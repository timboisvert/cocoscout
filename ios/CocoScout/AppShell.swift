import HotwireNative
import UIKit

/// One tab or menu item as the server describes it (NativeAppHelper):
/// icon is an SF Symbol name; badge is a count.
struct TabSpec: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let path: String
    let icon: String
    var badge: Int?

    var signature: String { "\(id)|\(title)|\(path)|\(icon)" }
}

/// How the app gets around. Being tried out side by side (DEBUG builds can
/// switch from the menu, or by shaking the phone: Simulator → Device → Shake).
enum NavStyle: String, CaseIterable, Identifiable {
    /// The server's tabs: Home, Tasks, Messages, Door, More.
    case tabs
    /// No tab bar: one floating button opens a full-screen menu of everything.
    case button
    /// Home, Messages and Door as tabs, plus a Menu tab that opens the menu.
    case mix

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tabs: "Tabs"
        case .button: "One button"
        case .mix: "Mix"
        }
    }
}

/// How a page picked from the menu replaces the one on screen. Being tried
/// out (DEBUG builds switch from the menu).
enum MenuTransition: String, CaseIterable, Identifiable {
    /// iOS's own cross-fade.
    case fade
    /// The new page slides in from the right, the old one off to the left.
    case slide
    /// The new page rises up from the bottom.
    case slideUp
    case none

    static var current: MenuTransition {
        MenuTransition(rawValue: UserDefaults.standard.string(forKey: "MenuTransition") ?? "") ?? .fade
    }

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fade: "Fade"
        case .slide: "Slide"
        case .slideUp: "Slide up"
        case .none: "None"
        }
    }

    /// A Core Animation transition to run instead of iOS's fade (nil: use the fade, or nothing).
    var coreAnimation: CATransition? {
        let transition = CATransition()
        transition.duration = 0.3
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        switch self {
        case .slide:
            transition.type = .push
            transition.subtype = .fromRight
        case .slideUp:
            transition.type = .moveIn
            transition.subtype = .fromTop
        case .fade, .none:
            return nil
        }
        return transition
    }
}

/// The app's frame around the web pages. The server sends the person's tabs
/// and menu on every page load (TabsComponent); this rebuilds the frame only
/// when what it shows actually changes, and keeps the badges current. No tabs
/// means signed out: a single sign-in screen, nothing else.
@MainActor
final class AppShell {
    static let shared = AppShell()

    let tabBarController = ShellTabBarController()
    private(set) var tabs: [TabSpec] = []
    private(set) var menu: [TabSpec] = []
    private(set) var loadedTabs: [TabSpec] = []
    private var loadedSignature: [String]?

    private(set) var style = NavStyle(rawValue: UserDefaults.standard.string(forKey: "NavStyle") ?? "") ?? .tabs
    private lazy var menuButton = MenuButton { [weak self] in self?.showMenu() }

    private static let tabsKey = "AppShell.tabs"
    private static let menuKey = "AppShell.menu"

    /// Starts with last time's tabs and menu, so a signed-in person doesn't
    /// see the frame change on every launch.
    func start() {
        tabs = Self.cached(Self.tabsKey)
        menu = Self.cached(Self.menuKey)
        tabBarController.onMenuTab = { [weak self] in self?.showMenu() }
        rebuild()
    }

    func update(tabs newTabs: [TabSpec], menu newMenu: [TabSpec]) {
        tabs = newTabs
        menu = newMenu
        Self.cache(newTabs, Self.tabsKey)
        Self.cache(newMenu, Self.menuKey)
        if barTabs().map(\.signature) + [style.rawValue] != loadedSignature {
            rebuild()
        } else {
            applyBadges()
        }
    }

    func setStyle(_ newStyle: NavStyle) {
        guard newStyle != style else { return }
        style = newStyle
        UserDefaults.standard.set(newStyle.rawValue, forKey: "NavStyle")
        rebuild()
    }

    // MARK: The menu

    func showMenu() {
        guard !menu.isEmpty else { return }
        let sheet = MenuViewController(items: menu, style: style) { [weak self] action in
            self?.handle(action)
        }
        topViewController().present(sheet, animated: true)
    }

    private func handle(_ action: MenuViewController.Action) {
        switch action {
        case .open(let item):
            tabBarController.dismiss(animated: true) { self.open(item) }
        case .signOut:
            tabBarController.dismiss(animated: true) {
                self.tabBarController.activeNavigator.route(AppConfig.url("/signout"))
            }
        case .style(let newStyle):
            tabBarController.dismiss(animated: true) { self.setStyle(newStyle) }
        }
    }

    /// A menu item that's also a tab selects the tab. Anything else becomes
    /// the whole screen: in one-button style the only screen; in mix style the
    /// Menu tab's screen, so the tab bar shows you're somewhere off the menu.
    private func open(_ item: TabSpec) {
        if let index = loadedTabs.firstIndex(where: { $0.id == item.id }) {
            select(index)
            return
        }
        let url = AppConfig.url(item.path)
        switch style {
        case .button:
            replaceRoot(of: tabBarController.activeNavigator, with: url)
        case .mix:
            if let menuIndex = loadedTabs.firstIndex(where: { $0.id == "menu" }) {
                select(menuIndex, start: false)
            }
            replaceRoot(of: tabBarController.activeNavigator, with: url)
        case .tabs:
            tabBarController.activeNavigator.route(url)
        }
    }

    /// Swaps the whole screen for the picked page, with the chosen transition:
    /// iOS's fade, our own slide (Hotwire's animation off), or nothing.
    private func replaceRoot(of navigator: Navigator, with url: URL) {
        let transition = MenuTransition.current
        var properties = Hotwire.config.pathConfiguration.properties(for: url)
        properties["presentation"] = "replace_root"
        properties["animated"] = transition == .fade
        if let animation = transition.coreAnimation {
            navigator.rootViewController.view.layer.add(animation, forKey: kCATransition)
        }
        navigator.route(VisitProposal(url: url, options: VisitOptions(action: .advance), properties: properties))
    }

    func setMenuTransition(_ transition: MenuTransition) {
        UserDefaults.standard.set(transition.rawValue, forKey: "MenuTransition")
    }

    private func select(_ index: Int, start: Bool = true) {
        if #available(iOS 18.0, *) {
            tabBarController.selectedTab = tabBarController.tabs.first { $0.identifier == loadedTabs[index].id }
        } else {
            tabBarController.selectedIndex = index
        }
        if start {
            tabBarController.activeNavigator.start()
        }
    }

    // MARK: Building the frame

    /// What the tab bar holds in the current style (empty: signed out).
    private func barTabs() -> [TabSpec] {
        guard !tabs.isEmpty else { return [] }
        switch style {
        case .tabs:
            return tabs
        case .button:
            return [TabSpec(id: "main", title: "Home", path: "/my", icon: "house")]
        case .mix:
            let kept = menu.filter { ["home", "messages", "door"].contains($0.id) }
            return kept + [TabSpec(id: "menu", title: "Menu", path: "/my/account", icon: "square.grid.2x2")]
        }
    }

    private func rebuild() {
        let next = barTabs()
        loadedTabs = next
        loadedSignature = next.map(\.signature) + [style.rawValue]
        tabBarController.menuTabID = style == .mix ? "menu" : nil

        if next.isEmpty {
            // /my sends a signed-out person to sign in; signing in sends the tabs.
            tabBarController.load([HotwireTab(id: "start", title: "CocoScout", image: nil, url: AppConfig.url("/my"))])
            setTabBarHidden(true)
        } else {
            tabBarController.load(next.map {
                HotwireTab(id: $0.id, title: $0.title, image: UIImage(systemName: $0.icon), url: AppConfig.url($0.path))
            })
            setTabBarHidden(style == .button)
        }

        if menuButton.superview == nil {
            menuButton.install(in: tabBarController.view)
        }
        menuButton.isHidden = next.isEmpty || style != .button
        tabBarController.view.bringSubviewToFront(menuButton)
        applyBadges()
    }

    private func setTabBarHidden(_ hidden: Bool) {
        if #available(iOS 18.0, *) {
            tabBarController.isTabBarHidden = hidden
        } else {
            tabBarController.tabBar.isHidden = hidden
        }
    }

    private func applyBadges() {
        let byID = Dictionary(menu.map { ($0.id, $0.badge ?? 0) }, uniquingKeysWith: { first, _ in first })
        let onBar = Set(loadedTabs.map(\.id))
        let offBar = menu.filter { !onBar.contains($0.id) }.reduce(0) { $0 + ($1.badge ?? 0) }

        for (index, spec) in loadedTabs.enumerated() {
            let count: Int
            switch (style, spec.id) {
            case (.tabs, _): count = spec.badge ?? 0
            case (.mix, "menu"): count = offBar
            default: count = byID[spec.id] ?? 0
            }
            let value = Self.badgeText(count)
            if #available(iOS 18.0, *) {
                tabBarController.tabs.first { $0.identifier == spec.id }?.badgeValue = value
            } else if let controllers = tabBarController.viewControllers, controllers.indices.contains(index) {
                controllers[index].tabBarItem.badgeValue = value
            }
        }
        menuButton.badge = Self.badgeText(menu.reduce(0) { $0 + ($1.badge ?? 0) })
    }

    private func topViewController() -> UIViewController {
        var top: UIViewController = tabBarController
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    static func badgeText(_ count: Int) -> String? {
        count > 0 ? (count > 99 ? "99+" : String(count)) : nil
    }

    private static func cached(_ key: String) -> [TabSpec] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let specs = try? JSONDecoder().decode([TabSpec].self, from: data) else { return [] }
        return specs
    }

    private static func cache(_ specs: [TabSpec], _ key: String) {
        let withoutBadges = specs.map { TabSpec(id: $0.id, title: $0.title, path: $0.path, icon: $0.icon) }
        UserDefaults.standard.set(try? JSONEncoder().encode(withoutBadges), forKey: key)
    }
}

/// The tab bar, able to catch a tap on the Menu tab (mix style) and open the
/// menu instead of switching to it.
final class ShellTabBarController: HotwireTabBarController {
    var menuTabID: String?
    var onMenuTab: (() -> Void)?

    convenience init() {
        self.init(navigatorDelegate: nil, lazyLoadTabs: true)
    }

    @objc(tabBarController:shouldSelectViewController:)
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        guard let menuTabID,
              let index = viewControllers?.firstIndex(of: viewController),
              AppShell.shared.loadedTabs.indices.contains(index),
              AppShell.shared.loadedTabs[index].id == menuTabID else { return true }
        onMenuTab?()
        return false
    }

    @available(iOS 18.0, *)
    @objc(tabBarController:shouldSelectTab:)
    func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
        guard let menuTabID, tab.identifier == menuTabID else { return true }
        onMenuTab?()
        return false
    }
}

#if DEBUG
/// Shake to switch navigation styles while trying them out (Simulator:
/// Device → Shake, or ⌃⌘Z).
final class ShakeWindow: UIWindow {
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            StylePicker.show()
        } else {
            super.motionEnded(motion, with: event)
        }
    }
}

enum StylePicker {
    @MainActor static func show() {
        let shell = AppShell.shared
        guard shell.tabBarController.presentedViewController == nil else { return }
        let sheet = UIAlertController(title: "Navigation", message: nil, preferredStyle: .actionSheet)
        for style in NavStyle.allCases {
            let title = style == shell.style ? "\(style.label) (now)" : style.label
            sheet.addAction(UIAlertAction(title: title, style: .default) { _ in shell.setStyle(style) })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        shell.tabBarController.present(sheet, animated: true)
    }
}
#endif
