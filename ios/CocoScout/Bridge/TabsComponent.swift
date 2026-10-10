import HotwireNative
import UIKit

/// The tabs and badges for the signed-in person, sent by every page
/// (bridge/tabs_controller.js). An empty list means signed out.
final class TabsComponent: BridgeComponent {
    nonisolated override class var name: String { "tabs" }

    override func onReceive(message: Message) {
        guard message.event == "update", let data: TabsData = message.data() else { return }
        // Rebuilding the tab bar can tear down the page that sent this, so
        // let the message finish first.
        DispatchQueue.main.async {
            AppShell.shared.update(data.tabs)
        }
    }
}

private struct TabsData: Decodable {
    let tabs: [TabSpec]
}
