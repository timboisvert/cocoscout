import AuthenticationServices
import UIKit

/// On opening the sign-in screen, iOS offers a CocoScout password saved in
/// iCloud Keychain (the webcredentials link to cocoscout.com is already in the
/// entitlements), so many people already signed in on the website sign in
/// here with one tap and Face ID. Nothing shows when there's none saved.
@MainActor
final class SavedPasswords: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    static let shared = SavedPasswords()

    private var controller: ASAuthorizationController?
    private var picked: ((String, String) -> Void)?
    private var offered = false

    /// Once per launch: someone who closed it isn't asked again every time
    /// the screen comes back.
    func offer(_ picked: @escaping (_ email: String, _ password: String) -> Void) {
        guard !offered, controller == nil else { return }
        offered = true
        self.picked = picked
        let controller = ASAuthorizationController(authorizationRequests: [ASAuthorizationPasswordProvider().createRequest()])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        controller.performRequests(options: .preferImmediatelyAvailableCredentials)
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASPasswordCredential else { return }
        let user = credential.user
        let password = credential.password
        MainActor.assumeIsolated {
            self.controller = nil
            self.picked?(user, password)
            self.picked = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated {
            self.controller = nil
            self.picked = nil
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }
}
