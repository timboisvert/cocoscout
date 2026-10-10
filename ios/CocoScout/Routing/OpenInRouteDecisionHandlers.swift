import HotwireNative
import UIKit

// Links the path configuration marks with "open_in" (public/hotwire-native/
// path-configuration.json), so which links leave the web view is decided on
// the server.

/// "open_in": "safari" — pages the app doesn't carry, like /manage, open in
/// Safari, where the person is usually already signed in.
final class OpenInSafariRouteDecisionHandler: RouteDecisionHandler {
    let name = "open-in-safari"

    func matches(proposal: VisitProposal, configuration: Navigator.Configuration) -> Bool {
        proposal.properties["open_in"] as? String == "safari"
    }

    func handle(proposal: VisitProposal, configuration: Navigator.Configuration, navigator: Navigating) -> Router.Decision {
        let url = proposal.url
        Task { @MainActor in
            UIApplication.shared.open(url)
        }
        return .cancel
    }
}

/// "open_in": "document" — PDFs (W-9 copy, 1099s, invoices) and calendar
/// files open in a viewer with Share, instead of a web page that can't show them.
final class OpenAsDocumentRouteDecisionHandler: RouteDecisionHandler {
    let name = "open-as-document"

    func matches(proposal: VisitProposal, configuration: Navigator.Configuration) -> Bool {
        proposal.properties["open_in"] as? String == "document"
    }

    func handle(proposal: VisitProposal, configuration: Navigator.Configuration, navigator: Navigating) -> Router.Decision {
        let url = proposal.url
        let presenter = navigator.activeNavigationController
        Task { @MainActor in
            DocumentPresenter.shared.present(url, from: presenter)
        }
        return .cancel
    }
}
