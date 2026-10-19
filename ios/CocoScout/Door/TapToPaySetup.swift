import Foundation
import UIKit

/// What the server says about Tap to Pay on iPhone for whoever's signed in
/// (NativeAppHelper#native_tap_to_pay, with the menu): sent only to someone
/// who can sell at a door that has it switched on, in a copy of the app
/// that has it.
struct TapToPayInfo: Codable, Equatable {
    /// Tap to Pay on iPhone's own page (door/tap_to_pay).
    let settingsPath: String
    /// Who's signed in, so "shown once" and "set up here" are per person.
    let userKey: String
    /// Only CocoScout's administrators may accept Apple's terms (Apple 3.8).
    let canAcceptTerms: Bool
    /// The organization's Terminal Location, when it has one yet.
    let locationId: String?
    let connectionTokenUrl: String
}

/// Tap to Pay on iPhone on this iPhone, as Apple's publishing review asks
/// for it (guide v1.8): warmed up at launch and on coming back (1.5, 5.6),
/// set up on purpose from its own page (3.5, 3.6), asking for location access
/// there rather than in a sale, showing how far along it
/// is while it gets ready (3.9.1, 5.7), and telling someone who may not
/// accept Apple's terms to wait for an administrator (3.8.1).
@MainActor
final class TapToPaySetup {
    static let shared = TapToPaySetup()

    enum State: Equatable {
        case notSetUp
        case preparing(Float)
        case ready
        case needsAdmin
        case failed(String)

    }

    private(set) var info: TapToPayInfo?

    private(set) var state: State = .notSetUp {
        didSet {
            guard state != oldValue else { return }
            pageListener?(state)
            preparingListener?(state)
        }
    }

    /// Tap to Pay on iPhone's page, hearing how things stand (one page at a time).
    var pageListener: ((State) -> Void)?
    /// The getting-ready screen over a sale (TapToPayPreparing).
    var preparingListener: ((State) -> Void)?

    private var reader: TapToPayReader { TapToPayReader.shared }

    // MARK: Who's signed in

    func update(info newInfo: TapToPayInfo?) {
        let changedPerson = newInfo?.userKey != info?.userKey
        info = newInfo
        if changedPerson { state = .notSetUp }
        warmUp()
    }

    /// Set up once on this iPhone by this person (a connection went through):
    /// from then on the app warms Terminal up on its own.
    private var setUpKey: String? { info.map { "TapToPay.setUp.\($0.userKey)" } }

    var hasBeenSetUp: Bool {
        guard let setUpKey else { return false }
        return UserDefaults.standard.bool(forKey: setUpKey)
    }

    // MARK: Getting ready

    /// At launch and whenever the app comes back (Apple 1.5, 5.6): connect in
    /// the background so the payment screen opens at once. Never shows
    /// Apple's terms; that only happens when someone sets it up.
    func warmUp() {
        guard let info, hasBeenSetUp, TapToPayLocation.shared.hasBeenAsked,
              let locationId = info.locationId, !locationId.isEmpty else { return }
        Task {
            _ = await connect(locationId: locationId, tokenURL: info.connectionTokenUrl, termsPermitted: false)
        }
    }

    /// "Set up Tap to Pay on iPhone" on its page (Apple 3.5): Apple's terms
    /// when they're still to be accepted and this person may accept them,
    /// then the configuration with its progress.
    func enable(locationId: String, tokenURL: String, termsPermitted: Bool) async -> State {
        await TapToPayLocation.shared.ask()
        return await connect(locationId: locationId, tokenURL: tokenURL, termsPermitted: termsPermitted)
    }

    /// Ready for a sale at this Location, connecting first when it isn't.
    func ensureReady(locationId: String, tokenURL: String, termsPermitted: Bool) async -> State {
        await TapToPayLocation.shared.ask()
        if reader.isConnected(to: locationId) {
            state = .ready
            return state
        }
        return await connect(locationId: locationId, tokenURL: tokenURL, termsPermitted: termsPermitted)
    }

    /// How this iPhone stands right now, for the page's first look.
    func currentState() -> State {
        if case .preparing = state { return state }
        if let locationId = info?.locationId, reader.isConnected(to: locationId) { return .ready }
        if case .needsAdmin = state { return state }
        return hasBeenSetUp ? .preparing(0) : .notSetUp
    }

    /// The SDK's configuration progress (TapToPayReaderDelegate), 0 to 1.
    func progress(_ value: Float) {
        state = .preparing(value)
    }

    private var connecting: Task<State, Never>?

    private func connect(locationId: String, tokenURL: String, termsPermitted: Bool) async -> State {
        if let connecting { return await connecting.value }
        if case .ready = state, reader.isConnected(to: locationId) { return .ready }

        state = .preparing(0)
        let task = Task { () -> State in
            do {
                try await reader.connect(locationId: locationId, tokenURL: tokenURL, termsPermitted: termsPermitted)
                if let setUpKey { UserDefaults.standard.set(true, forKey: setUpKey) }
                return .ready
            } catch {
                return TapToPayReader.state(for: error)
            }
        }
        connecting = task
        let result = await task.value
        connecting = nil
        state = result
        return result
    }
}
