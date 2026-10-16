import Foundation
import Security

/// 从 App 内置的自签证书加载服务器身份（证书 + 私钥），用于 HTTPS 服务的 TLS 握手。
///
/// 证书以 base64 文本内嵌在源码中（不再依赖二进制资源文件），避免二进制文件在
/// 传输 / 替换环节出问题，保证 App 里用的永远就是下面这份内容。
///
/// M1 简化：所有安装共用同一张证书（口令 photobridge）。后续应改为首次启动时
/// 为每台设备生成独立证书，避免私钥共享。
enum Certificate {
    /// 内置的 PKCS#12。必须使用 Apple Security 框架支持的传统算法：
    /// SHA-1 MAC + PBE-SHA1-3DES —— OpenSSL 3 默认的 SHA-256 MAC / AES-256 会导致
    /// SecPKCS12Import 返回 errSecDecode(-26275) 而导入失败。
    private static let p12Base64 = """
    MIIDkgIBAzCCA1gGCSqGSIb3DQEHAaCCA0kEggNFMIIDQTCCAjcGCSqGSIb3DQEH
    BqCCAigwggIkAgEAMIICHQYJKoZIhvcNAQcBMBwGCiqGSIb3DQEMAQMwDgQI/6W9
    2BZ6x2gCAggAgIIB8G7n87lGyURYelAvJOUcisx/XMEgnzv556aS0P4PuxY+z2Rq
    PjQqmJgnLWE5/SoP0+KV+08z03JMnGgA8Bsn/BbpBq+7BeqyBNJ67fWsAB4nAk0c
    CHqgjWzE5KHp8KsTKt5qd4loNJPRQBhBus50Nc/J/8LCFKfAmXfhOcu+z3FIQxPF
    6J+TkCnN3jMczzcK9Vg2vaVQtvpCo/6dERdnNaHvaQ2R47K2DlVvHcGYjIa6c93z
    uMpDIfrdJGQcg+GdlSIfchHreI7Qy9gbYwnTYn+zQ8O+IbFBDvrZVBkilCpN00GC
    Dutr4ik9bh590tcRJXy37bCgufjMN3h5JZCLwfuDoKJZI4GoQZoon25yuHL14LsL
    NxQ87NIX9wKkHe9DX8S0LscD4xTZiXGO3/nB0viulxMcHhWMjMURe6bZWW5eVYlf
    XDjHPo8ntPx2adj3z02qRgDHQrdVWxVG67hf0tQK3oMiW7Kef2d+uosbs65o3y6t
    ABRe3RmVQHGHjUGrbjoFnfLAEgv+fq2Y4dNtGHJMVBl0+Z8deTVuVHCCoYP62yXS
    hqk8AgAkL61IsR6Vy6Ft2FrV6jvdit0qTjhBo1NtIpbGGeuW/n/sCNPs6dqGmo+B
    Lh/2obVfhLxj2TsrsxS6SXPOkDPj9WEvbqvICAIwggECBgkqhkiG9w0BBwGggfQE
    gfEwge4wgesGCyqGSIb3DQEMCgECoIG0MIGxMBwGCiqGSIb3DQEMAQMwDgQINxsf
    9PayTHcCAggABIGQvOGKS2kRFug1wXYY1cYIAXaO/4HIRs3QtwzuxzP0SI/PniLr
    0+Tv96CGAjxQp0fETcIUWJQvNP2lw4lakhoeTUSB+FNGXB2W10NuhzFOxV705O0r
    1J07LYYPYBb9f5MQCnWl3j2D0OeRl2rKdZhR+7gQP4ndANd5zlmFa2vZRfFVYPqB
    nS4XX5xRRL8EK8MRMSUwIwYJKoZIhvcNAQkVMRYEFGWSubRXnGctp6DCLzYuLSM0
    7RJ1MDEwITAJBgUrDgMCGgUABBSCTvIw/xuEDNs+3YQABvTFLOIuTwQINZ68YfFC
    VhMCAggA
    """

    /// 加载内置证书并返回 `SecIdentity`，供 `NWListener` 用作服务端 TLS 身份。
    static func loadServerIdentity() throws -> SecIdentity {
        guard let data = Data(base64Encoded: p12Base64, options: .ignoreUnknownCharacters) else {
            throw CertificateError.invalidBase64
        }
        let options: [CFString: Any] = [
            kSecImportExportPassphrase: "photobridge"
        ]
        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess,
              let array = items as? [[CFString: Any]],
              let first = array.first,
              let identity = first[kSecImportItemIdentity] as! SecIdentity? else {
            throw CertificateError.importFailed(status: status)
        }
        return identity
    }

    enum CertificateError: Error, LocalizedError {
        case invalidBase64
        case importFailed(status: OSStatus)

        var errorDescription: String? {
            switch self {
            case .invalidBase64:
                return "内置证书解码失败（base64 内容异常）"
            case .importFailed(let status):
                return "证书导入失败，系统错误码 \(status)"
            }
        }
    }
}
