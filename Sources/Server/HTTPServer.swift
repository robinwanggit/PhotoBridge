import Foundation
import Network
import Security

/// 内嵌 HTTPS 服务器。M1 阶段：监听一个端口，对任意 HTTP 请求返回一个简单 HTML 页面，
/// 用于验证"电脑浏览器能打开 App 提供的 HTTPS 地址"这条地基。
///
/// 后续里程碑会扩展为完整的相册浏览 / 选择 / 下载接口。
final class HTTPServer {
    private var listener: NWListener?
    /// 服务器专用后台队列（不能在主线程跑，否则 start() 的信号量会与
    /// listener 的状态回调互相阻塞造成死锁）。
    private let queue = DispatchQueue(label: "com.photobridge.server")

    /// 实际监听的端口（启动后确定，若默认端口被占用则顺延）。
    private(set) var port: UInt16 = 0

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
            let port = NWEndpoint.Port(rawValue: candidate)!
            let listener = try NWListener(using: params, on: port)
            // 同步等待绑定结果（后台队列回调信号量，不阻塞主线程）
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
            listener.start(queue: queue)
            // 最多等 5 秒，避免个别情况下既不 ready 也不 failed 导致卡死
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

    // MARK: - 连接处理

    private func handle(connection: NWConnection) {
        connection.start(queue: .main)
        // 循环读取，直到拿到请求头结束符 \r\n\r\n。
        // 用局部可变 buffer 被嵌套闭包捕获（不能用 inout，因为 receive 的闭包是 @escaping）。
        var buffer = Data()

        func readNext() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, isComplete, error in
                if error != nil {
                    connection.cancel()
                    return
                }
                if let data = data, !data.isEmpty {
                    buffer.append(data)
                }
                if buffer.range(of: Data("\r\n\r\n".utf8)) != nil {
                    // 请求头已收齐，丢弃 body，直接返回固定页面
                    self.respondOK(connection: connection)
                    return
                }
                if isComplete {
                    self.respondOK(connection: connection)
                    return
                }
                if buffer.count < 1024 * 1024 {
                    readNext()
                } else {
                    connection.cancel()
                }
            }
        }
        readNext()
    }

    private func respondOK(connection: NWConnection) {
        let html = Self.welcomeHTML
        let body = html.data(using: .utf8) ?? Data()
        var response = "HTTP/1.1 200 OK\r\n"
        response += "Content-Type: text/html; charset=utf-8\r\n"
        response += "Content-Length: \(body.count)\r\n"
        response += "Connection: close\r\n"
        response += "\r\n"
        var out = response.data(using: .utf8) ?? Data()
        out.append(body)
        connection.send(content: out, completion: .contentProcessed { _ in
            connection.cancel()
        })
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

    static let welcomeHTML = """
    <!DOCTYPE html>
    <html lang="zh-CN">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>PhotoBridge · 连接成功</title>
      <style>
        body { margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center;
               font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #f5f5f7; color: #1d1d1f; }
        .card { background: #fff; padding: 40px 48px; border-radius: 18px; box-shadow: 0 8px 32px rgba(0,0,0,0.08); text-align: center; max-width: 460px; }
        .dot { display: inline-block; width: 12px; height: 12px; border-radius: 50%; background: #34c759; margin-right: 8px; }
        h1 { font-size: 22px; margin: 0 0 12px; }
        p { margin: 8px 0; color: #6e6e73; font-size: 15px; line-height: 1.6; }
        code { background: #f0f0f3; padding: 2px 6px; border-radius: 5px; font-size: 13px; }
      </style>
    </head>
    <body>
      <div class="card">
        <h1><span class="dot"></span>PhotoBridge 已连接</h1>
        <p>电脑浏览器已成功访问手机 App 内嵌的 HTTPS 服务。</p>
        <p>M1 验证通过：<code>NWListener</code> + 自签证书 + 局域网 HTTPS 链路可用。</p>
        <p>后续里程碑将在此页面上构建相册浏览、选择与下载功能。</p>
      </div>
    </body>
    </html>
    """

    enum HTTPServerError: Error {
        case noAvailablePort
        case identityUnavailable
    }
}
