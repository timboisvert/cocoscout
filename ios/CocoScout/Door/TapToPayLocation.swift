import CoreLocation

/// Card networks need to know where a payment is taken, so Tap to Pay on
/// iPhone needs location access while the app is in use. It's asked for
/// when someone sets Tap to Pay on iPhone up on its page, and before a sale
/// if it somehow still hasn't been, so Apple's payment screen never stops
/// for it halfway through a sale.
@MainActor
final class TapToPayLocation: NSObject, CLLocationManagerDelegate {
    static let shared = TapToPayLocation()

    private let manager = CLLocationManager()
    private var waiting: [CheckedContinuation<Void, Never>] = []

    private override init() {
        super.init()
        manager.delegate = self
    }

    /// Asked already, whatever the answer.
    var hasBeenAsked: Bool { manager.authorizationStatus != .notDetermined }

    /// Asks once, and returns when the person has answered.
    func ask() async {
        guard !hasBeenAsked else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiting.append(continuation)
            if waiting.count == 1 { manager.requestWhenInUseAuthorization() }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.answered() }
    }

    private func answered() {
        guard hasBeenAsked else { return }
        let done = waiting
        waiting = []
        done.forEach { $0.resume() }
    }
}
