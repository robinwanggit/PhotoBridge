import Foundation
import Security

/// 从 App 内置的 .p12 文件加载服务器身份（证书 + 私钥），用于 HTTPS 服务的 TLS 握手。
///
/// M1 简化：.p12 与密码随包提供，所有安装共用同一张证书。
/// 后续应改为首次启动时为每台设备生成独立证书，避免私钥共享。
enum Certificate {
    /// 加载内置证书并返回 `SecIdentity`，供 `NWListener` 用作服务端 TLS 身份。
    static func loadServerIdentity() throws -> SecIdentity {
        guard let p12URL = Bundle.main.url(forResource: "cert", withExtension: "p12") else {
            throw CertificateError.missingBundleFile
        }
        let data = try Data(contentsOf: p12URL) as CFData
        let options: [CFString: Any] = [
            kSecImportExportPassphrase: "photobridge"
        ]
        var items: CFArray?
        let status = SecPKCS12Import(data, options as CFDictionary, &items)
        guard status == errSecSuccess,
              let array = items as? [[CFString: Any]],
              let first = array.first,
              let identity = first[kSecImportItemIdentity] as! SecIdentity? else {
            throw CertificateError.importFailed(status: status)
        }
        return identity
    }

    enum CertificateError: Error {
        case missingBundleFile
        case importFailed(status: OSStatus)
    }
}
