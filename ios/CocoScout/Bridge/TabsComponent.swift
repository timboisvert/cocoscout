import HotwireNative
import UIKit

/// The tabs, menu and badges for the signed-in person, sent by every page
/// (bridge/tabs_controller.js). An empty tab list means signed out.
final class TabsComponent: BridgeComponent {
    nonisolated override class var name: String { "tabs" }

    override func onReceive(message: Message) {
        guard message.event == "update", let data: TabsData = message.data() else { return }
        // Rebuilding the tab bar can tear down the page that sent this, so
        // let the message finish first.
        DispatchQueue.main.async {
            AppShell.shared.update(tabs: data.tabs, menu: data.menu ?? [])
        }
    }
}

private struct TabsData: Decodable {
    let tabs: [TabSpec]
    let menu: [TabSpec]?
}
