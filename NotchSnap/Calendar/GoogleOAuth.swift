import AppKit
import CryptoKit
import Foundation
import Network

// MARK: - GoogleOAuth — sign-in for a Google account (PKCE + loopback)
//
// Google's documented flow for an INSTALLED app: open the consent screen in
// the user's real browser, have it redirect to a loopback address this process
// is listening on, and bind the exchange with PKCE so an intercepted
// authorization code is useless on its own.
//
// Loopback rather than a custom URL scheme because the OAuth client type is
// "Desktop app" — that is the type whose client ID a user can create without
// registering a bundle ID, which keeps the setup to a few minutes.
//
// The client secret is required by Google's token endpoint for desktop
// clients, but it is NOT confidential: it ships inside every copy of every
// desktop app ever built against it. PKCE is the thing actually protecting the
// exchange. Treating it as a secret anyway (Keychain, never logged) costs
// nothing.

@MainActor
final class GoogleOAuth {
    static let shared = GoogleOAuth()
    private init() {}

    /// Read-only calendar, plus openid/email purely so the token response
    /// carries an id_token we can read the account address out of — otherwise
    /// Settings could only say "connected" without saying to what.
    private static let scope = [
        "https://www.googleapis.com/auth/calendar.events.readonly",
        "openid", "email",
    ].joined(separator: " ")
    private static let authEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    private static let tokenEndpoint = "https://oauth2.googleapis.com/token"

    enum AuthError: LocalizedError {
        case notConfigured
        case listenerFailed(String)
        case denied(String)
        case tokenExchange(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .notConfigured: return L10n.t("gcal.err.notConfigured")
            case .listenerFailed(let d): return String(format: L10n.t("gcal.err.listener"), d)
            case .denied(let d): return String(format: L10n.t("gcal.err.denied"), d)
            case .tokenExchange(let d): return String(format: L10n.t("gcal.err.token"), d)
            case .cancelled: return L10n.t("gcal.err.cancelled")
            }
        }
    }

    // MARK: Configuration

    /// The credential the app ships with, registered once by whoever builds
    /// NotchSnap. Populated from Config/GoogleOAuth.xcconfig through
    /// Info.plist, so it never reaches the public repository.
    ///
    /// This is the whole point: a person using the app should press one button.
    /// Asking them to create a Google Cloud project — as the first version of
    /// this screen did — is developer setup wearing a user's clothes
    /// (Marcello, 2026-07-26).
    private static func bundled(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        // An unfilled xcconfig leaves the variable literally unexpanded.
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
    }

    static var hasBundledCredentials: Bool {
        bundled("GoogleOAuthClientID") != nil && bundled("GoogleOAuthClientSecret") != nil
    }

    /// A manually-entered override always wins, so a user who hits the shipped
    /// client's quota — or just prefers their own project — has a way out.
    var clientID: String? {
        get { KeychainStore.get(KeychainStore.Key.clientID) ?? Self.bundled("GoogleOAuthClientID") }
        set { KeychainStore.set(newValue, for: KeychainStore.Key.clientID) }
    }
    var clientSecret: String? {
        get { KeychainStore.get(KeychainStore.Key.clientSecret) ?? Self.bundled("GoogleOAuthClientSecret") }
        set { KeychainStore.set(newValue, for: KeychainStore.Key.clientSecret) }
    }
    var isConfigured: Bool {
        !(clientID ?? "").isEmpty && !(clientSecret ?? "").isEmpty
    }
    /// True when the user typed their own, rather than using the shipped one.
    var usesCustomCredentials: Bool {
        KeychainStore.get(KeychainStore.Key.clientID) != nil
    }
    var isSignedIn: Bool {
        KeychainStore.get(KeychainStore.Key.refreshToken) != nil
    }
    var account: String? { KeychainStore.get(KeychainStore.Key.account) }

    /// Cached until it expires; never persisted, since a refresh is cheap.
    private var accessToken: String?
    private var accessTokenExpiry: Date = .distantPast

    // MARK: Sign in / out

    func signIn() async throws {
        guard let clientID, let clientSecret, isConfigured else { throw AuthError.notConfigured }

        let verifier = Self.randomURLSafeString(64)
        let challenge = Self.codeChallenge(for: verifier)

        let listener = try LoopbackListener()
        defer { listener.stop() }
        let redirectURI = "http://127.0.0.1:\(listener.port)"

        var components = URLComponents(string: Self.authEndpoint)!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: Self.scope),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            // Without these Google only returns a refresh token the FIRST time
            // an account ever consents — reconnecting later would silently
            // yield an access token that dies in an hour.
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]
        NSWorkspace.shared.open(components.url!)

        let code = try await listener.awaitCode()
        try await exchange(code: code, verifier: verifier, redirectURI: redirectURI)
    }

    func signOut() {
        KeychainStore.remove(KeychainStore.Key.refreshToken)
        KeychainStore.remove(KeychainStore.Key.account)
        accessToken = nil
        accessTokenExpiry = .distantPast
    }

    /// A usable access token, refreshing if the cached one is stale.
    func validAccessToken() async throws -> String {
        if let accessToken, accessTokenExpiry > Date().addingTimeInterval(60) {
            return accessToken
        }
        guard let refresh = KeychainStore.get(KeychainStore.Key.refreshToken) else {
            throw AuthError.notConfigured
        }
        guard let clientID, let clientSecret else { throw AuthError.notConfigured }

        let body = Self.form([
            "client_id": clientID, "client_secret": clientSecret,
            "refresh_token": refresh, "grant_type": "refresh_token",
        ])
        let json = try await Self.post(Self.tokenEndpoint, body: body)
        guard let token = json["access_token"] as? String else {
            throw AuthError.tokenExchange(Self.errorText(json))
        }
        accessToken = token
        accessTokenExpiry = Date().addingTimeInterval((json["expires_in"] as? Double) ?? 3600)
        return token
    }

    // MARK: Token exchange

    private func exchange(code: String, verifier: String, redirectURI: String) async throws {
        guard let clientID, let clientSecret else { throw AuthError.notConfigured }
        let body = Self.form([
            "client_id": clientID, "client_secret": clientSecret,
            "code": code, "code_verifier": verifier,
            "grant_type": "authorization_code", "redirect_uri": redirectURI,
        ])
        let json = try await Self.post(Self.tokenEndpoint, body: body)
        guard let access = json["access_token"] as? String else {
            throw AuthError.tokenExchange(Self.errorText(json))
        }
        accessToken = access
        accessTokenExpiry = Date().addingTimeInterval((json["expires_in"] as? Double) ?? 3600)
        if let refresh = json["refresh_token"] as? String {
            KeychainStore.set(refresh, for: KeychainStore.Key.refreshToken)
        }
        // The email is only for showing "Connected as …" in Settings; the
        // id_token payload already carries it, so no extra request.
        if let idToken = json["id_token"] as? String,
           let email = Self.email(fromIDToken: idToken) {
            KeychainStore.set(email, for: KeychainStore.Key.account)
        }
    }

    // MARK: HTTP + PKCE helpers

    private static func post(_ url: String, body: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private static func errorText(_ json: [String: Any]) -> String {
        let code = json["error"] as? String ?? "unknown"
        let detail = json["error_description"] as? String
        return detail.map { "\(code): \($0)" } ?? code
    }

    private static func form(_ pairs: [String: String]) -> String {
        pairs.map { key, value in
            let encoded = value.addingPercentEncoding(
                withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))
            ) ?? value
            return "\(key)=\(encoded)"
        }.joined(separator: "&")
    }

    /// RFC 7636 PKCE: base64url(SHA256(verifier)), no padding.
    static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncoded
    }

    static func randomURLSafeString(_ length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return Data(bytes).base64URLEncoded
    }

    /// The `email` claim out of a JWT payload. No signature check: this token
    /// came straight from Google's token endpoint over TLS and is used only to
    /// label the Settings row.
    static func email(fromIDToken token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json["email"] as? String
    }
}

extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
