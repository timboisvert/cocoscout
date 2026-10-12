import UIKit

/// Where the app points and how it looks.
///
/// Debug builds talk to the Rails server on this Mac (the Simulator reaches it
/// at localhost); release builds talk to cocoscout.com. Either can be pointed
/// elsewhere for a run with a launch argument:
///
///     xcrun simctl launch booted com.cocoscout.app -BaseURL https://cocoscout.com
enum AppConfig {
    static let baseURL: URL = {
        if let override = UserDefaults.standard.string(forKey: "BaseURL"),
           let url = URL(string: override) {
            return url
        }
        #if DEBUG
        return URL(string: "http://localhost:3000")!
        #else
        return URL(string: "https://cocoscout.com")!
        #endif
    }()

    static let pathConfigurationURL = baseURL.appendingPathComponent("hotwire-native/path-configuration.json")

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
