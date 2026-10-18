import Foundation
import SwiftUI

/// 应用内语言管理。
///
/// 用内置的 `.lproj/Localizable.strings` 子束在运行时切换语言，无需重启 App。
/// 切换后通过 `ObservableObject` 通知界面刷新；阿拉伯语等 RTL 语言会自动翻转布局方向。
final class Localization: ObservableObject {
    static let shared = Localization()

    /// 支持的语言（code + 母语名称）。顺序即「设置」里的展示顺序。
    static let supported: [(code: String, name: String)] = [
        ("zh-Hans", "简体中文"),
        ("zh-Hant", "繁體中文"),
        ("en",      "English"),
        ("fr",      "Français"),
        ("de",      "Deutsch"),
        ("ja",      "日本語"),
        ("ko",      "한국어"),
        ("it",      "Italiano"),
        ("es",      "Español"),
        ("hi",      "हिन्दी"),
        ("ar",      "العربية"),
        ("ru",      "Русский"),
        ("bn",      "বাংলা"),
        ("pt",      "Português"),
        ("id",      "Bahasa Indonesia"),
        ("th",      "ภาษาไทย"),
        ("mn",      "Монгол"),
        ("bo",      "བོད་སྐད།"),
    ]

    /// RTL（从右到左）语言。
    static let rtlLanguages: Set<String> = ["ar"]

    /// 当前语言代码。
    @Published private(set) var currentLanguage: String

    /// 当前语言对应的字符串子束。
    private var bundle: Bundle

    private init() {
        let saved = UserDefaults.standard.string(forKey: "AppLanguage")
        let code = saved ?? Self.detectSystemLanguage()
        currentLanguage = code
        bundle = Self.bundle(for: code)
    }

    // MARK: - 翻译

    /// 取 key 对应的本地化字符串；找不到时返回 key 本身。
    func tr(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    // MARK: - 切换语言

    /// 切换到指定语言，并持久化。`nil` 表示跟随系统。
    func setLanguage(_ code: String?) {
        let resolved: String
        if let code = code, !code.isEmpty {
            resolved = code
        } else {
            resolved = Self.detectSystemLanguage()
        }
        currentLanguage = resolved
        bundle = Self.bundle(for: resolved)
        if let code = code {
            UserDefaults.standard.set(code, forKey: "AppLanguage")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppLanguage")
        }
        // 同时写入 AppleLanguages，让系统权限弹窗等也用该语言。
        UserDefaults.standard.set([resolved], forKey: "AppleLanguages")
    }

    /// 当前是否为 RTL 布局。
    var isRTL: Bool {
        Self.rtlLanguages.contains(currentLanguage)
    }

    /// 当前语言的母语名称。
    var currentLanguageName: String {
        Self.supported.first { $0.code == currentLanguage }?.name ?? currentLanguage
    }

    // MARK: - 工具

    /// 从系统首选语言里挑一个本应用支持的；都不支持则回退英语。
    private static func detectSystemLanguage() -> String {
        let supportedCodes = Set(supported.map { $0.code })
        for pref in Locale.preferredLanguages {
            // 完整匹配：zh-Hans
            if supportedCodes.contains(pref) { return pref }
            // 仅语言代码：zh-Hans-CN → zh-Hans / zh
            let dash = pref.split(separator: "-")
            if dash.count >= 2 {
                let base = String(dash[0]) + "-" + String(dash[1])
                if supportedCodes.contains(base) { return base }
            }
            let lang = String(dash[0])
            if supportedCodes.contains(lang) { return lang }
        }
        return "en"
    }

    /// 加载指定语言代码的 `.lproj` 子束；找不到回退主束。
    private static func bundle(for code: String) -> Bundle {
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let b = Bundle(path: path) {
            return b
        }
        return .main
    }
}
