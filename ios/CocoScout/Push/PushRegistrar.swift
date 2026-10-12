import UIKit
import UserNotifications

/// This phone's push notifications: whether they're allowed, the token Apple
/// gives the app to reach this phone, and opening the page a tapped
/// notification points to. The web side files the token under the signed-in
/// person (PushComponent → bridge/push_controller.js → /my/push-token).
///
/// Never asks on its own: iPhone's "Allow notifications?" appears only when
/// someone taps Turn on (the Home card, or Settings → Notifications).
@MainActor
final class PushRegistrar: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushRegistrar()

    /// What the web side needs: where notifications stand, the token (when
    /// allowed; when turned off, the last one, so the server can forget it),
    /// and which Apple server the token belongs to.
    struct State: Encodable {
        let status: String
        let token: String?
        let environment: String
    }

    /// Development builds get tokens from Apple's sandbox.
    static var environment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    private static let tokenKey = "PushRegistrar.token"
    private var savedToken: String? {
        get { UserDefaults.standard.string(forKey: Self.tokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.tokenKey) }
    }
    private var waiting: [CheckedContinuation<String?, Never>] = []

    func start() {
        UNUserNotificationCenter.current().delegate = self
    }

    func state() async -> State {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            // Registering every time keeps the token fresh; Apple can change it.
            let token = await register()
            return State(status: Self.name(settings.authorizationStatus), token: token, environment: Self.environment)
        default:
            return State(status: Self.name(settings.authorizationStatus), token: savedToken, environment: Self.environment)
        }
    }

    /// iPhone's own question, then where that leaves things.
    func request() async -> State {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        return await state()
    }

    // MARK: Apple's answer (from AppDelegate)

    func didRegister(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        savedToken = token
        finishRegistering(with: token)
    }

    func didFailToRegister(_ error: Error) {
        finishRegistering(with: savedToken)
    }

    private func register() async -> String? {
        await withCheckedContinuation { continuation in
            waiting.append(continuation)
            UIApplication.shared.registerForRemoteNotifications()
            // Apple usually answers at once; never leave the page waiting.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                self?.finishRegistering(with: self?.savedToken)
            }
        }
    }

    private func finishRegistering(with token: String?) {
        let continuations = waiting
        waiting.removeAll()
        continuations.forEach { $0.resume(returning: token) }
    }

    private static func name(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized: "authorized"
        case .provisional: "provisional"
        case .ephemeral: "ephemeral"
        case .denied: "denied"
        default: "notDetermined"
        }
    }

    // MARK: Notifications arriving

    /// Shown even while the app is open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    /// A tap opens the page it's about (a message thread).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard let path = response.notification.request.content.userInfo["path"] as? String, path.hasPrefix("/") else { return }
        await MainActor.run { AppShell.shared.open(path: path) }
    }
}
