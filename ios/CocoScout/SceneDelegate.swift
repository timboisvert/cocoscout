import HotwireNative
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        configureHotwire()
        configureAppearance()

        let shell = AppShell.shared
        shell.start()
        shell.tabBarController.view.backgroundColor = .white

        window = UIWindow(windowScene: windowScene)
        // Launch screen and web views are white; keep the window white too so
        // there's no flash between them.
        window?.backgroundColor = .white
        window?.tintColor = AppConfig.pink
        window?.rootViewController = shell.tabBarController
        window?.makeKeyAndVisible()
    }

    private func configureHotwire() {
        Hotwire.loadPathConfiguration(from: [.server(AppConfig.pathConfigurationURL)])
        Hotwire.registerBridgeComponents([FormComponent.self, MenuComponent.self, DoorScannerComponent.self])
        Hotwire.registerRouteDecisionHandlers([
            OpenInSafariRouteDecisionHandler(),
            OpenAsDocumentRouteDecisionHandler(),
            AppNavigationRouteDecisionHandler(),
            SafariViewControllerRouteDecisionHandler(),
            SystemNavigationRouteDecisionHandler()
        ])
        // Stripe first, then Hotwire's own defaults in their usual order.
        Hotwire.registerWebViewPolicyDecisionHandlers([
            StripeSheetPolicyDecisionHandler(),
            ReloadWebViewPolicyDecisionHandler(),
            NewWindowWebViewPolicyDecisionHandler(),
            ExternalNavigationWebViewPolicyDecisionHandler(),
            LinkActivatedWebViewPolicyDecisionHandler()
        ])
        Hotwire.config.backButtonDisplayMode = .minimal
        Hotwire.config.showDoneButtonOnModals = true
        Hotwire.config.defaultViewController = { url in WebViewController(url: url) }
        #if DEBUG
        Hotwire.config.debugLoggingEnabled = true
        #endif
    }

    private func configureAppearance() {
        // Opaque bars so iOS places web content below them.
        let navBar = UINavigationBarAppearance()
        navBar.configureWithOpaqueBackground()
        // Any title iOS draws itself in Coustard too; web pages put theirs on
        // the left (WebViewController).
        navBar.titleTextAttributes = [.font: AppConfig.coustard(18), .foregroundColor: UIColor.label]
        UINavigationBar.appearance().standardAppearance = navBar
        UINavigationBar.appearance().scrollEdgeAppearance = navBar
    }
}
