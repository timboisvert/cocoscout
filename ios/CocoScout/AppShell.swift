import HotwireNative
import UIKit

/// One menu tile as the server describes it (NativeAppHelper#native_menu):
/// icon is an SF Symbol name; badge is a count.
struct MenuItem: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let path: String
    let icon: String
    var badge: Int?
}

/// Who's signed in, for the menu's pink card (NativeAppHelper#native_person).
struct MenuPerson: Codable, Equatable {
    let name: String
    let email: String
    let initials: String
    let headshotPath: String?

    enum CodingKeys: String, CodingKey {
        case name, email, initials
        case headshotPath = "headshot_path"
    }

    var headshotURL: URL? { headshotPath.map { AppConfig.url($0) } }
}

/// The app's frame around the web pages: one screen, no tab bar, and a
/// floating pink button that opens the full-screen menu. Picking from the
/// menu replaces the screen (with iOS's cross-fade). The server sends the menu
/// on every page load (MenuComponent); an empty menu means signed out, and
/// the app shows just the sign-in screen, without the button.
@MainActor
final class AppShell {
    static let shared = AppShell()

    let tabBarController = HotwireTabBarController(lazyLoadTabs: true)
    private(set) var menu: [MenuItem] = []
    private(set) var person: MenuPerson?
    private var loadedSignedIn: Bool?
    private lazy var menuButton = MenuButton { [weak self] in self?.showMenu() }

    private static let menuKey = "AppShell.menu"
    private static let personKey = "AppShell.person"

    /// Starts with last time's menu, so the button is there right away for
    /// someone still signed in.
    func start() {
        menu = Self.cached([MenuItem].self, Self.menuKey) ?? []
        person = Self.cached(MenuPerson.self, Self.personKey)
        rebuild()
    }

    func update(menu newMenu: [MenuItem], person newPerson: MenuPerson?) {
        menu = newMenu
        person = newPerson
        Self.cache(newMenu.map { MenuItem(id: $0.id, title: $0.title, path: $0.path, icon: $0.icon) }, Self.menuKey)
        Self.cache(newPerson, Self.personKey)
        // Signing in or out starts the screen afresh; otherwise only the badge changes.
        if !newMenu.isEmpty != loadedSignedIn {
            rebuild()
        } else {
            menuButton.badge = Self.badgeText(newMenu.reduce(0) { $0 + ($1.badge ?? 0) })
        }
    }

    // MARK: The menu

    func showMenu() {
        guard !menu.isEmpty else { return }
        let sheet = MenuViewController(items: menu, person: person) { [weak self] action in
            self?.handle(action)
        }
        topViewController().present(sheet, animated: true)
    }

    private func handle(_ action: MenuViewController.Action) {
        tabBarController.dismiss(animated: true) {
            switch action {
            case .open(let item):
                self.replaceScreen(with: AppConfig.url(item.path))
            case .signOut:
                self.tabBarController.activeNavigator.route(AppConfig.url("/signout"))
            }
        }
    }

    /// The picked page becomes the whole screen (no back button), with iOS's
    /// cross-fade.
    private func replaceScreen(with url: URL) {
        var properties = Hotwire.config.pathConfiguration.properties(for: url)
        properties["presentation"] = "replace_root"
        tabBarController.activeNavigator.route(VisitProposal(url: url, options: VisitOptions(action: .advance), properties: properties))
    }

    // MARK: Building the frame

    private func rebuild() {
        let signedIn = !menu.isEmpty
        loadedSignedIn = signedIn
        // /my sends a signed-out person to sign in; signing in sends the menu.
        tabBarController.load([HotwireTab(id: signedIn ? "main" : "start", title: "CocoScout", image: nil, url: AppConfig.url("/my"))])
        if #available(iOS 18.0, *) {
            tabBarController.isTabBarHidden = true
        } else {
            tabBarController.tabBar.isHidden = true
        }

        if menuButton.superview == nil {
            menuButton.install(in: tabBarController.view)
        }
        menuButton.isHidden = !signedIn
        tabBarController.view.bringSubviewToFront(menuButton)
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

    private static func cached<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func cache<T: Encodable>(_ value: T?, _ key: String) {
        if let value, let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
