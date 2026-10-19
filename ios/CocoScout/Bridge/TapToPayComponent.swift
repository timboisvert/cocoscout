import HotwireNative
import UIKit
import UserNotifications

/// Tap to Pay on iPhone (bridge/tap_to_pay_controller.js), on the Stripe
/// Terminal SDK, the way Apple's publishing review asks for it (guide v1.8):
///
/// - "pay": the door page holds seats for a sale. Get the reader ready
///   (showing "Getting Tap to Pay on iPhone ready" if that takes a moment,
///   Apple 5.7), then Apple's How to Tap guide the first time (after the
///   terms, never before, Apple 4.2), then the buyer's tap, and reply
///   { status: "paid" | "failed" | "canceled", message, paymentIntentId,
///   declined }. A payment that isn't approved while the app is in the
///   background posts a notification (Apple 5.12).
/// - "status" / "enable": Tap to Pay on iPhone's own page asks how this
///   iPhone stands, and sets it up (Apple 3.5, 3.6). The answers keep
///   coming while it gets ready, with its progress (Apple 3.9.1).
/// - "howToTap": Apple's guide again, from either page (Apple 4.3).
final class TapToPayComponent: BridgeComponent {
    nonisolated override class var name: String { "tap-to-pay" }

    private var reader: TapToPayReader { TapToPayReader.shared }
    private var setup: TapToPaySetup { TapToPaySetup.shared }

    override func onReceive(message: Message) {
        let page = delegate?.destination as? UIViewController
        switch message.event {
        case "howToTap":
            guard let page else { return }
            Task { @MainActor in await HowToTap.present(from: page) }
        case "status":
            Task { @MainActor in
                setup.pageListener = { [weak self] state in self?.answer("status", state) }
                answer("status", setup.currentState())
            }
        case "enable":
            guard let data: ReaderData = message.data() else { return }
            Task { @MainActor in
                setup.pageListener = { [weak self] state in self?.answer("status", state) }
                let state = await setup.enable(locationId: data.locationId, tokenURL: data.connectionTokenUrl,
                                               termsPermitted: data.canAcceptTerms ?? false)
                answer("enable", state)
                if state == .ready, !HowToTap.hasBeenShown, let page { await HowToTap.present(from: page) }
            }
        case "pay":
            guard let data: TapToPayPayment = message.data() else { return }
            Task { @MainActor in await pay(data, from: page) }
        default:
            break
        }
    }

    @MainActor
    private func pay(_ sale: TapToPayPayment, from page: UIViewController?) async {
        let state = await TapToPayPreparing.around(page) {
            await setup.ensureReady(locationId: sale.locationId, tokenURL: sale.connectionTokenUrl,
                                    termsPermitted: sale.canAcceptTerms ?? false)
        }
        switch state {
        case .ready:
            break
        case .needsAdmin:
            return reply("pay", Answer(status: "failed", message: TapToPayReader.needsAdminMessage, paymentIntentId: nil, declined: false))
        case .failed(let message):
            return reply("pay", Answer(status: "failed", message: message, paymentIntentId: nil, declined: false))
        default:
            return reply("pay", Answer(status: "failed", message: "Tap to Pay on iPhone isn't ready yet. Try again in a moment.", paymentIntentId: nil, declined: false))
        }

        // Apple's guide comes after the terms are accepted, before the first tap.
        if !HowToTap.hasBeenShown, let page { await HowToTap.present(from: page) }

        let outcome = await reader.take(sale)
        if outcome.status == "failed", UIApplication.shared.applicationState != .active {
            await Self.notifyNotApproved(sale)
        }
        reply("pay", Answer(status: outcome.status, message: outcome.message, paymentIntentId: outcome.paymentIntentId,
                            declined: outcome.declined))
    }

    @MainActor
    private func answer(_ event: String, _ state: TapToPaySetup.State) {
        Task { _ = try? await reply(to: event, with: StateAnswer(state)) }
    }

    @MainActor
    private func reply(_ event: String, _ answer: Answer) {
        Task { _ = try? await reply(to: event, with: answer) }
    }

    /// Apple 5.12: the app was closed before the result, and it wasn't approved.
    private static func notifyNotApproved(_ sale: TapToPayPayment) async {
        let content = UNMutableNotificationContent()
        content.title = "Payment not approved"
        content.body = String(format: "The $%.2f Tap to Pay on iPhone payment for %@ wasn't approved. Open CocoScout to try again.",
                              Double(sale.amountCents) / 100, sale.label)
        content.sound = .default
        if let door = sale.doorPath { content.userInfo = ["path": door] }
        let request = UNNotificationRequest(identifier: "tap-to-pay-\(sale.stripeMetadata["ticket_order_id"] ?? UUID().uuidString)",
                                            content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

/// What Tap to Pay on iPhone's page sends with "status" and "enable".
private struct ReaderData: Decodable {
    let connectionTokenUrl: String
    let locationId: String
    let canAcceptTerms: Bool?
}

private struct Answer: Encodable {
    let status: String
    let message: String?
    let paymentIntentId: String?
    let declined: Bool
}

private struct StateAnswer: Encodable {
    let state: String
    let progress: Float?
    let message: String?

    init(_ state: TapToPaySetup.State) {
        switch state {
        case .notSetUp: (self.state, progress, message) = ("notSetUp", nil, nil)
        case .preparing(let value): (self.state, progress, message) = ("preparing", value, nil)
        case .ready: (self.state, progress, message) = ("ready", nil, nil)
        case .needsAdmin: (self.state, progress, message) = ("needsAdmin", nil, nil)
        case .failed(let text): (self.state, progress, message) = ("failed", nil, text)
        }
    }
}
