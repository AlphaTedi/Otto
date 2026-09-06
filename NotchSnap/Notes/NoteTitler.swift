import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - NoteTitler — proposes a name for a note, and nothing else
//
// It never rewrites, summarizes, reformats or corrects the body. The user's
// words are the note; this only answers "what would you call it".
//
// Three engines, in order, exactly the shape BrainDumpParser already uses:
//
//   1. Apple Intelligence, where the Mac has it.
//   2. An on-device heuristic — the note's own opening clause.
//   3. The date.
//
// BOTH working engines run on this Mac. No note body leaves the device, so
// title generation does not open a new privacy path and owes no settings
// switch; if a network model is ever added here, that stops being true and the
// handoff's rule applies (surface it, make it switchable, fall back to dates
// when it is off).
//
// Failure is silent by design. A generation error is not an alert and not an
// error state — it is the date.

enum NoteTitler {

    struct Proposal {
        let text: String
        let source: NoteTitleSource
    }

    /// Output contract, enforced on every engine including our own: one line,
    /// 2-5 words ideally, 48 characters hard, no trailing punctuation, no
    /// quotes, no emoji. Anything that fails it is rejected rather than shown.
    static let maxLength = 48

    /// The prefix the model sees. The whole note is not needed to name it, and
    /// a bounded input keeps the request predictable.
    private static let inputPrefix = 1500

    // MARK: Entry point

    static func title(for body: String) async -> Proposal? {
        let cleaned = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            if let generated = await generate(String(cleaned.prefix(inputPrefix))),
               let accepted = accept(generated) {
                return Proposal(text: accepted, source: .generated)
            }
        }
        #endif

        if let heuristic = heuristicTitle(for: cleaned) {
            // `.generated` and not `.date`: it IS a proposal drawn from the
            // body, so it wears the badge and answers ⌘⇧R like any other. The
            // badge says "not yours", which is the thing it needs to say.
            return Proposal(text: heuristic, source: .generated)
        }
        return Proposal(text: dateTitle(for: Date()), source: .date)
    }

    // MARK: Engine 1 — Apple Intelligence

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func generate(_ body: String) async -> String? {
        let session = LanguageModelSession(instructions: """
            You name notes. Given the text of a note, reply with a title for it \
            and nothing else.
            Rules: one line; two to five words; at most 48 characters; the same \
            language as the note; no trailing punctuation; no quotation marks; \
            no emoji. Never rewrite, correct or summarize the note itself.
            If the note has no recognizable subject, reply with the single word \
            NONE.
            """)
        // No racing timeout, and none is needed: the entry is ALREADY in the
        // stream under a name taken from its own words, so a slow answer costs
        // nothing but a late 200ms crossfade. The request is cancellable —
        // NotesStore holds the task and drops it if the user renames the note
        // by hand — which is the only deadline that actually matters here.
        //
        // (A Task-based race was tried first and does not compile:
        // `LanguageModelSession.Response` is not Sendable, so it cannot cross
        // a task boundary. Nothing here needs it to.)
        guard let response = try? await session.respond(to: "Note:\n\(body)") else { return nil }
        return response.content
    }
    #endif

    // MARK: Engine 2 — the note's own opening clause

    /// The first sentence-ish run of the body, trimmed to the contract.
    ///
    /// Not a summary and not an invention: it is the words the user already
    /// wrote, cut at the first natural break. When those words do not make a
    /// usable name — one word, or a wall with no break inside 48 characters —
    /// this returns nil and the date takes over. No name is invented from
    /// nothing.
    static func heuristicTitle(for body: String) -> String? {
        let cleaned = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        let firstLine = cleaned.split(separator: "\n").first.map(String.init) ?? cleaned

        // Cut at the first sentence-ending break. NOT the comma: in a real
        // sentence the first comma usually arrives long after a title should
        // have ended, so cutting there produces a truncated clause rather than
        // a name ("il contratto scade il 31 ottobre e il preavviso").
        let breaks = CharacterSet(charactersIn: ".!?;:—–\n")
        var clause = firstLine
        if let range = firstLine.rangeOfCharacter(from: breaks) {
            let head = String(firstLine[firstLine.startIndex..<range.lowerBound])
            // Only if what is left is still a name. A note that opens
            // "trasloco: chiamare l'agenzia…" breaks after ONE word, and
            // cutting there throws away the whole title to keep a label —
            // "trasloco" is then rejected as a single word and the note falls
            // all the way to a date, which is the worst of the three answers
            // for the note that most plainly says what it is about.
            if head.split(whereSeparator: { $0.isWhitespace }).count >= 2 {
                clause = head
            }
        }
        var words = clause
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !words.isEmpty else { return nil }

        // Drop a leading article BEFORE counting words, not after. Counting
        // first spends one of five slots on "il" and then the cut lands a word
        // early — "Contratto scade il 31" instead of "Contratto scade il 31
        // ottobre".
        if words.count > 2, leadingArticles.contains(words[0].lowercased()) {
            words.removeFirst()
        }

        // Five words, and a character cap under it: this is a name, not the
        // opening of the note. The note itself is one line below in the
        // stream, so the title does not have to carry the content.
        words = Array(words.prefix(5))
        while words.count > 2,
              words.joined(separator: " ").count > titleWordCap {
            words.removeLast()
        }
        // A title should not end on a preposition or a conjunction — that
        // reads as the sentence having been cut off, which it has.
        while words.count > 2, functionWords.contains(words[words.count - 1].lowercased()) {
            words.removeLast()
        }
        // Nor on an article plus whatever followed it. "Quarterly report needs
        // the new" is grammatical and still obviously mid-sentence, because
        // the article is a promise the title does not keep. Dropping the pair
        // gives "Quarterly report needs", which ends where a name ends.
        if words.count > 3, functionWords.contains(words[words.count - 2].lowercased()) {
            words.removeLast(2)
        }

        var title = words.joined(separator: " ")
        // The user's BODY is never reformatted; a title drawn from it is a new
        // string and takes a capital, the way every other title in the app has
        // one.
        if let first = title.first, first.isLowercase {
            title = first.uppercased() + title.dropFirst()
        }
        return accept(title, allowSingleWord: false)
    }

    /// Soft cap for the heuristic — well under the 48 the contract allows, so
    /// what it produces reads as a name rather than as a truncation.
    private static let titleWordCap = 38

    private static let leadingArticles: Set<String> = [
        "il", "lo", "la", "i", "gli", "le", "l'", "un", "uno", "una", "un'",
        "the", "a", "an",
    ]

    /// Words a title must not end on, in the two languages the app ships.
    private static let functionWords: Set<String> = [
        "a", "al", "allo", "alla", "ai", "agli", "alle", "e", "ed", "o", "od",
        "di", "del", "dello", "della", "dei", "degli", "delle", "da", "dal",
        "in", "nel", "nella", "con", "su", "sul", "per", "tra", "fra", "che",
        "se", "il", "lo", "la", "i", "gli", "le", "un", "uno", "una",
        "the", "an", "and", "or", "of", "to", "on", "for", "with", "at", "by",
        "from", "is", "are", "that", "if", "as", "but",
    ]

    // MARK: Engine 3 — the date

    /// `Note del 28 agosto` — localized long date, no year. Used when the body
    /// has no recognizable subject, when no engine is available, when the
    /// request times out, or when the output fails the contract.
    static func dateTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("d MMMM")
        return L10n.t("notes.dateTitle") + " " + formatter.string(from: date)
    }

    // MARK: The contract

    /// Returns the title if it satisfies the output contract, nil otherwise.
    /// Applied to OUR heuristic too — a rule we only enforce on the model is a
    /// rule we do not believe in.
    private static func accept(_ raw: String, allowSingleWord: Bool = true) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Multi-line answers are rejected outright rather than truncated: a
        // model that ignored "one line" has ignored the brief.
        guard !text.contains("\n") else { return nil }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’«»"))
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?-–— "))
        guard !text.isEmpty, text.uppercased() != "NONE", text.count <= maxLength else { return nil }
        guard !text.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) else { return nil }
        if !allowSingleWord, text.split(separator: " ").count < 2 { return nil }
        return text
    }
}
