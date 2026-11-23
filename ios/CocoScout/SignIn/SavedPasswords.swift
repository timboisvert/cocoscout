import AuthenticationServices
import UIKit

/// iOS's own sheet offering a CocoScout password saved in iCloud Keychain
/// (the webcredentials link to cocoscout.com is in the entitlements), filled
/// in with Face ID. Asked for when the email step opens on a phone that has
/// one (once per launch, so closing it isn't met again), and on Welcome
/// back's Continue. Nothing shows when there's none saved.
@MainActor
final class SavedPasswords: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    static let shared = SavedPasswords()

    struct Picked {
        let email: String
        let password: String
    }

    private var controller: ASAuthorizationController?
    private var done: ((Picked?) -> Void)?
    private var offeredAutomatically = false

    /// automatic: the email step opening (once per launch); otherwise the
    /// person asked for it. `done` gets nil when there's none or they close it.
    func request(automatic: Bool, done: @escaping (Picked?) -> Void) {
        if automatic {
            guard !offeredAutomatically else { return done(nil) }
            offeredAutomatically = true
        }
        guard controller == nil else { return done(nil) }
        self.done = done
        let controller = ASAuthorizationController(authorizationRequests: [ASAuthorizationPasswordProvider().createRequest()])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        controller.performRequests(options: .preferImmediatelyAvailableCredentials)
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        let credential = authorization.credential as? ASPasswordCredential
        let picked = credential.map { Picked(email: $0.user, password: $0.password) }
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
