import Foundation
import StripeTerminal

/// The phone as a card reader: Stripe Terminal's Tap to Pay on iPhone.
///
/// One of these lives for the app (shared). The first tap connects the phone to
/// Terminal as a reader at the organization's Location (the server picks
/// the Location when it makes the connection token); later taps reuse the
/// connection. The PaymentIntent is made here, by the SDK, from what the
/// server sends (TapToPay.payment_params): Stripe won't let the server name
/// in-person cards on CocoScout's account. Every step reports a plain status
/// + message back to the door page, which shows it and offers another go.
@MainActor
final class TapToPayReader: NSObject {
    struct Outcome {
        let status: String   // paid, failed, canceled
        let message: String?
        var paymentIntentId: String? = nil
        /// The card itself was declined (not a connection or setup problem),
        /// so the buyer gets a receipt saying so (Apple 5.10).
        var declined = false
    }

    private var connectionTokenURL: URL?
    /// The Location this phone last connected at. Kept here rather than read
    /// back from the SDK's reader, which doesn't always report it (Stripe's
    /// simulated reader doesn't), so a connected phone is never connected again.
    private var connectedLocationId: String?
    /// The sale's PaymentIntent while it's being paid, so a declined card
    /// tries again on the same one (Stripe: never make a second for a sale).
    private var pending: (orderId: String, intent: PaymentIntent)?

    /// Stripe Terminal takes its token provider once per launch, so the
    /// app has one reader, shared by every door page.
    static let shared = TapToPayReader()

    private override init() {
        super.init()
        Terminal.setTokenProvider(self)
    }

    /// Takes the sale's payment on a reader that's already connected
    /// (TapToPaySetup.ensureReady comes first).
    func take(_ sale: TapToPayPayment) async -> Outcome {
        connectionTokenURL = URL(string: sale.connectionTokenUrl)
        let orderId = sale.stripeMetadata["ticket_order_id"] ?? ""
        do {
            try await connect(locationId: sale.locationId, tokenURL: sale.connectionTokenUrl, termsPermitted: sale.canAcceptTerms ?? false)
            let intent = try await paymentIntent(for: sale, orderId: orderId)
            let collected = try await collectPaymentMethod(intent)
            let confirmed = try await confirmPaymentIntent(collected)
            guard confirmed.status == .succeeded || confirmed.status == .requiresCapture else {
                pending = (orderId, confirmed)
                return Outcome(status: "failed", message: "The payment wasn't approved.", declined: true)
            }
            pending = nil
            return Outcome(status: "paid", message: nil, paymentIntentId: confirmed.stripeId)
        } catch let error as ConfirmPaymentIntentError {
            // Declined: the same PaymentIntent takes the next card.
            if let intent = error.paymentIntent { pending = (orderId, intent) }
            return Outcome(status: "failed", message: "The payment wasn't approved. \(error.localizedDescription)", declined: true)
        } catch let error as NSError where error.domain == ErrorDomain && error.code == ErrorCode.canceled.rawValue {
            return Outcome(status: "canceled", message: nil)
        } catch {
            if case .failed(let message) = Self.state(for: error) { return Outcome(status: "failed", message: message) }
            if case .needsAdmin = Self.state(for: error) { return Outcome(status: "failed", message: Self.needsAdminMessage) }
            return Outcome(status: "failed", message: error.localizedDescription)
        }
    }

    // MARK: Connecting

    /// Connected as a reader at this Location (a door at another
    /// organization connects afresh).
    func isConnected(to locationId: String) -> Bool {
        Terminal.shared.connectionStatus == .connected && connectedLocationId == locationId
    }

    /// The phone as a Tap to Pay reader at the organization's Location.
    /// termsPermitted: Apple's terms may be shown if they're still to be
    /// accepted (only CocoScout's administrators, Apple 3.8); otherwise a
    /// connection that needs them fails with TOSNotYetAccepted.
    func connect(locationId: String, tokenURL: String, termsPermitted: Bool) async throws {
        connectionTokenURL = URL(string: tokenURL)
        if isConnected(to: locationId) { return }
        if Terminal.shared.connectionStatus == .connected {
            try await Terminal.shared.disconnectReader()
        }
        connectedLocationId = nil

        #if targetEnvironment(simulator)
        let simulated = true // no NFC in the Simulator: Stripe's simulated reader
        #else
        let simulated = false
        #endif
        if case .failure = Terminal.shared.supportsReaders(of: .tapToPay, discoveryMethod: .tapToPay, simulated: simulated) {
            throw TapToPayError.unsupported
        }

        let discovery = try TapToPayDiscoveryConfigurationBuilder().setSimulated(simulated).build()
        let reader = try await discoverTapToPayReader(discovery)
        let connection = try TapToPayConnectionConfigurationBuilder(delegate: self, locationId: locationId)
            .setTosAcceptancePermitted(termsPermitted)
            .build()
        _ = try await Terminal.shared.connectReader(reader, connectionConfig: connection)
        connectedLocationId = locationId
    }

    static let needsAdminMessage = "Tap to Pay on iPhone needs an administrator to accept Apple's terms first. Ask your organization's manager to contact CocoScout."

    /// What a connection error means for the person holding the phone, in
    /// words that never name the payment provider.
    static func state(for error: Error) -> TapToPaySetup.State {
        if let error = error as? TapToPayError { return .failed(error.localizedDescription) }
        let error = error as NSError
        guard error.domain == ErrorDomain else { return .failed(error.localizedDescription) }
        switch error.code {
        case 3930: // TOS not yet accepted, and this person may not accept them
            return .needsAdmin
        case 2910: // iOS too old for Tap to Pay (Apple 1.4)
            return .failed("To take payments with Tap to Pay on iPhone, update iOS: Settings > General > Software Update.")
        case 2920:
            return .failed("This iPhone needs a passcode to take payments. Set one in Settings > Face ID & Passcode.")
        case 2960:
            return .failed("Sign in with your Apple Account in Settings, then set up Tap to Pay on iPhone again.")
        case 2970:
            return .failed("Apple's terms weren't accepted, so Tap to Pay on iPhone isn't set up.")
        case 2930:
            return .failed("Tap to Pay on iPhone can't take payments during a phone call.")
        case 2200: // location access off; card networks need it
            return .failed("Tap to Pay on iPhone needs location access, as card networks require. Turn it on in Settings > Privacy & Security > Location Services > CocoScout.")
        default:
            return .failed(error.localizedDescription)
        }
    }

    /// This sale's PaymentIntent: the one already started for it, or a new
    /// one carrying the order's total and metadata.
    private func paymentIntent(for sale: TapToPayPayment, orderId: String) async throws -> PaymentIntent {
        if let pending, pending.orderId == orderId, pending.intent.status == .requiresPaymentMethod {
            return pending.intent
        }
        let params = try PaymentIntentParametersBuilder(amount: UInt(sale.amountCents), currency: sale.currency)
            .setCaptureMethod(.automatic)
            .setMetadata(sale.stripeMetadata)
            .setStripeDescription(sale.description)
            .setTransferGroup(sale.transferGroup)
            .build()
        let intent = try await Terminal.shared.createPaymentIntent(params)
        pending = (orderId, intent)
        return intent
    }

    // The SDK hands back a Cancelable for these, so they have no async
    // forms of their own.
    private func collectPaymentMethod(_ intent: PaymentIntent) async throws -> PaymentIntent {
        try await withCheckedThrowingContinuation { continuation in
            Terminal.shared.collectPaymentMethod(intent) { collected, error in
                if let collected { continuation.resume(returning: collected) }
                else { continuation.resume(throwing: error ?? TapToPayError.noToken) }
            }
        }
    }

    private func confirmPaymentIntent(_ intent: PaymentIntent) async throws -> PaymentIntent {
        try await withCheckedThrowingContinuation { continuation in
            Terminal.shared.confirmPaymentIntent(intent) { confirmed, error in
                if let confirmed { continuation.resume(returning: confirmed) }
                else { continuation.resume(throwing: error ?? TapToPayError.noToken) }
            }
        }
    }

    private func discoverTapToPayReader(_ configuration: DiscoveryConfiguration) async throws -> Reader {
        try await withCheckedThrowingContinuation { continuation in
            var done = false
            let delegate = DiscoveryDelegateBox { readers in
                guard !done, let reader = readers.first else { return }
                done = true
                continuation.resume(returning: reader)
            }
            self.discovery = delegate
            Terminal.shared.discoverReaders(configuration, delegate: delegate) { error in
                if let error, !done {
                    done = true
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private var discovery: DiscoveryDelegateBox?
}

/// What bridge/tap_to_pay_controller.js sends with "pay".
struct TapToPayPayment: Decodable {
    let amountCents: Int
    let currency: String
    let description: String
    /// The PaymentIntent's metadata (the bridge keeps "metadata" for itself).
    let stripeMetadata: [String: String]
    let transferGroup: String
    let connectionTokenUrl: String
    let locationId: String
    let label: String
    /// Only CocoScout's administrators may accept Apple's terms (Apple 3.8).
    let canAcceptTerms: Bool?
    /// The door the sale is at, for the notification that it wasn't approved.
    let doorPath: String?
}

enum TapToPayError: LocalizedError {
    case unsupported
    case noToken

    var errorDescription: String? {
        switch self {
        case .unsupported: return "This iPhone can't take Tap to Pay on iPhone. It needs an iPhone XS or newer; if it is one, update iOS: Settings > General > Software Update."
        case .noToken: return "Couldn't reach our payment provider. Check the connection and try again."
        }
    }
}

// MARK: - Stripe Terminal delegates

extension TapToPayReader: ConnectionTokenProvider {
    /// The server mints the token (door#tap_connection_token) with the
    /// signed-in cookies, so Terminal knows which organization is selling.
    nonisolated func fetchConnectionToken(_ completion: @escaping ConnectionTokenCompletionBlock) {
        Task { @MainActor in
            guard let url = connectionTokenURL else { return completion(nil, TapToPayError.noToken) }
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                let body = try JSONDecoder().decode(TokenBody.self, from: data)
                completion(body.secret, nil)
            } catch {
                completion(nil, TapToPayError.noToken)
            }
        }
    }

    private struct TokenBody: Decodable { let secret: String }
}

// Apple's Tap to Pay screen does the prompting. The configuration it does
// the first time on a phone arrives as a software update, whose progress the
// app shows (Apple 3.9.1).
extension TapToPayReader: TapToPayReaderDelegate {
    nonisolated func tapToPayReader(_ reader: Reader, didStartInstallingUpdate update: ReaderSoftwareUpdate, cancelable: Cancelable?) {
        Task { @MainActor in TapToPaySetup.shared.progress(0) }
    }

    nonisolated func tapToPayReader(_ reader: Reader, didReportReaderSoftwareUpdateProgress progress: Float) {
        Task { @MainActor in TapToPaySetup.shared.progress(progress) }
    }

    nonisolated func tapToPayReader(_ reader: Reader, didFinishInstallingUpdate update: ReaderSoftwareUpdate?, error: Error?) {}
    nonisolated func tapToPayReader(_ reader: Reader, didRequestReaderInput inputOptions: ReaderInputOptions = []) {}
    nonisolated func tapToPayReader(_ reader: Reader, didRequestReaderDisplayMessage displayMessage: ReaderDisplayMessage) {}
    nonisolated func tapToPayReaderDidAcceptTermsOfService(_ reader: Reader) {}
}

/// Hands discovered readers to a closure (the SDK wants a delegate object).
private final class DiscoveryDelegateBox: NSObject, DiscoveryDelegate {
    private let found: ([Reader]) -> Void

    init(found: @escaping ([Reader]) -> Void) {
        self.found = found
    }

    func terminal(_ terminal: Terminal, didUpdateDiscoveredReaders readers: [Reader]) {
        found(readers)
    }
}
