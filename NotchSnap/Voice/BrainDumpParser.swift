import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - BrainDumpParser — transcript → structured to-dos (VC-3, VC-7, VC-8)
//
// Two engines, same output:
//
//   • Apple Intelligence (macOS 26 + Apple silicon): the on-device
//     SystemLanguageModel returns a typed @Generable result — the PRD's
//     preferred path. Zero network calls, free inference.
//   • Everywhere else (incl. Marcello's 2018 Intel Mac, which can never run
//     Foundation Models): a deterministic clause parser. Splits the ramble on
//     spoken conjunctions, reads urgency words, matches category names, and
//     hands date phrases to the EXISTING NLDateParser (VC-7 — dates are never
//     reimplemented here).
//
// Both paths are fully on-device: the fallback is local string work, so the
// "nothing leaves your Mac" promise holds on every machine, not just the
// Apple Intelligence ones.

struct ParsedTodo: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var suggestedCategoryName: String?
    var urgency: TodoUrgency
    var dueDatePhrase: String?
    /// Resolved from `dueDatePhrase` by NLDateParser (VC-7).
    var dueDate: Date?
}

@MainActor
enum BrainDumpParser {

    /// Which engine will actually run — surfaced in the UI so the privacy and
    /// capability story is honest rather than implied.
    enum Engine {
        case appleIntelligence
        case onDeviceRules

        var caption: String {
            switch self {
            case .appleIntelligence: return L10n.t("voice.engine.ai")
            case .onDeviceRules:     return L10n.t("voice.engine.rules")
            }
        }
    }

    static var activeEngine: Engine {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                return .appleIntelligence
            }
        }
        #endif
        return .onDeviceRules
    }

    /// Parse a spoken brain-dump into structured to-dos. Never throws: a
    /// failed or empty model parse falls back to rules, and a failed rule
    /// parse falls back to the raw transcript as a single to-do (AV-3) — the
    /// user's words are never silently discarded.
    static func parse(transcript: String, collections: [TodoCollection]) async -> [ParsedTodo] {
        let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            if let modelParsed = await parseWithAppleIntelligence(cleaned, collections: collections),
               !modelParsed.isEmpty {
                return modelParsed
            }
            // Model unavailable mid-flight or returned nothing usable → rules.
        }
        #endif

        let ruleParsed = parseWithRules(cleaned, collections: collections)
        if !ruleParsed.isEmpty { return ruleParsed }

        // AV-3: last resort — keep the words, let the user clean them up.
        return [ParsedTodo(title: cleaned, suggestedCategoryName: nil,
                           urgency: .low, dueDatePhrase: nil, dueDate: nil)]
    }

    // MARK: - Engine 1: Apple Intelligence (macOS 26 + Apple silicon)

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func parseWithAppleIntelligence(
        _ transcript: String, collections: [TodoCollection]
    ) async -> [ParsedTodo]? {
        let names = collections.filter { !$0.isSystemToday }.map(\.name)
        let categoryHint = names.isEmpty ? "none" : names.joined(separator: ", ")
        let session = LanguageModelSession(instructions: """
            You turn a spoken brain-dump into distinct to-do items.
            Split the transcript into separate tasks. Clean up spoken filler \
            ("um", "like", "you know") and rephrase each task as a short \
            imperative title. Do not invent tasks that were not said.
            Available categories: \(categoryHint).
            """)
        do {
            let response = try await session.respond(
                to: "Transcript: \(transcript)",
                generating: FMBrainDumpResult.self
            )
            return response.content.todos.map { todo in
                let resolved = todo.dueDatePhrase.flatMap { NLDateParser.parse($0) }
                return ParsedTodo(
                    title: todo.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    suggestedCategoryName: todo.suggestedCategoryName,
                    urgency: TodoUrgency(spoken: todo.urgency),
                    dueDatePhrase: todo.dueDatePhrase,
                    dueDate: resolved?.date
                )
            }.filter { !$0.title.isEmpty }
        } catch {
            print("[BrainDumpParser] Apple Intelligence parse failed: \(error)")
            return nil
        }
    }
    #endif

    // MARK: - Engine 2: deterministic rules (every other Mac)

    /// Spoken separators, longest first so "and then" wins over "and".
    private static let separators = [
        ", and then ", " and then ", ", and also ", " and also ",
        ", also ", " also ", ", and ", " and ", ", then ", " then ",
        "; ", ". ", ", ",
    ]

    static func parseWithRules(_ transcript: String,
                               collections: [TodoCollection]) -> [ParsedTodo] {
        var clauses = [transcript]
        for separator in separators {
            clauses = clauses.flatMap { chunk -> [String] in
                // Don't shatter short fragments — a comma inside a 3-word
                // phrase is punctuation, not a task boundary.
                guard chunk.count > 24 else { return [chunk] }
                return chunk.components(separatedBy: separator)
            }
        }

        var result: [ParsedTodo] = []
        for raw in clauses {
            var clause = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard clause.count > 2 else { continue }

            let urgency = detectUrgency(in: clause)
            clause = strippingUrgencyPhrases(clause)

            let category = collections
                .filter { !$0.isSystemToday }
                .first { clause.range(of: $0.name, options: .caseInsensitive) != nil }

            // VC-7: dates come from the existing parser, which also hands back
            // the title with the phrase removed.
            var dueDate: Date?
            var datePhrase: String?
            if let match = NLDateParser.parse(clause) {
                dueDate = match.date
                datePhrase = (clause as NSString).substring(with: match.nsRange)
                clause = match.cleanedTitle
            }

            let title = tidyTitle(clause)
            if title.isEmpty {
                // The clause was ONLY an aside — "…, that one's kind of
                // urgent". People say that about the task they just named, so
                // apply it backwards instead of dropping it on the floor.
                if urgency != .low, !result.isEmpty {
                    result[result.count - 1].urgency = urgency
                }
                continue
            }

            result.append(ParsedTodo(title: title,
                                     suggestedCategoryName: category?.name,
                                     urgency: urgency,
                                     dueDatePhrase: datePhrase,
                                     dueDate: dueDate))
        }
        return result
    }

    private static let highWords = ["urgent", "urgently", "asap", "critical",
                                    "important", "right away", "priority",
                                    "urgente", "importante", "subito"]
    private static let lowWords = ["whenever", "no rush", "sometime", "eventually",
                                   "at some point", "quando puoi", "senza fretta"]

    private static func detectUrgency(in clause: String) -> TodoUrgency {
        let lower = clause.lowercased()
        if highWords.contains(where: lower.contains) { return .high }
        if lowWords.contains(where: lower.contains) { return .low }
        return .low   // TD-2: Low is the default
    }

    /// Remove the urgency aside ("that one's urgent") so it doesn't survive
    /// into the title — the urgency is captured structurally instead.
    private static func strippingUrgencyPhrases(_ clause: String) -> String {
        var result = clause
        let asides = [
            "that one's kind of urgent", "that one is kind of urgent",
            "that one's urgent", "that one is urgent",
            "kind of urgent", "it's urgent", "its urgent", "very urgent",
            "and it's important", "that's important",
        ]
        for aside in asides {
            result = result.replacingOccurrences(of: aside, with: "",
                                                 options: [.caseInsensitive])
        }
        return result
    }

    /// Drop leading spoken filler and normalize whitespace/punctuation.
    private static func tidyTitle(_ raw: String) -> String {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let leadingFiller = ["um ", "uh ", "so ", "and ", "also ", "then ",
                             "i need to ", "i have to ", "i should ",
                             "remember to ", "don't forget to ",
                             "devo ", "ricordati di "]
        var changed = true
        while changed {
            changed = false
            for filler in leadingFiller where title.lowercased().hasPrefix(filler) {
                title = String(title.dropFirst(filler.count))
                changed = true
            }
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Removing a date phrase can strand the preposition that introduced
        // it — "book the flight for <Friday>" → "book the flight for".
        let danglingTails = ["for", "on", "at", "by", "before", "until",
                             "this", "next", "per", "entro"]
        changed = true
        while changed {
            changed = false
            let words = title.split(separator: " ")
            if let last = words.last,
               danglingTails.contains(String(last).lowercased()) {
                title = words.dropLast().joined(separator: " ")
                changed = true
            }
        }

        // Bare urgency adverbs carry no information once urgency is structural.
        for adverb in ["urgently", "asap", "urgent", "right away"] {
            if title.lowercased().hasSuffix(" " + adverb) {
                title = String(title.dropLast(adverb.count + 1))
            }
        }

        title = title.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;-"))
        title = title.replacingOccurrences(of: "\\s{2,}", with: " ",
                                           options: .regularExpression)
        // Speech output is lowercase-ish; capitalize just the first letter.
        guard let first = title.first else { return "" }
        return String(first).uppercased() + title.dropFirst()
    }
}

// MARK: - Typed model output (Apple Intelligence path only)

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
struct FMParsedTodo {
    @Guide(description: "A concise task title, cleaned up from spoken phrasing")
    var title: String

    @Guide(description: "Best-guess category name from the provided list, or omit if unclear")
    var suggestedCategoryName: String?

    @Guide(description: "Exactly one of: low, medium, high — infer from urgency language like 'urgent' or 'whenever'")
    var urgency: String

    @Guide(description: "A natural language date phrase if one was mentioned, e.g. 'tomorrow', otherwise omit")
    var dueDatePhrase: String?
}

@available(macOS 26.0, *)
@Generable
struct FMBrainDumpResult {
    @Guide(description: "One or more distinct tasks extracted from the transcript")
    var todos: [FMParsedTodo]
}
#endif

extension TodoUrgency {
    /// Map the model's free-text urgency onto the enum, defaulting to Low.
    init(spoken: String) {
        switch spoken.lowercased().trimmingCharacters(in: .whitespaces) {
        case "high", "urgent", "alta":   self = .high
        case "medium", "media", "med":   self = .medium
        default:                          self = .low
        }
    }
}
