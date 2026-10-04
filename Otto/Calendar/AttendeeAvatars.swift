import SwiftUI
import AppKit

// MARK: - Attendee avatars (calendar PRD §3.3, AV-4..6)
//
// Replaces the "with Rose, Wessel" text line and the colored accent stripe —
// the stripe-plus-text layout is exactly what read as generic/AI-templated
// (Marcello, 2026-07-25). A real avatar stack is the product signal.
//
// NOTE on AV-5: profile photos would come from the Google Calendar API. The
// EventKit provider has no access to attendee photos, so this renders the
// initial-based fallback on every avatar today. `imageURL` is the seam for
// photos once a Google OAuth provider exists — never a person-outline glyph.

struct AttendeeAvatar: View {
    let name: String
    /// Used to resolve a real photo from Contacts; nil ⇒ initial only.
    var email: String? = nil
    var diameter: CGFloat = 24
    /// Dim non-urgent rows without changing the layout (Today's later events).
    var isMuted: Bool = false
    /// Ring colour — matches whatever surface the avatar sits on, so an
    /// overlapping stack reads as separate discs.
    var ringColor: Color = DSColor.fieldBackground

    @ObservedObject private var photos = AttendeePhotoStore.shared

    /// Separator width between overlapping discs.
    private var ringWidth: CGFloat { diameter > 20 ? 2 : 1.5 }

    var body: some View {
        Group {
            if let email, let image = photos.photo(for: email) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: diameter, height: diameter)
                    .clipShape(Circle())
                    .opacity(isMuted ? 0.65 : 1)
            } else {
                // Prefer the contact's real name for the initial — an
                // address-only attendee would otherwise read as its domain.
                let display = email.flatMap { photos.name(for: $0) } ?? name
                let tone = Self.tone(for: display)
                Circle()
                    .fill(tone.background.opacity(isMuted ? 0.55 : 1))
                    .frame(width: diameter, height: diameter)
                    .overlay(
                        // Proportions from Marcello's spec: a 14pt letter on a
                        // 32pt disc, medium weight, line-height 100%.
                        Text(Self.initial(for: display))
                            .font(.system(size: diameter * 0.4375, weight: .medium))
                            .foregroundStyle(tone.foreground.opacity(isMuted ? 0.7 : 1))
                    )
            }
        }
        // Inside the edge, under the ring: a pale disc or a light photo would
        // otherwise dissolve into whatever sits behind it.
        .overlay(
            Circle().strokeBorder(DSColor.AvatarPalette.innerStroke, lineWidth: 1)
        )
        // The separator sits OUTSIDE the disc rather than on top of it, so it
        // cannot eat into the artwork or hide the hairline above. Drawn as a
        // background it adds no layout size — neighbours still overlap by the
        // stack's own ratio.
        .background(
            Circle()
                .fill(ringColor)
                .frame(width: diameter + ringWidth * 2,
                       height: diameter + ringWidth * 2)
        )
    }

    static func initial(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Emails ("rose@x.com") should key off the local part, not the "@".
        let base = trimmed.split(separator: "@").first.map(String.init) ?? trimmed
        guard let first = base.first(where: { $0.isLetter || $0.isNumber }) else { return "?" }
        return String(first).uppercased()
    }

    /// AV-5: stable per-person tone from the pastel avatar family.
    /// Hash is computed by hand — Swift's `hashValue` is randomly seeded per
    /// process, so a person's colour would change on every launch.
    static func tone(for name: String) -> DSColor.AvatarPalette.Tone {
        let palette = DSColor.AvatarPalette.all
        var hash: UInt64 = 5381
        for byte in name.lowercased().utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return palette[Int(hash % UInt64(palette.count))]
    }
}

/// AV-6: overlapping stack, capped, with a "+N" disc for the remainder.
// MARK: - AccountAvatar — the signed-in user, wherever they are shown

struct AvatarStack: View {
    let names: [String]
    /// Parallel to `names` where known — drives the Contacts photo lookup.
    var emails: [String] = []
    var diameter: CGFloat = 24
    var maxVisible: Int = 3
    var isMuted: Bool = false
    var ringColor: Color = DSColor.fieldBackground

    /// How far each disc slides under the previous one. 0.42 buried the
    /// initial of every avatar but the last — legible only when every
    /// attendee happens to have a Contacts photo.
    var overlapRatio: CGFloat = 0.30
    private var overlap: CGFloat { diameter * overlapRatio }

    var body: some View {
        // Kick off (idempotent) photo resolution for whoever is on screen.
        let _ = AttendeePhotoStore.shared.prefetch(emails: emails)
        let shown = Array(names.prefix(maxVisible))
        let extra = names.count - shown.count
        HStack(spacing: -overlap) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, name in
                AttendeeAvatar(name: name,
                               email: index < emails.count ? emails[index] : nil,
                               diameter: diameter,
                               isMuted: isMuted, ringColor: ringColor)
            }
            if extra > 0 {
                // Deliberately NOT pastel: this disc is a count, not a person,
                // and the dark ground is what separates "and 3 more" from the
                // faces beside it.
                Circle()
                    .fill(Color(hex: "#3A3A3A"))
                    .frame(width: diameter, height: diameter)
                    .overlay(
                        // Same ratio as an initial — it used to be smaller
                        // (0.34) to make room for two glyphs, which just made
                        // the count unreadable (Marcello, 2026-07-26). A big
                        // overflow ("+57") shrinks to fit instead of forcing
                        // every count to be tiny.
                        Text("+\(extra)")
                            .font(.system(size: diameter * 0.40, weight: .semibold))
                            .foregroundStyle(DSColor.textPrimaryBright)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, diameter * 0.1)
                    )
                    .overlay(
                        Circle().strokeBorder(DSColor.AvatarPalette.innerStroke, lineWidth: 1)
                    )
                    .background(
                        Circle()
                            .fill(ringColor)
                            .frame(width: diameter + (diameter > 20 ? 4 : 3),
                                   height: diameter + (diameter > 20 ? 4 : 3))
                    )
            }
        }
    }
}
