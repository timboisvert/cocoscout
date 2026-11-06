import HotwireNative
import UIKit
import WebKit

/// Where the floating Coco button belongs on this page, as the page itself
/// works it out (bridge/menu_button_controller.js): how far above the bottom
/// it must sit to clear a bar pinned there, and whether it should be away
/// altogether (scrolling down, or a sheet over the page). The button gets
/// out of the way, so no page makes room for it (Tim, 2026-11-06). The app
/// only obeys; the rules live on the server.
final class MenuButtonComponent: BridgeComponent {
    nonisolated override class var name: String { "menu-button" }

    override func onReceive(message: Message) {
        guard message.event == "place", let data: Placement = message.data() else { return }
        // A page in a sheet over the screen hides the button by itself, and
        // must not move it for the page underneath.
        guard let controller = delegate?.destination as? UIViewController,
              controller.navigationController?.presentingViewController == nil else { return }
        let webView = (controller as? VisitableViewController)?.visitableView.webView
        AppShell.shared.placeMenuButton(rise: CGFloat(data.rise), away: data.away, webView: webView)
    }
}

private struct Placement: Decodable {
    let rise: Double
    let away: Bool
}
