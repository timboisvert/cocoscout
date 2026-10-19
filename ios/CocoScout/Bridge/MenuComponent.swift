import HotwireNative
import UIKit

/// The menu (with badges) and who's signed in, sent by every page
/// (bridge/menu_controller.js). An empty menu means signed out.
final class MenuComponent: BridgeComponent {
    nonisolated override class var name: String { "menu" }

    override func onReceive(message: Message) {
        guard message.event == "update", let data: MenuData = message.data() else { return }
        // Rebuilding the screen can tear down the page that sent this, so let
        // the message finish first.
        let page = message.metadata?.url
        DispatchQueue.main.async {
            AppShell.shared.update(menu: data.menu, person: data.person, page: page)
            AppShell.shared.update(tapToPay: data.tapToPay)
        }
    }
}

private struct MenuData: Decodable {
    let menu: [MenuItem]
    let person: MenuPerson?
    /// Tap to Pay on iPhone for someone who can sell with it, else absent.
    let tapToPay: TapToPayInfo?
}
