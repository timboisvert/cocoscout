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

        // A cocoscout.com link that launched the app (universal link).
        if let activity = connectionOptions.userActivities.first(where: { $0.activityType == NSUserActivityTypeBrowsingWeb }) {
            openUniversalLink(activity)
        }
    }

    /// A cocoscout.com link tapped while the app was already running.
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb else { return }
        openUniversalLink(userActivity)
    }

    /// The links the site says open here (AppleAppSiteAssociationsController):
    /// the page, on top of whatever's showing, at the app's own server.
    private func openUniversalLink(_ activity: NSUserActivity) {
        guard let url = activity.webpageURL,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        components.scheme = nil
        components.host = nil
        components.port = nil
        let path = components.string ?? "/my"
        AppShell.shared.open(path: path.hasPrefix("/") ? path : "/my")
    }

    private func configureHotwire() {
        Hotwire.loadPathConfiguration(from: [.server(AppConfig.pathConfigurationURL)])
        var components: [BridgeComponent.Type] = [FormComponent.self, MenuComponent.self, DoorScannerComponent.self, PushComponent.self]
        // Tap to Pay only in builds run from Xcode (Debug) until Apple grants
        // its distribution entitlement; TestFlight and App Store builds leave
        // it out, so the door page doesn't offer it (NativeAppHelper).
        #if DEBUG
        components.append(TapToPayComponent.self)
        #endif
        Hotwire.registerBridgeComponents(components)
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
