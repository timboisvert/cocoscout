import HotwireNative
import UIKit

/// Push notifications on this phone, for the web side (bridge/push_controller.js):
///
/// - "sync": where they stand and the token, on every page, so the server
///   keeps this phone filed under whoever's signed in.
/// - "request": iPhone's "Allow notifications?", then the same answer.
/// - "open-settings": CocoScout's notification settings in iPhone Settings,
///   the only place they can be turned off.
final class PushComponent: BridgeComponent {
    nonisolated override class var name: String { "push" }

    override func onReceive(message: Message) {
        switch message.event {
        case "sync":
            Task {
                let state = await PushRegistrar.shared.state()
                _ = try? await reply(to: "sync", with: state)
            }
        case "request":
            Task {
                let state = await PushRegistrar.shared.request()
                _ = try? await reply(to: "request", with: state)
            }
        case "open-settings":
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                UIApplication.shared.open(url)
            }
        default:
            break
        }
    }
}
