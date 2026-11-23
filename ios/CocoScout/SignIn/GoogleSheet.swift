import AuthenticationServices
import CryptoKit
import UIKit

/// Continue with Google on the iPhone: Google won't sign anyone in inside an
/// app's own web view, so it runs in the system's sign-in sheet, as the
/// Stripe sheet does, with no Google SDK. The sheet opens /auth/app/google
/// with a challenge made from a secret only the app holds; the server sends
/// the sheet back to cocoscout://auth?code=… and the app trades the code and
/// the secret at /app/sign_in/exchange (SignIn::ProvidersController#app_start).
@MainActor
final class GoogleSheet: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleSheet()

    enum Result {
        case code(String, secret: String)
        case canceled
        case failed
    }

    private var session: ASWebAuthenticationSession?

    func signIn(_ done: @escaping (Result) -> Void) {
        guard session == nil else { return }

        let secret = Self.randomSecret()
        let challenge = Data(SHA256.hash(data: Data(secret.utf8))).base64URLEncoded
        var components = URLComponents(url: AppConfig.url("/auth/app/google"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "challenge", value: challenge)]

        let session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: StripeSheet.callbackScheme) { [weak self] callback, error in
            Task { @MainActor in
                self?.session = nil
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    return done(.canceled)
                }
                let items = callback.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems ?? []
                if let code = items.first(where: { $0.name == "code" })?.value {
                    done(.code(code, secret: secret))
                } else if items.first(where: { $0.name == "error" })?.value == "canceled" {
                    done(.canceled)
                } else {
                    done(.failed)
                }
            }
        }
        session.presentationContextProvider = self
        // Not ephemeral: the Google accounts already signed in on this
        // phone's Safari are offered, which is most of what makes it quick.
        session.prefersEphemeralWebBrowserSession = false
        self.session = session
        if !session.start() {
            self.session = nil
            done(.failed)
        }
    }

    private static func randomSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }
}

extension Data {
    /// Base64 for addresses: - and _ in place of + and /, and no padding.
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
