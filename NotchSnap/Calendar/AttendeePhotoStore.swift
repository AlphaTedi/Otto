import AppKit
import Contacts
import SwiftUI

// MARK: - AttendeePhotoStore — real faces for attendee avatars (AV-5)
//
// EventKit hands over attendee names and emails but never photos. The only
// on-device source is the user's own Contacts database, so an attendee's
// email is matched against contact cards and their thumbnail is used
// (Marcello chose this over initials-only, 2026-07-25).
//
// Everything here is local: no network, no third-party avatar service, no
// emailing a hash to Gravatar. If Contacts access is refused or a person
// isn't in the address book, the view falls back to the coloured initial —
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
            guard await ensureAuthorized() else { return }
            for email in pending {
                let found = Self.lookup(email: email, in: store)
                if let image = found.photo { photos[email] = image }
                if let name = found.name, !name.isEmpty { names[email] = name }
            }
        }
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
