import HotwireNative
import UIKit
import UserNotifications

/// One menu tile as the server describes it (NativeAppHelper#native_menu):
/// icon is an SF Symbol name; badge is a count; subtitle is a second line
/// (the Door's bar says which show and when).
struct MenuItem: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let path: String
    let icon: String
    var badge: Int?
    var subtitle: String?
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
        if let path = pendingPath {
            pendingPath = nil
            open(path: path)
        }
    }

    /// A tapped notification's page, on top of whatever's showing. One that
    /// launched the app waits for the screen to be built.
    private var pendingPath: String?

    func open(path: String) {
        guard loadedSignedIn != nil else {
            pendingPath = path
            return
        }
        tabBarController.dismiss(animated: false)
        tabBarController.activeNavigator.route(AppConfig.url(path))
    }

    /// page: the address of the page that sent the menu.
    func update(menu newMenu: [MenuItem], person newPerson: MenuPerson?, page: String? = nil) {
        menu = newMenu
        person = newPerson
        // Without badges or the Door (it comes and goes with tonight's shows).
        Self.cache(newMenu.filter { $0.id != "door" }.map { MenuItem(id: $0.id, title: $0.title, path: $0.path, icon: $0.icon) },
                   Self.menuKey)
        Self.cache(newPerson, Self.personKey)
        // The app icon shows unread messages, as the notifications set it.
        let unread = newMenu.first { $0.id == "messages" }?.badge ?? 0
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(unread) }
        // Signing in or out starts the screen afresh; otherwise only the badge changes.
        if !newMenu.isEmpty != loadedSignedIn {
            rebuild()
            // Just signed in from an email link (an invitation, a sign-up):
            // the server sent them on to that link's page, so stay there
            // rather than starting over on My Calendar.
            if !newMenu.isEmpty, let path = Self.pageAfterSignIn(page) {
                open(path: path)
            }
        } else {
            menuButton.badge = Self.badgeText(newMenu.reduce(0) { $0 + ($1.badge ?? 0) })
        }
    }

    // MARK: Tap to Pay on iPhone

    /// Who can sell with Tap to Pay on iPhone, with every menu: warm it up
    /// (Apple 1.5), and show Apple's awareness screen once (Apple 3.1, 3.2).
    func update(tapToPay info: TapToPayInfo?) {
        TapToPaySetup.shared.update(info: info)
        guard let info else { return }
        // Let the page settle first, and never over a sheet already showing.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard self.tabBarController.presentedViewController == nil else { return }
            TapToPaySplash.showIfNeeded(info, over: self.tabBarController) { [weak self] path in self?.open(path: path) }
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

    /// The page sign-in landed on, when it's somewhere other than My
    /// Calendar or the sign-in pages themselves.
    static func pageAfterSignIn(_ page: String?) -> String? {
        guard let page, let url = URL(string: page), url.host == AppConfig.baseURL.host else { return nil }
        let path = url.path
        let home = ["", "/", "/my", "/my/"]
        let signingIn = ["/welcome", "/signin", "/signup", "/signout", "/password", "/reset"]
        guard !home.contains(path), !signingIn.contains(where: { path.hasPrefix($0) }) else { return nil }
        return url.query.map { "\(path)?\($0)" } ?? path
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
