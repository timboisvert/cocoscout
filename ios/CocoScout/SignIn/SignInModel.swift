import Combine
import CryptoKit
import Foundation

/// Which screen of the sign-in steps is showing, and what's typed into it.
/// The server decides every next step (App::SignInController); this only
/// shows the one it names.
@MainActor
final class SignInModel: ObservableObject {
    enum Screen: Equatable {
        /// The email address, with Apple and Google below it.
        case start
        case password
        case code
        /// A new person's name, once a code has confirmed their address.
        case create
        /// Apple or Google matched an account with a chosen password: enter it once.
        case connect
        /// Apple's Hide My Email: the address organizations know them by.
        case addEmail
    }

    @Published var screen: Screen = .start
    @Published var email = ""
    @Published var password = ""
    @Published var code = ""
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var busy = false
    /// A step went wrong: shown in pink.
    @Published var error: String?
    /// Something to know (a code sent moments ago): shown in gray.
    @Published var notice: String?
    @Published var provider: String?
    @Published var codeLifetime = "10 minutes"
    @Published var superadmin = false
    /// The nonce Apple's sheet signs into its token, asked for when the
    /// screen opens so the button works on the first tap.
    @Published private(set) var appleNonce: String?

    /// Signed in: the page to load in the web view.
    let onSignedIn: (URL) -> Void

    init(onSignedIn: @escaping (URL) -> Void) {
        self.onSignedIn = onSignedIn
    }

    // MARK: Steps

    func continueWithEmail() {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return }
        run("identify", ["email": address])
    }

    /// A password iCloud Keychain offered on opening: both at once.
    func signIn(email address: String, password saved: String) {
        email = address
        run("identify", ["email": address, "password": saved])
    }

    func submitPassword() {
        guard !password.isEmpty else { return }
        run(screen == .connect ? "connect" : "password", ["password": password])
    }

    func sendCode() { run("send_code") }

    func submitCode() {
        let digits = code.filter(\.isNumber)
        guard digits.count == 6 else { return }
        run("code", ["code": digits])
    }

    func createAccount() {
        run("create", ["first_name": firstName, "last_name": lastName])
    }

    func addEmail() {
        run("add_email", ["email": email.trimmingCharacters(in: .whitespacesAndNewlines)])
    }

    func startOver() {
        password = ""
        code = ""
        run("start_over")
    }

    // MARK: Apple and Google

    func prepareApple() {
        guard appleNonce == nil else { return }
        Task {
            let reply = await SignInClient.get("nonce")
            appleNonce = reply.nonce
        }
    }

    /// Apple's sheet signs the nonce's SHA-256 (the server checks the same).
    var appleNonceDigest: String? {
        appleNonce.map { SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined() }
    }

    func finishApple(token: String, authorizationCode: String?, firstName: String?, lastName: String?) {
        // Used once: the next try asks for a fresh one.
        appleNonce = nil
        var body = ["provider": "apple", "id_token": token]
        body["authorization_code"] = authorizationCode
        body["first_name"] = firstName
        body["last_name"] = lastName
        run("provider", body)
    }

    func appleFailed() {
        appleNonce = nil
        prepareApple()
    }

    func continueWithGoogle() {
        guard !busy else { return }
        busy = true
        error = nil
        GoogleSheet.shared.signIn { [weak self] result in
            guard let self else { return }
            switch result {
            case .code(let code, let secret):
                self.busy = false
                self.run("exchange", ["code": code, "secret": secret])
            case .canceled:
                self.busy = false
            case .failed:
                self.busy = false
                self.error = "Google couldn't confirm that sign-in. Try again, or continue with your email address."
            }
        }
    }

    // MARK: Talking to the server

    private func run(_ step: String, _ body: [String: String] = [:]) {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            let reply = await SignInClient.post(step, body)
            busy = false
            show(reply)
        }
    }

    private func show(_ reply: SignInReply) {
        switch reply.status {
        case "signed_in":
            if let landing = reply.landing.flatMap(URL.init(string:)) {
                onSignedIn(landing)
            }
        case "step":
            notice = reply.notice
            if let address = reply.email { email = address }
            provider = reply.provider
            superadmin = reply.superadmin ?? false
            if let lifetime = reply.codeLifetime { codeLifetime = lifetime }
            if let first = reply.firstName, firstName.isEmpty { firstName = first }
            if let last = reply.lastName, lastName.isEmpty { lastName = last }
            let next: Screen = switch reply.step {
            case "password": .password
            case "code": .code
            case "create": .create
            case "connect": .connect
            case "add_email": .addEmail
            default: .start
            }
            if next != screen {
                password = ""
                code = ""
            }
            if next == .addEmail { email = "" }
            screen = next
        default:
            error = reply.message ?? "That didn't work. Please try again."
            if reply.error == "wrong" || reply.error == "expired" || reply.error == "locked" { code = "" }
        }
    }
}
