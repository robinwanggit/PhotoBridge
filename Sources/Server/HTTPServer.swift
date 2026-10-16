import Foundation
import Network
import Security

/// 内嵌 HTTPS 服务器。
/// - M1：验证电脑浏览器能打开 App 提供的 HTTPS 地址。
/// - M3：在 HTTPS 之上提供相册浏览接口 —— 页面、相册列表、资产分页、缩略图。
///
/// 后续里程碑会在此扩展选择与下载接口（M4/M5/M6）。
final class HTTPServer {
    private var listener: NWListener?

    /// listener 专用串行队列。start() 里用信号量同步等待绑定结果，
    /// 若与状态回调同在主线程会互相阻塞造成死锁，故放到独立后台队列。
    private let listenerQueue = DispatchQueue(label: "com.photobridge.listener")

    /// 连接处理专用并发队列。缩略图生成会阻塞等待 PhotoKit，
    /// 用并发队列才能同时服务浏览器并行发起的多个缩略图请求。
    private let connectionQueue = DispatchQueue(label: "com.photobridge.connection",
                                                attributes: .concurrent)

    /// 实际监听的端口（启动后确定，若默认端口被占用则顺延）。
    private(set) var port: UInt16 = 0

    // MARK: - 生命周期

    /// 启动服务器。返回成功绑定的端口。
    func start() throws -> UInt16 {
        let secIdentity = try Certificate.loadServerIdentity()
        // SecIdentity 需先转换为 sec_identity_t，才能交给 TLS 选项使用
        guard let identity = sec_identity_create(secIdentity) else {
            throw HTTPServerError.identityUnavailable
        }
        // NWParameters 没有 tlsOptions 属性，需要自己构建 NWProtocolTLS.Options
        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, identity)
        let params = NWParameters(tls: tlsOptions, tcp: .init())

        // 从 8443 开始尝试，被占用则顺延
        for candidate in stride(from: UInt16(8443), through: 8463, by: 1) {
            guard let port = NWEndpoint.Port(rawValue: candidate) else { continue }
            let listener = try NWListener(using: params, on: port)
            let semaphore = DispatchSemaphore(value: 0)
            var setupError: NWError?
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    semaphore.signal()
                case .failed(let error):
                    setupError = error
                    semaphore.signal()
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection: connection)
            }
            listener.start(queue: listenerQueue)
            // 最多等 5 秒，避免既不 ready 也不 failed 时卡死
            if semaphore.wait(timeout: .now() + 5) == .timedOut {
                listener.cancel()
                continue
            }
            if setupError != nil {
                listener.cancel()
                continue
            }
            self.listener = listener
            self.port = candidate
            return candidate
        }
        throw HTTPServerError.noAvailablePort
    }

    /// 停止服务器。
    func stop() {
        listener?.cancel()
        listener = nil
        port = 0
    }

    // MARK: - 连接与请求解析

    private func handle(connection: NWConnection) {
        connection.start(queue: connectionQueue)
        // 循环读取，直到拿到请求头结束符 \r\n\r\n。
        // 用局部可变 buffer 被嵌套闭包捕获（不能用 inout，因为 receive 的闭包是 @escaping）。
        var buffer = Data()

        func readNext() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, isComplete, error in
                if error != nil {
                    connection.cancel()
                    return
                }
                if let data = data, !data.isEmpty {
                    buffer.append(data)
                }
                let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8))
                if headerEnd != nil {
                    self.route(buffer: buffer, connection: connection)
                    return
                }
                if isComplete {
                    connection.cancel()
                    return
                }
                if buffer.count < 256 * 1024 {
                    readNext()
                } else {
                    connection.cancel()
                }
            }
        }
        readNext()
    }

    private struct HTTPRequest {
        let method: String
        let path: String
        let query: [String: String]
    }

    private static func parse(_ data: Data) -> HTTPRequest? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        guard let requestLine = text.components(separatedBy: "\r\n").first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0]).uppercased()
        let target = String(parts[1])
        let split = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let path = String(split[0])
        var query: [String: String] = [:]
        if split.count > 1 {
            query = parseQuery(String(split[1]))
        }
        return HTTPRequest(method: method, path: path, query: query)
    }

    private static func parseQuery(_ string: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in string.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let key = kv.first.map(String.init) else { continue }
            let rawValue = kv.count > 1 ? String(kv[1]) : ""
            let decodedKey = key.removingPercentEncoding ?? key
            let decodedValue = rawValue.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? rawValue
            result[decodedKey] = decodedValue
        }
        return result
    }

    // MARK: - 路由

    private func route(buffer: Data, connection: NWConnection) {
        guard let request = Self.parse(buffer) else {
            send(connection, status: "400 Bad Request",
                 contentType: "text/plain; charset=utf-8", body: Data("Bad Request".utf8))
            return
        }

        switch (request.method, request.path) {
        case ("GET", "/"), ("GET", "/index.html"):
            send(connection, contentType: "text/html; charset=utf-8", body: Data(WebApp.html.utf8))

        case ("GET", "/api/albums"):
            sendJSON(connection, PhotoLibrary.shared.albumsJSON())

        case ("GET", "/api/assets"):
            let album = request.query["album"] ?? "ALL"
            let offset = max(Int(request.query["offset"] ?? "") ?? 0, 0)
            let limit = min(max(Int(request.query["limit"] ?? "") ?? 80, 1), 300)
            sendJSON(connection, PhotoLibrary.shared.assetsJSON(album: album, offset: offset, limit: limit))

        case ("GET", "/api/thumb"):
            let id = request.query["id"] ?? ""
            let width = min(max(Int(request.query["w"] ?? "") ?? 320, 64), 2048)
            if let jpeg = PhotoLibrary.shared.thumbnailJPEG(id: id, width: width) {
                send(connection, contentType: "image/jpeg", body: jpeg, cacheSeconds: 3600)
            } else {
                send(connection, status: "404 Not Found",
                     contentType: "text/plain; charset=utf-8", body: Data("thumbnail unavailable".utf8))
            }

        case ("GET", "/favicon.ico"):
            send(connection, status: "204 No Content", contentType: "image/x-icon", body: Data())

        default:
            send(connection, status: "404 Not Found",
                 contentType: "text/plain; charset=utf-8", body: Data("Not Found".utf8))
        }
    }

    // MARK: - 响应

    private func send(_ connection: NWConnection,
                      status: String = "200 OK",
                      contentType: String,
                      body: Data,
                      cacheSeconds: Int = 0) {
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += cacheSeconds > 0
            ? "Cache-Control: private, max-age=\(cacheSeconds)\r\n"
            : "Cache-Control: no-store\r\n"
        header += "Connection: close\r\n\r\n"
        var out = Data(header.utf8)
        out.append(body)
        connection.send(content: out, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendJSON(_ connection: NWConnection, _ object: Any) {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [])) ?? Data("{}".utf8)
        send(connection, contentType: "application/json; charset=utf-8", body: data)
    }

    // MARK: - 工具

    /// 获取当前 WiFi 接口的 IPv4 地址，供 App 展示访问地址。
    static func localIPv4Address() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let interface = ptr?.pointee else { continue }
            let name = String(cString: interface.ifa_name)
            // 只取 WiFi 接口（en0），避免返回蜂窝或虚拟网卡地址
            guard name == "en0" else { continue }
            guard let ifaAddr = interface.ifa_addr else { continue }
            let addr = ifaAddr.pointee
            if addr.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(ifaAddr,
                            socklen_t(addr.sa_len),
                            &hostname,
                            socklen_t(hostname.count),
                            nil, 0, NI_NUMERICHOST)
                address = String(cString: hostname)
            }
        }
        return address
    }

    enum HTTPServerError: Error {
        case noAvailablePort
        case identityUnavailable
    }
}
