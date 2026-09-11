import Foundation

// MARK: - ActionItemDetector — the phrases in a note that read like commitments
//
// OTTO UNDERLINES. OTTO DOES NOT REWRITE. Nothing in this file edits a note:
// it reads a string and hands back ranges into it. The user's words stay as
// they were typed — lowercase, missing punctuation, telegraphic dashes, typos
// and all. That constraint is the feature; everything else here serves it.
//
// LOCAL, AND ONLY LOCAL. Rules over a string, in this process. Note text never
// leaves the device, which is why there is no setting to switch this off and no
// disclosure to write: there is nothing to disclose. A model call would be more
// accurate and would also mean sending someone's meeting notes somewhere, which
// is not a trade this feature is allowed to make.
//
// PRECISION OVER RECALL, and this is the tuning decision that matters. Three
// underlines in five lines is noise, and the feature dies of over-eagerness long
// before it dies of missing one. Everything below leans toward underlining
// FEWER, more certain spans: cue words must be strong, facts are rejected
// outright, and there are hard caps on density and count.

/// One phrase worth offering as a to-do.
struct DetectedAction: Equatable, Identifiable {
    /// Where it sits in the string it was detected in. UTF-16, so it can be
    /// handed straight to NSTextStorage.
    let range: NSRange
    /// The phrase exactly as the user wrote it. This is the to-do's title
    /// unless normalisation finds something obvious to fix.
    let phrase: String
    /// A deadline the phrase carried, if it carried one.
    let dueDate: Date?

    var id: String { "\(range.location)-\(range.length)-\(phrase)" }
}

enum ActionItemDetector {

    /// Never more than this in one note, however long it is. A note that is all
    /// underlines is a note with none.
    static let maxPerNote = 4

    // MARK: Vocabulary
    //
    // Italian and English together, with no language setting — real notes mix
    // them mid-sentence and asking the user to declare a language would be
    // asking them to do the work this is supposed to save.

    /// First-person commitments: the user said they would do it.
    private static let commitments = [
        // Italian
        "mando io", "mando", "faccio io", "faccio", "scrivo", "chiamo", "preparo",
        "invio", "controllo", "verifico", "sento", "parlo con", "ci penso io",
        "me ne occupo", "porto", "aggiorno", "fisso",
        // English
        "i'll", "i will", "ill send", "i send", "i'm going to", "im going to",
        "let me", "i can send", "i'll ask", "i'll check",
    ]

    /// Obligations: something the user has to do.
    private static let obligations = [
        // Italian
        "devo", "dobbiamo", "bisogna", "va fatto", "da fare", "occorre",
        "mi tocca", "ho da",
        // English
        "i need to", "we need to", "i have to", "we have to", "need to",
        "have to", "must", "to do", "todo", "follow up", "action:",
    ]

    /// Imperative or infinitive openings: "riprogrammare la revisione",
    /// "chiedere a marta", "schedule the review".
    private static let imperatives = [
        // Italian — the common ones, spelled out rather than inferred, because
        // "any word ending in -are" also catches nouns like "mare".
        "riprogrammare", "chiedere", "mandare", "rivedere", "preparare",
        "controllare", "contattare", "aggiornare", "scrivere", "fissare",
        "organizzare", "verificare", "sentire", "chiamare", "inviare",
        "ricordare", "confermare", "prenotare", "spedire", "completare",
        // English
        "send", "ask", "check", "schedule", "review", "email", "call",
        "confirm", "book", "update", "prepare", "remind", "chase", "draft",
    ]

    /// Phrases that mean a FACT is being recorded, not a task. Any of these in
    /// a clause disqualifies it outright, even if a cue word is also present —
    /// "la revisione slitta di 2 sett" is news, not work.
    private static let factMarkers = [
        // Italian
        "slitta", "è slittato", "nessuna novità", "resta", "rimane", "hanno detto",
        "ha detto", "sono", "è stato", "era", "c'è", "non c'è", "risulta",
        "chiede se", "ha chiesto se", "secondo", "pare che", "sembra che",
        // English
        "said", "there is", "there are", "was", "were", "turns out",
        "apparently", "fyi", "no news", "still open", "asked if",
    ]

    // MARK: Detection

    /// Find the offerable phrases in `text`.
    ///
    /// `ignoring` holds the phrases the user has already marked as not tasks in
    /// this note — the one piece of state the feature persists, because a
    /// dismissal the detector forgets is a dismissal that reappears on the next
    /// keystroke.
    static func detect(in text: String, ignoring: Set<String> = []) -> [DetectedAction] {
        let ns = text as NSString
        var found: [DetectedAction] = []
        var sentencesSeen = 0

        for clause in clauses(in: ns) {
            let raw = ns.substring(with: clause)
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            sentencesSeen += 1
            guard trimmed.count >= 8, trimmed.count <= 120 else { continue }

            let lower = trimmed.lowercased()
            // A question is someone asking, not the user committing.
            guard !lower.hasSuffix("?") else { continue }
            guard !factMarkers.contains(where: { lower.contains($0) }) else { continue }
            guard qualifies(lower) else { continue }
            guard !ignoring.contains(trimmed) else { continue }

            // The span is the clause with its surrounding whitespace and
            // punctuation trimmed off, so it is usable verbatim as a title.
            guard let tight = tighten(clause, in: ns) else { continue }
            let phrase = ns.substring(with: tight)

            found.append(DetectedAction(range: tight, phrase: phrase,
                                        dueDate: NLDateParser.parse(phrase)?.date))
            if found.count >= maxPerNote { break }
        }

        // Roughly one underline per two clauses, with a floor of two.
        //
        // The floor is the correction: taken literally, "one per two sentences"
        // means a two-line note with two genuine commitments in it keeps only
        // one — throwing away a true positive to satisfy a rule that exists to
        // stop noise in LONG notes. The cap should throttle a rambling page,
        // not punish a short one for being short.
        let densityCap = max(2, (sentencesSeen + 1) / 2)
        return Array(found.prefix(min(densityCap, maxPerNote)))
    }

    /// A clause qualifies on a STRONG cue only. Weak signals were tried and
    /// they are what turn this from a quiet underline into an app that thinks
    /// every line is a task.
    private static func qualifies(_ lower: String) -> Bool {
        if obligations.contains(where: { lower.contains($0) }) { return true }
        if commitments.contains(where: { lower.hasPrefix($0) || lower.contains(" \($0)") }) {
            return true
        }
        // An imperative counts only at the HEAD of the clause. Mid-sentence,
        // "chiedere" is usually part of a report of what someone else said.
        return imperatives.contains { lower.hasPrefix($0 + " ") }
    }

    /// Split into clauses on sentence and clause boundaries.
    ///
    /// Commas and dashes matter as much as full stops here: notes are written
    /// as runs of fragments, and "preventivo da rifare coi volumi nuovi, mando
    /// io i numeri di luglio" is two thoughts on one line — the second is the
    /// task, and underlining the whole line would give a to-do titled with both.
    private static func clauses(in ns: NSString) -> [NSRange] {
        var out: [NSRange] = []
        var start = 0
        let separators = CharacterSet(charactersIn: ".;\n\u{2014}\u{2013},")
        for index in 0..<ns.length {
            let scalar = ns.character(at: index)
            guard let unicode = Unicode.Scalar(scalar), separators.contains(unicode) else { continue }
            if index > start { out.append(NSRange(location: start, length: index - start)) }
            start = index + 1
        }
        if start < ns.length { out.append(NSRange(location: start, length: ns.length - start)) }
        return out
    }

    /// Trim whitespace and leading list glyphs off a range without moving the
    /// text — the range shrinks, the string is untouched.
    private static func tighten(_ range: NSRange, in ns: NSString) -> NSRange? {
        var location = range.location
        var end = NSMaxRange(range)
        let skip = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "-*\u{2022}\u{2610}\u{2611}"))
        while location < end,
              let u = Unicode.Scalar(ns.character(at: location)), skip.contains(u) {
            location += 1
        }
        while end > location,
              let u = Unicode.Scalar(ns.character(at: end - 1)),
              CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":-")).contains(u) {
            end -= 1
        }
        guard end > location else { return nil }
        return NSRange(location: location, length: end - location)
    }

    // MARK: Title
    //
    // THE ONE ALLOWED EDIT, and it happens on the to-do, never in the note.

    /// Capitalise the first letter for the to-do's title. Nothing else: the
    /// phrase the user wrote is the phrase the to-do wears, because a title
    /// that has been "improved" no longer matches the words still underlined
    /// in the note behind it.
    static func title(for action: DetectedAction) -> String {
        title(forPhrase: action.phrase)
    }

    static func title(forPhrase phrase: String) -> String {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return trimmed }
        return first.uppercased() + trimmed.dropFirst()
    }

    /// The deadline a phrase carries, if it carries one. The same parser the
    /// capture field uses, so "entro ven" means the same thing typed into a
    /// note as typed into the list.
    static func dueDate(in phrase: String) -> Date? {
        NLDateParser.parse(phrase)?.date
    }
}

// MARK: - ActionPicker — "Aggiungi a", and the sections to put it in

import SwiftUI

/// Opens under the phrase it acts on, never over it — the whole point is that
/// you can still read the words you are filing.
struct ActionPicker: View {
    let phrase: String
    let dueDate: Date?
    let onPick: (UUID) -> Void
    let onDismiss: () -> Void

    @ObservedObject private var store = TodoStore.shared

    /// Three, then the rest behind a "…". With ten lists this must not become
    /// a menu — and the first one is preselected because the list you filed
    /// into last is overwhelmingly the list you mean now.
    private static let maxShown = 3

    private var sections: [TodoCollection] { store.pickerSections() }

    var body: some View {
        let shown = Array(sections.prefix(Self.maxShown))
        HStack(spacing: 11) {
            Text(L10n.t("notes.action.addTo"))
                .font(.system(size: 12.5))
                .foregroundStyle(DSColor.textSecondary)
                .fixedSize()

            ForEach(Array(shown.enumerated()), id: \.element.id) { index, section in
                Button { onPick(section.id) } label: {
                    Text(section.name)
                        .font(.system(size: 12, weight: index == 0 ? .semibold : .regular))
                        .foregroundStyle(index == 0 ? DSColor.onAccentFill : DSColor.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(index == 0 ? LabMetrics.accent
                                                      : Color.white.opacity(0.06))
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("\(index + 1)")
            }

            if sections.count > Self.maxShown {
                Menu {
                    ForEach(sections.dropFirst(Self.maxShown)) { section in
                        Button(section.name) { onPick(section.id) }
                    }
                } label: {
                    Text("\u{2026}")
                        .font(.system(size: 12))
                        .foregroundStyle(DSColor.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            if let dueDate {
                // The deadline the phrase already carried. Shown, not silently
                // applied: filing something "entro ven" should say so.
                Text(ActionPicker.dueLabel(dueDate))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color(hex: "#F2B6B6"))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(hex: "#E89A9A").opacity(0.12)))
                    .fixedSize()
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DSColor.textFaint)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DSColor.menuBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.65), radius: 21, x: 0, y: 9)
    }

    private static func dueLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("EEEd")
        return f.string(from: date)
    }
}
