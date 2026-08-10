import AppKit
import Contacts
import SwiftUI

// MARK: - AttendeePhotoStore — real faces for attendee avatars (AV-5)
//
// EventKit hands over attendee names and emails but never photos, so faces
// have to be resolved from somewhere else. Two sources, tried in order:
//
//   1. The user's own Contacts database — local, instant, free, never leaves
//      this Mac.
//   2. The signed-in user's own Google People contacts, but ONLY when signed
//      in with Google — covers colleagues Contacts has never heard of.
//
// A Workspace DIRECTORY lookup (org-wide, not personal) lived here through
// 2026-08-09 and was removed: it needed the directory.readonly OAuth scope,
// which is Google "restricted" tier and gates OAuth verification behind a
// paid third-party CASA security assessment. contacts.readonly /
// contacts.other.readonly, added in its place the same day, are a different
// thing — the signed-in user's OWN contacts and "other contacts"
// (auto-collected from Gmail interactions), never anyone else's directory.
// Both are "sensitive" tier, the same tier calendar access already sits at:
// ordinary Google review, no CASA. See GoogleOAuth.swift's scope comment.
//
// If both sources come up empty the view falls back to the coloured initial —
// never a generic person glyph.

@MainActor
final class AttendeePhotoStore: ObservableObject {
    static let shared = AttendeePhotoStore()

    /// email (lowercased) → photo, or nil once we know there isn't one.
    /// Published so a late lookup re-renders the avatars that asked for it.
    @Published private(set) var photos: [String: NSImage] = [:]
    /// email → the contact's real name. EventKit often supplies only an
    /// address ("teddyzeta0799@gmail.com" → "T"); a contact card turns that
    /// into a person.
    @Published private(set) var names: [String: String] = [:]

    private var resolved: Set<String> = []
    private var authorizationAsked = false
    private let store = CNContactStore()

    private var isAuthorized: Bool {
        CNContactStore.authorizationStatus(for: .contacts) == .authorized
    }

    func photo(for email: String) -> NSImage? {
        photos[email.lowercased()]
    }

    func name(for email: String) -> String? {
        names[email.lowercased()]
    }

    /// Resolve any addresses we haven't looked at yet. Safe to call from a
    /// view body — it's idempotent and does nothing once an email is known.
    func prefetch(emails: [String]) {
        let pending = emails
            .map { $0.lowercased() }
            .filter { !$0.isEmpty && !resolved.contains($0) }
        guard !pending.isEmpty else { return }
        pending.forEach { resolved.insert($0) }

        Task { @MainActor in
            if await ensureAuthorized() {
                for email in pending {
                    let found = Self.lookup(email: email, in: store)
                    if let image = found.photo { photos[email] = image }
                    if let name = found.name, !name.isEmpty { names[email] = name }
                }
            }
            // Whoever Contacts could not place — including everyone when
            // Contacts access was refused outright.
            await resolveFromGoogle(pending.filter { photos[$0] == nil })
        }
    }

    // MARK: Google People — the signed-in user's own contacts

    private func resolveFromGoogle(_ emails: [String]) async {
        guard !emails.isEmpty, GoogleOAuth.shared.isSignedIn,
              let token = try? await GoogleOAuth.shared.validAccessToken() else { return }

        for email in emails {
            guard let found = await Self.searchContacts(email: email, token: token) else { continue }
            if let image = found.photo { photos[email] = image }
            if let name = found.name, !name.isEmpty, names[email] == nil { names[email] = name }
        }
    }

    /// `people:searchContacts` — the signed-in user's OWN contacts plus
    /// "other contacts" (people auto-collected from Gmail interactions but
    /// never explicitly saved), which is why this reaches colleagues who were
    /// never added as a contact by hand. NOT the org-wide directory; that
    /// endpoint (`people:searchDirectoryPeople`) needs a different, restricted
    /// scope this app deliberately does not request.
    nonisolated private static func searchContacts(
        email: String, token: String
    ) async -> (photo: NSImage?, name: String?)? {
        var components = URLComponents(
            string: "https://people.googleapis.com/v1/people:searchContacts")!
        components.queryItems = [
            .init(name: "query", value: email),
            .init(name: "readMask", value: "photos,names,emailAddresses"),
            .init(name: "pageSize", value: "5"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 12

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]]
        else { return nil }

        // The search is FUZZY — it will happily return a contact whose name or
        // company merely mentions the query. Match the address exactly or take
        // nothing: a confidently wrong face is worse than a letter.
        for result in results {
            guard let person = result["person"] as? [String: Any] else { continue }
            let addresses = (person["emailAddresses"] as? [[String: Any]]) ?? []
            guard addresses.contains(where: {
                ($0["value"] as? String)?.lowercased() == email.lowercased()
            }) else { continue }

            let name = (person["names"] as? [[String: Any]])?
                .compactMap { $0["displayName"] as? String }.first

            // Skip Google's generic silhouette — flagged `default: true`. The
            // coloured initial says more than a grey bust does.
            let url = (person["photos"] as? [[String: Any]])?
                .first { ($0["default"] as? Bool) != true }
                .flatMap { $0["url"] as? String }
                .flatMap(URL.init(string:))

            var image: NSImage?
            if let url,
               let (bytes, imageResponse) = try? await URLSession.shared.data(from: url),
               (imageResponse as? HTTPURLResponse)?.statusCode == 200 {
                image = NSImage(data: bytes)
            }
            return (image, name)
        }
        return nil
    }

    /// Ask once per launch, and only when a meeting actually has attendees —
    /// so the prompt appears in context, not at startup for no visible reason.
    private func ensureAuthorized() async -> Bool {
        if isAuthorized { return true }
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status == .notDetermined, !authorizationAsked else { return false }
        authorizationAsked = true
        return await withCheckedContinuation { continuation in
            store.requestAccess(for: .contacts) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    nonisolated private static func lookup(
        email: String, in store: CNContactStore
    ) -> (photo: NSImage?, name: String?) {
        let predicate = CNContact.predicateForContacts(matchingEmailAddress: email)
        let keys: [CNKeyDescriptor] = [
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        ]
        guard let contact = try? store.unifiedContacts(matching: predicate,
                                                       keysToFetch: keys).first else {
            return (nil, nil)
        }
        let image = contact.thumbnailImageData.flatMap(NSImage.init(data:))
        return (image, CNContactFormatter.string(from: contact, style: .fullName))
    }
}
