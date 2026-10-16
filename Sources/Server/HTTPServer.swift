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
        // 循环读取，直到拿到完整的请求（请求头 + Content-Length 指定的请求体）。
        // 用局部可变 buffer 被嵌套闭包捕获（不能用 inout，因为 receive 的闭包是 @escaping）。
        var buffer = Data()

        // 请求头已到齐且请求体也读满时返回 true。
        func routeIfReady() -> Bool {
            guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return false }
            let headerData = buffer.subdata(in: 0..<headerEnd.lowerBound)
            let bodyLength = Self.contentLength(in: headerData)
            let totalNeeded = headerEnd.upperBound + bodyLength
            if buffer.count < totalNeeded { return false }
            let bodyStart = headerEnd.upperBound
            let body = buffer.count > bodyStart
                ? buffer.subdata(in: bodyStart..<min(totalNeeded, buffer.count))
                : Data()
            route(headerData: headerData, body: body, connection: connection)
            return true
        }

        func readNext() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if error != nil {
                    connection.cancel()
                    return
                }
                if let data = data, !data.isEmpty {
                    buffer.append(data)
                }
                if routeIfReady() { return }
                if isComplete {
                    connection.cancel()
                    return
                }
                // 上限放宽到 32MB：整选整个图库后提交 ZIP 任务时，请求体会较大
                if buffer.count < 32 * 1024 * 1024 {
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
        let body: Data
    }

    private static func parse(header data: Data, body: Data) -> HTTPRequest? {
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
        return HTTPRequest(method: method, path: path, query: query, body: body)
    }

    /// 从请求头读取 Content-Length（找不到或非法则按 0 处理）。
    private static func contentLength(in header: Data) -> Int {
        guard let text = String(data: header, encoding: .utf8) else { return 0 }
        for line in text.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            guard lower.hasPrefix("content-length:") else { continue }
            let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
            return max(Int(value) ?? 0, 0)
        }
        return 0
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

    private func route(headerData: Data, body: Data, connection: NWConnection) {
        guard let request = Self.parse(header: headerData, body: body) else {
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

        case ("GET", "/api/ids"):
            let album = request.query["album"] ?? "ALL"
            let from = Double(request.query["from"] ?? "")
            let to = Double(request.query["to"] ?? "")
            sendJSON(connection, PhotoLibrary.shared.assetIDsJSON(album: album, from: from, to: to))

        case ("GET", "/api/thumb"):
            let id = request.query["id"] ?? ""
            let width = min(max(Int(request.query["w"] ?? "") ?? 320, 64), 2048)
            if let jpeg = PhotoLibrary.shared.thumbnailJPEG(id: id, width: width) {
                send(connection, contentType: "image/jpeg", body: jpeg, cacheSeconds: 3600)
            } else {
                send(connection, status: "404 Not Found",
                     contentType: "text/plain; charset=utf-8", body: Data("thumbnail unavailable".utf8))
            }

        case ("GET", "/api/export"):
            handleExport(request: request, connection: connection)

        case ("POST", "/api/zip"):
            handleZip(request: request, connection: connection)

        case ("GET", "/favicon.ico"):
            send(connection, status: "204 No Content", contentType: "image/x-icon", body: Data())

        default:
            send(connection, status: "404 Not Found",
                 contentType: "text/plain; charset=utf-8", body: Data("Not Found".utf8))
        }
    }

    // MARK: - 导出：单个文件

    /// `GET /api/export?id=<assetId>&mode=original|copy`
    /// 单文件下载，供前端「下载到文件夹」直接写盘。
    private func handleExport(request: HTTPRequest, connection: NWConnection) {
        let id = request.query["id"] ?? ""
        let mode = ExportMode(rawValue: request.query["mode"] ?? "original") ?? .original
        do {
            let file = try AssetExporter.export(assetId: id, mode: mode)
            sendExport(connection, file: file)
        } catch {
            sendJSON(connection, status: "500 Internal Server Error",
                     ["error": errorDescription(error)])
        }
    }

    // MARK: - 导出：ZIP

    /// `POST /api/zip`，JSON 请求体 `{ ids: [String], mode: "original"|"copy" }`。
    /// 服务端就地打包成临时 ZIP 后流式下发，供前端「下载为 ZIP」。
    private func handleZip(request: HTTPRequest, connection: NWConnection) {
        guard let payload = Self.zipPayload(from: request.body) else {
            sendJSON(connection, status: "400 Bad Request", ["error": "请求内容无法解析"])
            return
        }
        guard !payload.ids.isEmpty else {
            sendJSON(connection, status: "400 Bad Request", ["error": "未选择任何项目"])
            return
        }
        let mode = ExportMode(rawValue: payload.mode) ?? .original
        do {
            let url = try AssetExporter.packZip(ids: payload.ids, mode: mode)
            let suffix = (mode == .copy) ? "copy" : "original"
            sendFile(connection, fileURL: url, contentType: "application/zip",
                     downloadName: "PhotoBridge-\(suffix).zip", deleteAfterSend: true)
        } catch {
            sendJSON(connection, status: "500 Internal Server Error",
                     ["error": errorDescription(error)])
        }
    }

    private static func zipPayload(from body: Data) -> (ids: [String], mode: String)? {
        guard !body.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }
        let ids = (object["ids"] as? [String]) ?? []
        let mode = (object["mode"] as? String) ?? "original"
        return (ids, mode)
    }

    private func errorDescription(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let text = localized.errorDescription {
            return text
        }
        return error.localizedDescription
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
        sendJSON(connection, status: "200 OK", object)
    }

    private func sendJSON(_ connection: NWConnection, status: String, _ object: Any) {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [])) ?? Data("{}".utf8)
        send(connection, status: status, contentType: "application/json; charset=utf-8", body: data)
    }

    // MARK: - 文件响应

    /// 单个导出文件：整体下发，并通过响应头告知前端文件名与日期目录。
    private func sendExport(_ connection: NWConnection, file: ExportedFile) {
        let fallback = "photo.bin"
        let encodedName = Self.percentEncode(file.filename)
        let encodedPath = Self.percentEncode(file.relativePath)

        var header = "HTTP/1.1 200 OK\r\n"
        header += "Content-Type: \(file.mimeType)\r\n"
        header += "Content-Length: \(file.data.count)\r\n"
        header += "Content-Disposition: attachment; filename=\"\(fallback)\"; filename*=UTF-8''\(encodedName)\r\n"
        header += "X-Photo-Path: \(encodedPath)\r\n"
        header += "Cache-Control: no-store\r\n"
        header += "Connection: close\r\n\r\n"

        var out = Data(header.utf8)
        out.append(file.data)
        connection.send(content: out, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// 从磁盘文件流式下发（分块读取，避免整份驻留内存）。下发完可选删除临时文件。
    private func sendFile(_ connection: NWConnection,
                          fileURL: URL,
                          contentType: String,
                          downloadName: String?,
                          deleteAfterSend: Bool) {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            if deleteAfterSend { try? FileManager.default.removeItem(at: fileURL) }
            send(connection, status: "500 Internal Server Error",
                 contentType: "text/plain; charset=utf-8", body: Data("file unavailable".utf8))
            return
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? UInt64 ?? 0

        var header = "HTTP/1.1 200 OK\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(size)\r\n"
        if let name = downloadName {
            let encoded = Self.percentEncode(name)
            header += "Content-Disposition: attachment; filename=\"\(name)\"; filename*=UTF-8''\(encoded)\r\n"
        }
        header += "Cache-Control: no-store\r\n"
        header += "Connection: close\r\n\r\n"

        func cleanup() {
            try? handle.close()
            if deleteAfterSend { try? FileManager.default.removeItem(at: fileURL) }
        }

        func pump() {
            let chunk = try? handle.read(upToCount: 256 * 1024)
            guard let chunk = chunk, !chunk.isEmpty else {
                cleanup()
                connection.cancel()
                return
            }
            connection.send(content: chunk, completion: .contentProcessed { error in
                if error != nil {
                    cleanup()
                    connection.cancel()
                    return
                }
                pump()
            })
        }

        connection.send(content: Data(header.utf8), completion: .contentProcessed { error in
            if error != nil {
                cleanup()
                connection.cancel()
                return
            }
            pump()
        })
    }

    /// 对响应头里的非 ASCII 文本做百分号编码，避免头部校验失败。
    private static func percentEncode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~!*'()")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
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
