import AppKit
import AuthenticationServices
import Foundation
import Security

// MARK: - KeychainStore — sign-in credentials at rest, for every provider
//
// The Google refresh token is a long-lived key to the user's calendar, so it
// does not go in UserDefaults. The client ID and secret live here too: for an
// installed app Google's "secret" is not truly confidential (it ships inside
// every copy of a desktop client), but it is still an account identifier and
// there is no reason to leave it in a plist. Apple's identifier and the
// name/email it hands over exactly once (see AppleSignIn below) live under the
// same store.
//
// The app is not sandboxed, so this is the plain login keychain with no access
// group. One `service` covers every provider — SecItem already scopes by the
// `account` key, so nothing is gained by splitting it further.

enum KeychainStore {
    private static let service = "com.notchsnap.app.google"

    static func set(_ value: String?, for key: String) {
        guard let value, !value.isEmpty else { remove(key); return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            // Needed after first unlock so a refresh can run without the user
            // having just typed their login password.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            SecItemAdd(query.merging(attributes) { a, _ in a } as CFDictionary, nil)
        }
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ key: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ] as CFDictionary)
    }

    // Keys used by the Google integration.
    enum Key {
        static let clientID = "clientID"
        static let clientSecret = "clientSecret"
        static let refreshToken = "refreshToken"
        static let account = "account"
    }
}

// MARK: - AppleSignIn — the Face-ID-on-a-Mac flow (Touch ID / Apple Watch)
//
// The other half of "make it yours": Google identifies an account by reading a
// calendar; this identifies one with nothing else attached. No calendar scope,
// no data pulled — ASAuthorizationAppleIDProvider hands back a stable user
// identifier plus, on the FIRST grant only, a name and email address. Every
// sign-in after that returns nil for both, which is why they are cached here
// the moment they arrive rather than re-read from Apple each time.
//
// On a Mac already signed into iCloud with Touch ID (or an Apple Watch that
// can unlock it), the system sheet authenticates locally on that alone —
// the same one-tap flow as Face ID on iOS, not a separate mechanism.
//
// REQUIRES a one-time change only Marcello can make: "Sign In with Apple"
// enabled on the com.notchsnap.app identifier at developer.apple.com. The
// entitlement here and the code below are both real and complete; without
// that portal switch, `signIn()` reaches Apple's servers and comes back with
// a permission error, caught and surfaced through `SignInError.failed` rather
// than a raw OSStatus (Marcello, 2026-08-09).
@MainActor
final class AppleSignIn: NSObject {
    static let shared = AppleSignIn()
    private override init() { super.init() }

    private enum Key {
        static let userID = "appleUserID"
        static let email = "appleEmail"
        static let name = "appleName"
    }

    var isSignedIn: Bool { KeychainStore.get(Key.userID) != nil }
    /// Whichever Apple gave that first time — a name if consented, else the
    /// email (which may itself be an Apple "Hide My Email" relay address;
    /// that is still a valid, usable identity).
    var account: String? { KeychainStore.get(Key.name) ?? KeychainStore.get(Key.email) }

    enum SignInError: LocalizedError {
        case cancelled
        case failed(String)
        var errorDescription: String? {
            switch self {
            case .cancelled: return "Sign-in was cancelled."
            case .failed(let message): return message
            }
        }
    }

    private var continuation: CheckedContinuation<Void, Error>?
    /// Kept alive only for the duration of one request — ASAuthorizationController
    /// does not retain its delegate.
    private var activeController: ASAuthorizationController?

    func signIn() async throws {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        activeController = controller

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.continuation = cont
            controller.performRequests()
        }
    }

    func signOut() {
        KeychainStore.remove(Key.userID)
        KeychainStore.remove(Key.email)
        KeychainStore.remove(Key.name)
    }

    /// Apple can revoke a grant from the user's own Apple ID settings without
    /// telling this app. Call once at launch so Settings never keeps claiming
    /// a connection that is already gone (Apple's documented pattern — check,
    /// never assume a stored identifier is still valid).
    func refreshCredentialState() {
        guard let userID = KeychainStore.get(Key.userID) else { return }
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, _ in
            guard state == .revoked || state == .notFound else { return }
            Task { @MainActor in self.signOut() }
        }
    }
}

extension AppleSignIn: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController,
                                              didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            defer { activeController = nil }
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                continuation?.resume(throwing: SignInError.failed("Apple returned an unexpected credential."))
                continuation = nil
                return
            }
            KeychainStore.set(credential.user, for: Key.userID)
            if let email = credential.email, !email.isEmpty {
                KeychainStore.set(email, for: Key.email)
            }
            if let components = credential.fullName {
                let formatted = PersonNameComponentsFormatter().string(from: components)
                if !formatted.isEmpty { KeychainStore.set(formatted, for: Key.name) }
            }
            continuation?.resume()
            continuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                              didCompleteWithError error: Error) {
        Task { @MainActor in
            defer { activeController = nil }
            let nsError = error as NSError
            if nsError.domain == ASAuthorizationError.errorDomain,
               nsError.code == ASAuthorizationError.canceled.rawValue {
                continuation?.resume(throwing: SignInError.cancelled)
            } else {
                // Exactly the failure mode expected until the App ID capability
                // is turned on — surfaced as readable text, not a bare code.
                continuation?.resume(throwing: SignInError.failed(
                    "Apple couldn't complete sign-in (\(nsError.localizedDescription))."))
            }
            continuation = nil
        }
    }
}

extension AppleSignIn: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
        }
    }
}
