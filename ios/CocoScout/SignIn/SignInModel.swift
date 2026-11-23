import Combine
import CryptoKit
import Foundation
import SwiftUI

/// Who last signed in on this phone, kept on the phone only, so the next
/// sign-in screen can say "Welcome back, Sam" and Continue the same way. The
/// server sends it with a successful sign-in (App::SignInController).
struct KnownAccount: Codable, Equatable {
    let email: String
    let firstName: String?
    /// "password", "code", "passkey", "apple", or "google".
    let method: String

    private static let key = "SignIn.knownAccount"

    static func load() -> KnownAccount? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(KnownAccount.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    static func forget() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// The sign-in screens (sign-in plan phase 3, redesigned for the phone on
/// https://claude.ai/artifact/X1sA6FoXBSPJseGxFzdExn): a pink landing, and
/// the steps on a white sheet that rises over it. The server decides every
/// next step (App::SignInController); this only shows the one it names.
@MainActor
final class SignInModel: ObservableObject {
    enum Screen: Equatable {
        /// The landing, with no sheet up.
        case landing
        /// The email address, with Apple and Google below it.
        case email
        case password
        case code
        /// A new person's name, once a code has confirmed their address.
        case create
        /// Apple or Google matched an account with a chosen password: enter it once.
        case connect
        /// Apple's Hide My Email: the address organizations know them by.
        case addEmail

        /// The sheet sits low, with Coco peeking over it; the steps that
        /// need more room raise it near the top, and she steps off.
        var sheetIsLow: Bool { self == .email || self == .addEmail }
    }

    @Published var screen: Screen = .landing
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
    /// Who last signed in here: the landing welcomes them back.
    @Published var known: KnownAccount? = KnownAccount.load()
    /// A link that came in while signed out, waiting for sign-in, in words:
    /// "A message is waiting for you".
    @Published var waiting: String?
    /// The nonce Apple's sheet signs into its token, asked for ahead of time
    /// so the button works on the first tap.
    @Published private(set) var appleNonce: String?

    /// Who just signed in here and how, for AppShell's offer to make a
    /// passkey (PasskeyOffer) once the first page is up.
    private(set) var justSignedIn: KnownAccount?

    /// Signed in: the page to load in the web view.
    let onSignedIn: (URL) -> Void

    init(onSignedIn: @escaping (URL) -> Void) {
        self.onSignedIn = onSignedIn
    }

    // MARK: The landing

    /// Get started, or a link's "Sign in to see it": the email sheet, with
    /// iOS offering any passkey or saved password over it.
    func getStarted() {
        error = nil
        notice = nil
        withSheet(.email)
        offerSaved(automatic: true) { _ in }
    }

    /// Welcome back's Continue: the same way in as last time. A passkey or a
    /// saved password goes through iOS's own sheet and Face ID; Apple and
    /// Google open theirs; otherwise the address goes in as typed, and the
    /// server asks for the password or sends a code.
    func continueAsKnown() {
        guard let known, !busy else { return }
        email = known.email
        error = nil
        switch known.method {
        case "apple":
            startApple()
        case "google":
            continueWithGoogle()
        default:
            offerSaved(automatic: false, account: known.email) { [weak self] used in
                if !used { self?.run("identify", ["email": known.email]) }
            }
        }
    }

    /// iOS's sheet with this phone's passkeys and saved passwords for
    /// cocoscout.com. A saved password for another address than Welcome
    /// back's doesn't count. `done` says whether one was used.
    private func offerSaved(automatic: Bool, account: String? = nil, done: @escaping (Bool) -> Void) {
        Task {
            let options = await SignInClient.json("/app/sign_in/passkey_options")
            SavedSignIns.shared.request(automatic: automatic, passkeyOptions: options) { [weak self] picked in
                guard let self else { return }
                switch picked {
                case .passkey(let credential):
                    self.run("passkey", ["credential": credential])
                    done(true)
                case .password(let address, let saved) where account == nil || address.caseInsensitiveCompare(account ?? "") == .orderedSame:
                    self.signIn(email: address, password: saved)
                    done(true)
                default:
                    done(false)
                }
            }
        }
    }

    /// Use a different email: forget who was here, and start fresh.
    func useDifferentEmail() {
        KnownAccount.forget()
        known = nil
        email = ""
        getStarted()
    }

    /// Closing the sheet from the email step goes back to the landing.
    func closeSheet() {
        error = nil
        notice = nil
        password = ""
        code = ""
        withSheet(.landing)
        run("start_over", quietly: true)
    }

    // MARK: Steps

    func continueWithEmail() {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return }
        run("identify", ["email": address])
    }

    /// A password iCloud Keychain filled in: both at once.
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

    /// Back from a step: to the email step, fresh.
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

    /// Apple's sheet opened from code (Welcome back's Continue), not its button.
    func startApple() {
        guard let digest = appleNonceDigest else {
            prepareApple()
            error = "Apple isn't ready yet. Try again in a moment."
            return
        }
        AppleSignIn.shared.request(nonceDigest: digest) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let credential):
                self.finishApple(token: credential.token, authorizationCode: credential.code,
                                 firstName: credential.firstName, lastName: credential.lastName)
            case .failure:
                self.appleFailed()
            }
        }
    }

    func finishApple(token: String, authorizationCode: String?, firstName: String?, lastName: String?) {
        appleNonce = nil
        var body = ["provider": "apple", "id_token": token]
        body["authorization_code"] = authorizationCode
        body["first_name"] = firstName
        body["last_name"] = lastName
        run("provider", body)
        prepareApple()
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
            self.busy = false
            switch result {
            case .code(let code, let secret):
                self.run("exchange", ["code": code, "secret": secret])
            case .canceled:
                break
            case .failed:
                self.error = "Google couldn't confirm that sign-in. Try again, or continue with your email address."
            }
        }
    }

    // MARK: Talking to the server

    private func run(_ step: String, _ body: [String: Any] = [:], quietly: Bool = false) {
        guard !busy || quietly else { return }
        if !quietly {
            busy = true
            error = nil
        }
        Task {
            let reply = await SignInClient.post(step, body)
            if quietly { return }
            busy = false
            show(reply)
        }
    }

    private func show(_ reply: SignInReply) {
        switch reply.status {
        case "signed_in":
            if let address = reply.email, let method = reply.method {
                let account = KnownAccount(email: address, firstName: reply.firstName, method: method)
                account.save()
                known = account
                justSignedIn = account
            }
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
            default: .email
            }
            if next != screen {
                password = ""
                code = ""
            }
            if next == .addEmail { email = "" }
            withSheet(next)
        default:
            error = reply.message ?? "That didn't work. Please try again."
            if reply.error == "wrong" || reply.error == "expired" || reply.error == "locked" { code = "" }
        }
    }

    /// Screen changes animate: the sheet rises, steps slide.
    private func withSheet(_ next: Screen) {
        withAnimation(.spring(duration: 0.4)) { screen = next }
    }
}
