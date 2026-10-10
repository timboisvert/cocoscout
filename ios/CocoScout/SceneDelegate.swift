import HotwireNative
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    private let tabBarController = HotwireTabBarController(lazyLoadTabs: true)

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        configureHotwire()
        configureAppearance()

        tabBarController.load(Tabs.standard)
        tabBarController.view.backgroundColor = .white

        window = UIWindow(windowScene: windowScene)
        // Launch screen and web views are white; keep the window white too so
        // there's no flash between them.
        window?.backgroundColor = .white
        window?.tintColor = AppConfig.pink
        window?.rootViewController = tabBarController
        window?.makeKeyAndVisible()
    }

    private func configureHotwire() {
        Hotwire.loadPathConfiguration(from: [.server(AppConfig.pathConfigurationURL)])
        Hotwire.registerBridgeComponents([FormComponent.self])
        Hotwire.config.backButtonDisplayMode = .minimal
        Hotwire.config.showDoneButtonOnModals = true
        #if DEBUG
        Hotwire.config.debugLoggingEnabled = true
        #endif
    }

    private func configureAppearance() {
        // Opaque bars so iOS places web content below them.
        let navBar = UINavigationBarAppearance()
        navBar.configureWithOpaqueBackground()
        UINavigationBar.appearance().standardAppearance = navBar
        UINavigationBar.appearance().scrollEdgeAppearance = navBar
        UITabBar.appearance().tintColor = AppConfig.pink
    }
}

/// The tabs everyone gets until the server says otherwise.
enum Tabs {
    static let standard: [HotwireTab] = [
        HotwireTab(id: "home", title: "Home", image: UIImage(systemName: "house"), url: AppConfig.url("/my")),
        HotwireTab(id: "tasks", title: "Tasks", image: UIImage(systemName: "checklist"), url: AppConfig.url("/my/tasks")),
        HotwireTab(id: "messages", title: "Messages", image: UIImage(systemName: "envelope"), url: AppConfig.url("/my/messages")),
        HotwireTab(id: "more", title: "More", image: UIImage(systemName: "person.crop.circle"), url: AppConfig.url("/my/account"))
    ]
}
