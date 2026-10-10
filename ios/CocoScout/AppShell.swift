import HotwireNative
import UIKit

/// One tab as the server describes it (NativeAppHelper#native_tabs).
/// icon is an SF Symbol name; badge is a count.
struct TabSpec: Codable, Equatable {
    let id: String
    let title: String
    let path: String
    let icon: String
    var badge: Int?

    func isSameTab(as other: TabSpec) -> Bool {
        id == other.id && title == other.title && path == other.path && icon == other.icon
    }
}

/// The app's tab bar. The server decides the tabs on every page load
/// (TabsComponent); this rebuilds the bar only when they actually change, and
/// keeps the badges current. No tabs means signed out: a single sign-in screen
/// with the tab bar hidden.
@MainActor
final class AppShell {
    static let shared = AppShell()

    let tabBarController = HotwireTabBarController(lazyLoadTabs: true)
    private(set) var specs: [TabSpec] = []

    private static let cacheKey = "AppShell.tabs"

    /// Starts with the tabs from last time, so a signed-in person doesn't see
    /// the bar change on every launch.
    func start() {
        load(Self.cachedSpecs())
    }

    func update(_ newSpecs: [TabSpec]) {
        let changed = newSpecs.count != specs.count || zip(newSpecs, specs).contains { !$0.isSameTab(as: $1) }
        if changed {
            load(newSpecs)
            Self.cache(newSpecs)
        } else {
            specs = newSpecs
        }
        applyBadges()
    }

    private func load(_ newSpecs: [TabSpec]) {
        specs = newSpecs
        if newSpecs.isEmpty {
            // /my sends a signed-out person to sign in; signing in sends the tabs.
            tabBarController.load([HotwireTab(id: "start", title: "CocoScout", image: nil, url: AppConfig.url("/my"))])
            setTabBarHidden(true)
        } else {
            tabBarController.load(newSpecs.map {
                HotwireTab(id: $0.id, title: $0.title, image: UIImage(systemName: $0.icon), url: AppConfig.url($0.path))
            })
            setTabBarHidden(false)
        }
    }

    private func setTabBarHidden(_ hidden: Bool) {
        if #available(iOS 18.0, *) {
            tabBarController.isTabBarHidden = hidden
        } else {
            tabBarController.tabBar.isHidden = hidden
        }
    }

    private func applyBadges() {
        for (index, spec) in specs.enumerated() {
            let count = spec.badge ?? 0
            let value = count > 0 ? (count > 99 ? "99+" : String(count)) : nil
            if #available(iOS 18.0, *) {
                tabBarController.tabs.first { $0.identifier == spec.id }?.badgeValue = value
            } else if let controllers = tabBarController.viewControllers, controllers.indices.contains(index) {
                controllers[index].tabBarItem.badgeValue = value
            }
        }
    }

    private static func cachedSpecs() -> [TabSpec] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let specs = try? JSONDecoder().decode([TabSpec].self, from: data) else { return [] }
        return specs
    }

    private static func cache(_ specs: [TabSpec]) {
        let withoutBadges = specs.map { TabSpec(id: $0.id, title: $0.title, path: $0.path, icon: $0.icon) }
        UserDefaults.standard.set(try? JSONEncoder().encode(withoutBadges), forKey: cacheKey)
    }
}
