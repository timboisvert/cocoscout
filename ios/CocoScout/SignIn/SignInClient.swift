import Foundation
import HotwireNative
import WebKit

/// One answer from the server's sign-in steps (App::SignInController).
struct SignInReply: Decodable {
    /// "step", "signed_in", or "error".
    let status: String
    let step: String?
    let email: String?
    let notice: String?
    let codeLifetime: String?
    let provider: String?
    let firstName: String?
    let lastName: String?
    let superadmin: Bool?
    let landing: String?
    let error: String?
    let message: String?
    let nonce: String?
    /// With "signed_in": how they signed in ("password", "code", "passkey", "apple", "google").
    var method: String? = nil
}

/// Talks to the server's sign-in steps as the web view: with its cookies and
/// its user agent, writing the cookies that come back into its store, so the
/// session a step starts is the web view's own (the sign-in plan's handoff).
/// No link ever signs anyone in.
enum SignInClient {
    static func post(_ step: String, _ body: [String: Any] = [:]) async -> SignInReply {
        var request = URLRequest(url: AppConfig.url("/app/sign_in/\(step)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return await send(request)
    }

    static func get(_ step: String) async -> SignInReply {
        await send(URLRequest(url: AppConfig.url("/app/sign_in/\(step)")))
    }

    /// Any of the app's JSON steps as a dictionary: the passkey options, and
    /// making a passkey (App::PasskeysController). GET without a body. nil
    /// when the server can't be reached or doesn't answer with JSON.
    static func json(_ path: String, body: [String: Any]? = nil) async -> [String: Any]? {
        var request = URLRequest(url: AppConfig.url(path))
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        guard let data = await raw(request) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// As the web view: its cookies and user agent out, and whatever the
    /// server set (the session, the sign-in step) back into its store before
    /// anything else loads.
    private static func raw(_ original: URLRequest) async -> Data? {
        var request = original
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let store = WKWebsiteDataStore.default().httpCookieStore
        let configuration = URLSessionConfiguration.ephemeral
        for cookie in await store.allCookies() {
            configuration.httpCookieStorage?.setCookie(cookie)
        }
        configuration.httpAdditionalHeaders = ["User-Agent": Hotwire.config.userAgent]

        guard let (data, _) = try? await URLSession(configuration: configuration).data(for: request) else { return nil }
        for cookie in configuration.httpCookieStorage?.cookies ?? [] {
            await store.setCookie(cookie)
        }
        return data
    }

    private static func send(_ request: URLRequest) async -> SignInReply {
        do {
            guard let data = await raw(request) else { throw URLError(.cannotConnectToHost) }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(SignInReply.self, from: data)
        } catch {
            return SignInReply(status: "error", step: nil, email: nil, notice: nil, codeLifetime: nil, provider: nil,
                               firstName: nil, lastName: nil, superadmin: nil, landing: nil, error: "network",
                               message: "CocoScout couldn't be reached. Check your connection and try again.", nonce: nil)
        }
    }
}
