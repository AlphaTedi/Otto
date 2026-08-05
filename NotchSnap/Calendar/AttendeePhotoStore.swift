import AppKit
import Contacts
import SwiftUI

// MARK: - AttendeePhotoStore — real faces for attendee avatars (AV-5)
//
// EventKit hands over attendee names and emails but never photos, so faces
// have to be resolved from somewhere else. Two sources, tried in order:
//
//   1. The user's own Contacts database — local, instant, free.
//   2. The Google Workspace directory, but ONLY when the user has signed in
//      with Google. Contacts only knows people the user personally saved,
//      which is why colleagues appeared as letters in NotchSnap while the
//      same meeting in Google Calendar showed their faces
//      (Marcello, 2026-08-05).
//
// The Google lookup is the one piece of this file that touches the network.
// It sends an attendee's address to Google's People API under the user's own
// OAuth token, and only for addresses already listed on a meeting the user
// was invited to. There is still no third-party avatar service and no hash
// emailed to Gravatar.
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

    // MARK: Google Workspace directory

    private func resolveFromGoogle(_ emails: [String]) async {
        guard !emails.isEmpty, GoogleOAuth.shared.isSignedIn,
              let token = try? await GoogleOAuth.shared.validAccessToken() else { return }

        for email in emails {
            guard let found = await Self.directoryLookup(email: email, token: token) else { continue }
            if let image = found.photo { photos[email] = image }
            if let name = found.name, !name.isEmpty, names[email] == nil { names[email] = name }
        }
    }

    nonisolated private static func directoryLookup(
        email: String, token: String
    ) async -> (photo: NSImage?, name: String?)? {
        var components = URLComponents(
            string: "https://people.googleapis.com/v1/people:searchDirectoryPeople")!
        components.queryItems = [
            .init(name: "query", value: email),
            .init(name: "readMask", value: "photos,names,emailAddresses"),
            .init(name: "sources", value: "DIRECTORY_SOURCE_TYPE_DOMAIN_PROFILE"),
            .init(name: "sources", value: "DIRECTORY_SOURCE_TYPE_DOMAIN_CONTACT"),
            .init(name: "pageSize", value: "5"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 12

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let people = json["people"] as? [[String: Any]]
        else { return nil }

        // A directory search is FUZZY — it will happily return a different
        // colleague whose profile merely mentions the query. Match the address
        // exactly or take nothing: a confidently wrong face is far worse than
        // a letter.
        for person in people {
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
