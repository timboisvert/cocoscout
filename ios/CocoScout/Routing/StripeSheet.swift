import AuthenticationServices
import HotwireNative
import UIKit
import WebKit

/// Stripe's own pages (bank setup) never load in the app's web view: that web
/// view only knows how to show CocoScout pages, and once Stripe sent someone
/// back the app was left on a blank screen. They open in a secure sheet
/// instead. When Stripe is done it returns to /app/return, which hands the
/// sheet a cocoscout://open?path=… link (AppReturnsController); the sheet
/// closes and the app opens that page, signed in as always. Stripe Checkout
/// (paying a contract invoice) opens the same way.
struct StripeSheetPolicyDecisionHandler: WebViewPolicyDecisionHandler {
    let name = "stripe-sheet"

    func matches(navigationAction: WKNavigationAction, configuration: Navigator.Configuration) -> Bool {
        guard navigationAction.targetFrame?.isMainFrame ?? true,
              let host = navigationAction.request.url?.host?.lowercased() else { return false }
        return host == "stripe.com" || host.hasSuffix(".stripe.com")
    }

    func handle(navigationAction: WKNavigationAction, configuration: Navigator.Configuration,
                navigator: Navigating) -> WebViewPolicyManager.Decision {
        guard let url = navigationAction.request.url else { return .cancel }
        Task { @MainActor [weak navigator] in
            StripeSheet.shared.open(url) { path in
                if let path {
                    // The page they came from (Payment Settings) gives way to
                    // where Stripe sent them back to.
                    navigator?.route(AppConfig.url(path), options: VisitOptions(action: .replace), parameters: nil)
                } else {
                    // Closed by hand (a contract payment ends on a public
                    // receipt page that never sends the sheet back): reload so
                    // the page underneath shows what changed, like PAID.
                    navigator?.reload()
                }
            }
        }
        return .cancel
    }
}

@MainActor
final class StripeSheet: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = StripeSheet()
    static let callbackScheme = "cocoscout"

    private var session: ASWebAuthenticationSession?

    /// Opens the Stripe page. `closed` gets the CocoScout path to open when
    /// Stripe sends them back, or nil when they close the sheet themselves.
    func open(_ url: URL, closed: @escaping (String?) -> Void) {
        guard session == nil else { return }

        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.callbackScheme) { [weak self] callback, _ in
            Task { @MainActor in
                self?.session = nil
                let path = callback.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
                    .queryItems?.first(where: { $0.name == "path" })?.value
                closed(path?.hasPrefix("/") == true ? path : nil)
            }
        }
        session.presentationContextProvider = self
        // A fresh browser each time: no "wants to use stripe.com to sign in"
        // prompt, and nothing of Stripe's left behind on the phone.
        session.prefersEphemeralWebBrowserSession = true
        self.session = session
        if !session.start() { self.session = nil }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }
}
