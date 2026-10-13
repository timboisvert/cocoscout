import Foundation
import StripeTerminal

/// The phone as a card reader: Stripe Terminal's Tap to Pay on iPhone.
///
/// One of these lives for the app. The first tap connects the phone to
/// Terminal as a reader at the organization's Location (the server picks
/// the Location when it makes the connection token); later taps reuse the
/// connection. Every step reports a plain status + message back to the door
/// page, which shows it and offers another go.
@MainActor
final class TapToPayReader: NSObject {
    struct Outcome {
        let status: String   // paid, failed, canceled
        let message: String?
    }

    private var connectionTokenURL: URL?

    override init() {
        super.init()
        Terminal.setTokenProvider(self)
    }

    func take(_ sale: TapToPayPayment) async -> Outcome {
        connectionTokenURL = URL(string: sale.connectionTokenUrl)
        do {
            try await connectIfNeeded()
            let intent = try await Terminal.shared.retrievePaymentIntent(clientSecret: sale.clientSecret)
            let collected = try await Terminal.shared.collectPaymentMethod(intent)
            let confirmed = try await Terminal.shared.confirmPaymentIntent(collected)
            guard confirmed.status == .succeeded || confirmed.status == .requiresCapture else {
                return Outcome(status: "failed", message: "The payment didn't go through.")
            }
            return Outcome(status: "paid", message: nil)
        } catch let error as NSError where error.code == ErrorCode.Code.canceled.rawValue {
            return Outcome(status: "canceled", message: nil)
        } catch {
            return Outcome(status: "failed", message: error.localizedDescription)
        }
    }

    /// The phone as a Tap to Pay reader, connected once per launch.
    private func connectIfNeeded() async throws {
        if Terminal.shared.connectionStatus == .connected { return }

        guard Terminal.shared.supportsReaders(of: .tapToPay, simulated: false) == nil else {
            throw TapToPayError.unsupported
        }

        let discovery = try TapToPayDiscoveryConfigurationBuilder().setSimulated(false).build()
        let reader = try await discoverTapToPayReader(discovery)
        // The Location comes with the connection token the server minted.
        let connection = try TapToPayConnectionConfigurationBuilder(delegate: self, locationId: reader.locationId ?? "")
            .setOnBehalfOf(nil)
            .build()
        _ = try await Terminal.shared.connectReader(reader, connectionConfig: connection)
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
    let clientSecret: String
    let connectionTokenUrl: String
    let amountCents: Int
    let label: String
}

enum TapToPayError: LocalizedError {
    case unsupported
    case noToken

    var errorDescription: String? {
        switch self {
        case .unsupported: return "This iPhone can't take Tap to Pay (it needs an iPhone XS or newer on a current iOS)."
        case .noToken: return "Couldn't connect to Stripe. Check the connection and try again."
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

extension TapToPayReader: TapToPayReaderDelegate {
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
