import AuthenticationServices
import UIKit

/// iOS's own sheet offering what this iPhone holds for cocoscout.com: the
/// passkeys (sign-in plan phase 4) and the passwords saved in iCloud Keychain
/// (the webcredentials link to cocoscout.com is in the entitlements), with
/// Face ID. Asked for when the email step opens on a phone that has one
/// (once per launch, so closing it isn't met again), and on Welcome back's
/// Continue. Nothing shows when there's none.
@MainActor
final class SavedSignIns: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    static let shared = SavedSignIns()

    enum Picked {
        case password(email: String, password: String)
        /// The passkey's answer, as the JSON App::SignInController#passkey reads.
        case passkey([String: Any])
    }

    private var controller: ASAuthorizationController?
    private var done: ((Picked?) -> Void)?
    private var offeredAutomatically = false

    /// automatic: the email step opening (once per launch); otherwise the
    /// person asked for it. passkeyOptions: /app/sign_in/passkey_options, or
    /// nil to offer passwords only. `done` gets nil when there's nothing or
    /// they close it.
    func request(automatic: Bool, passkeyOptions: [String: Any]?, done: @escaping (Picked?) -> Void) {
        if automatic {
            guard !offeredAutomatically else { return done(nil) }
            offeredAutomatically = true
        }
        guard controller == nil else { return done(nil) }
        self.done = done
        var requests: [ASAuthorizationRequest] = [ASAuthorizationPasswordProvider().createRequest()]
        if let assertion = passkeyOptions.flatMap(WebAuthnJSON.assertionRequest) { requests.insert(assertion, at: 0) }
        let controller = ASAuthorizationController(authorizationRequests: requests)
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        controller.performRequests(options: .preferImmediatelyAvailableCredentials)
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        var picked: Picked?
        if let password = authorization.credential as? ASPasswordCredential {
            picked = .password(email: password.user, password: password.password)
        } else if let assertion = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
            picked = .passkey(WebAuthnJSON.assertion(assertion))
        }
        MainActor.assumeIsolated { self.finish(picked) }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated { self.finish(nil) }
    }

    private func finish(_ picked: Picked?) {
        controller = nil
        let done = self.done
        self.done = nil
        done?(picked)
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated { keyWindow() }
    }
}

/// iOS's sheet that makes a passkey for the signed-in account and keeps it
/// in iCloud Keychain, with Face ID: after a code or password sign-in
/// (PasskeyOffer) and from the Account page (PasskeyComponent). The options
/// and the answer go through App::PasskeysController.
@MainActor
final class PasskeyMaker: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    static let shared = PasskeyMaker()

    enum Outcome {
        /// Kept: what the Account page calls it.
        case added(String)
        case canceled
        /// This iPhone's iCloud Keychain already has one for this account.
        case exists
        case failed(String)
    }

    private var controller: ASAuthorizationController?
    private var made: ((ASAuthorizationPlatformPublicKeyCredentialRegistration?, Error?) -> Void)?

    /// The whole of it: the options, the sheet, and the new passkey back to
    /// the server.
    func make(done: @escaping (Outcome) -> Void) {
        guard controller == nil else { return }
        Task {
            let options = await SignInClient.json("/app/passkeys/options")
            guard let options, options["challenge"] != nil, let request = WebAuthnJSON.registrationRequest(options) else {
                return done(.failed((options?["message"] as? String) ?? "Passkeys can't be added right now. Please try again."))
            }
            present(request) { registration, error in
                if let registration {
                    Task {
                        let answer = await SignInClient.json("/app/passkeys", body: ["credential": WebAuthnJSON.registration(registration)])
                        if answer?["status"] as? String == "added" {
                            done(.added(answer?["name"] as? String ?? "iCloud Keychain"))
                        } else {
                            done(.failed((answer?["message"] as? String) ?? "That passkey couldn't be added. Please try again."))
                        }
                    }
                } else if let error = error as? ASAuthorizationError, error.code == .canceled {
                    done(.canceled)
                } else if Self.matchedExcluded(error) {
                    done(.exists)
                } else {
                    done(.failed("That passkey couldn't be added. Please try again."))
                }
            }
        }
    }

    private static func matchedExcluded(_ error: Error?) -> Bool {
        guard let error = error as? ASAuthorizationError else { return false }
        if #available(iOS 18.0, *) { return error.code == .matchedExcludedCredential }
        return false
    }

    private func present(_ request: ASAuthorizationRequest, made: @escaping (ASAuthorizationPlatformPublicKeyCredentialRegistration?, Error?) -> Void) {
        self.made = made
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        controller.performRequests()
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        let registration = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration
        MainActor.assumeIsolated { self.finish(registration, registration == nil ? ASAuthorizationError(.failed) : nil) }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated { self.finish(nil, error) }
    }

    private func finish(_ registration: ASAuthorizationPlatformPublicKeyCredentialRegistration?, _ error: Error?) {
        controller = nil
        let made = self.made
        self.made = nil
        made?(registration, error)
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated { keyWindow() }
    }
}

/// WebAuthn's JSON (base64url strings, as SignIn::Passkeys sends and reads)
/// to and from AuthenticationServices' requests and answers.
enum WebAuthnJSON {
    static func data(_ value: Any?) -> Data? {
        guard var text = value as? String else { return nil }
        text = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while text.count % 4 != 0 { text += "=" }
        return Data(base64Encoded: text)
    }

    static func string(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func assertionRequest(_ options: [String: Any]) -> ASAuthorizationPlatformPublicKeyCredentialAssertionRequest? {
        guard let rpID = options["rpId"] as? String, let challenge = data(options["challenge"]) else { return nil }
        let request = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpID).createCredentialAssertionRequest(challenge: challenge)
        request.userVerificationPreference = .required
        return request
    }

    static func registrationRequest(_ options: [String: Any]) -> ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest? {
        guard let rp = options["rp"] as? [String: Any], let rpID = rp["id"] as? String,
              let user = options["user"] as? [String: Any], let userID = data(user["id"]), let name = user["name"] as? String,
              let challenge = data(options["challenge"]) else { return nil }
        let request = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpID)
            .createCredentialRegistrationRequest(challenge: challenge, name: name, userID: userID)
        request.userVerificationPreference = .required
        if #available(iOS 17.4, *) {
            let excluded = (options["excludeCredentials"] as? [[String: Any]] ?? []).compactMap { data($0["id"]) }
            request.excludedCredentials = excluded.map { ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0) }
        }
        return request
    }

    static func assertion(_ assertion: ASAuthorizationPlatformPublicKeyCredentialAssertion) -> [String: Any] {
        let id = string(assertion.credentialID)
        var response: [String: Any] = [
            "clientDataJSON": string(assertion.rawClientDataJSON),
            "authenticatorData": string(assertion.rawAuthenticatorData),
            "signature": string(assertion.signature)
        ]
        if let user = assertion.userID { response["userHandle"] = string(user) }
        return ["id": id, "rawId": id, "type": "public-key", "authenticatorAttachment": "platform",
                "clientExtensionResults": [String: Any](), "response": response]
    }

    static func registration(_ registration: ASAuthorizationPlatformPublicKeyCredentialRegistration) -> [String: Any] {
        let id = string(registration.credentialID)
        return ["id": id, "rawId": id, "type": "public-key", "authenticatorAttachment": "platform",
                "clientExtensionResults": [String: Any](),
                "response": ["clientDataJSON": string(registration.rawClientDataJSON),
                             "attestationObject": string(registration.rawAttestationObject ?? Data()),
                             "transports": ["internal", "hybrid"]]]
    }
}

/// Apple's own Sign in with Apple sheet, opened from code: Welcome back's
/// Continue for someone who last signed in with Apple. (The sign-in sheet's
/// Continue with Apple is the system's button itself.)
@MainActor
final class AppleSignIn: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    static let shared = AppleSignIn()

    struct Credential {
        let token: String
        let code: String?
        let firstName: String?
        let lastName: String?
    }

    private var controller: ASAuthorizationController?
    private var done: ((Result<Credential, Error>) -> Void)?

    func request(nonceDigest: String, done: @escaping (Result<Credential, Error>) -> Void) {
        guard controller == nil else { return }
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = nonceDigest
        self.done = done
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        controller.performRequests()
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        let apple = authorization.credential as? ASAuthorizationAppleIDCredential
        let credential = apple.flatMap { apple -> Credential? in
            guard let token = apple.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) else { return nil }
            return Credential(token: token, code: apple.authorizationCode.flatMap { String(data: $0, encoding: .utf8) },
                              firstName: apple.fullName?.givenName, lastName: apple.fullName?.familyName)
        }
        MainActor.assumeIsolated {
            self.finish(credential.map { .success($0) } ?? .failure(ASAuthorizationError(.failed)))
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated { self.finish(.failure(error)) }
    }

    private func finish(_ result: Result<Credential, Error>) {
        controller = nil
        let done = self.done
        self.done = nil
        done?(result)
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated { keyWindow() }
    }
}

@MainActor
func keyWindow() -> UIWindow {
    UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.keyWindow }
        .first ?? UIWindow()
}
