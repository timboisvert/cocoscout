import UIKit

/// Where the app points and how it looks.
///
/// The Simulator talks to the Rails server on this Mac (it reaches it at
/// localhost); a phone, whether run from Xcode or installed from TestFlight,
/// talks to cocoscout.com. Either can be pointed elsewhere for a run with a
/// launch argument:
///
///     xcrun simctl launch booted com.cocoscout.app -BaseURL https://cocoscout.com
enum AppConfig {
    static let baseURL: URL = {
        if let override = UserDefaults.standard.string(forKey: "BaseURL"),
           let url = URL(string: override) {
            return url
        }
        #if DEBUG && targetEnvironment(simulator)
        return URL(string: "http://localhost:3000")!
        #else
        return URL(string: "https://cocoscout.com")!
        #endif
    }()

    /// Which navigation this build draws. V1 builds are 1 and read the
    /// original page rules; V1.1 builds (production mode, the universal
    /// Messages and Notifications icons) are 2. The server reads it from the
    /// user agent (NativeAppVersion) and only sends generation-2 menus and
    /// pages to builds that say so, so V1 installs never see them.
    static let navGeneration = 2

    /// Each generation reads its own page rules, so a change for one never
    /// reaches phones running the other.
    static let pathConfigurationURL = baseURL.appendingPathComponent("hotwire-native/nav-\(navGeneration)/path-configuration.json")

    /// "CocoScout/1.1 (12; nav 2)", ahead of Hotwire Native's own user agent.
    static let userAgentPrefix: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "CocoScout/\(version) (\(build); nav \(navGeneration))"
    }()

    static func url(_ path: String) -> URL {
        URL(string: path, relativeTo: baseURL)!.absoluteURL
    }

    /// CocoScout pink: Tailwind v4's pink-500, as the website compiles it.
    static let pink = UIColor(red: 0xF6 / 255, green: 0x33 / 255, blue: 0x9A / 255, alpha: 1)

    /// Coustard, the website's title face (bundled; listed in Info.plist's
    /// UIAppFonts). Falls back to the system font if it ever fails to load.
    static func coustard(_ size: CGFloat) -> UIFont {
        if let font = UIFont(name: "Coustard-Regular", size: size) { return font }
        if let name = UIFont.fontNames(forFamilyName: "Coustard").first, let font = UIFont(name: name, size: size) { return font }
        return .systemFont(ofSize: size, weight: .semibold)
    }
}
