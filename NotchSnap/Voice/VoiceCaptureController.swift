import Foundation
import SwiftUI

// MARK: - VoiceCaptureController — the voice brain-dump state machine
//
// idle → listening → parsing → review → (confirm) → idle
//
// VC-4 is the load-bearing rule: parsed to-dos ALWAYS pass through `review`.
// Nothing here writes to TodoStore except `confirm()`, which only runs from
// an explicit user action. A confident-looking parse is still just a draft.

@MainActor
final class VoiceCaptureController: ObservableObject {
    static let shared = VoiceCaptureController()

    enum Phase: Equatable {
        case idle
        case listening
        case parsing
        case review
        /// AV-1/AV-2: feature can't run here — always with a reason, never a
        /// dead end or a crash.
        case unavailable(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var drafts: [ParsedTodo] = []
    /// Index of the draft currently being edited (gets the focus border).
    @Published var focusedDraftIndex: Int = 0

    @ObservedObject private(set) var transcriber = VoiceTranscriber()

    private var parseTask: Task<Void, Never>?

    var isActive: Bool { phase != .idle }

    var transcript: String { transcriber.transcript }
    var level: CGFloat { transcriber.level }

    /// Dynamic confirm label — "Add both" / "Add all 3" (PRD §3.2: never a
    /// generic "Confirm", the user should know exactly what will happen).
    var confirmLabel: String {
        switch drafts.count {
        case 0:  return L10n.t("voice.addNone")
        case 1:  return L10n.t("voice.addOne")
        case 2:  return L10n.t("voice.addBoth")
        default: return String(format: L10n.t("voice.addAll"), drafts.count)
        }
    }

    // MARK: Toggle (Marcello chose press-to-start / press-to-stop)

    func toggle() {
        switch phase {
        case .idle, .unavailable:
            start()
        case .listening:
            finishListening()
        case .parsing, .review:
            cancel()
        }
    }

    func start() {
        guard VoiceTranscriber.isOnDeviceAvailable else {
            // AV-2: explain, and point at the typed flow instead.
            phase = .unavailable(L10n.t("voice.err.onDevice"))
            return
        }
        drafts = []
        focusedDraftIndex = 0
        withAnimation(NotchAnimation.contentHug) { phase = .listening }
        Task { @MainActor in
            do {
                try await transcriber.start()
            } catch {
                let message = (error as? VoiceTranscriber.StartFailure)?.errorDescription
                    ?? error.localizedDescription
                withAnimation(NotchAnimation.contentHug) { phase = .unavailable(message) }
            }
        }
    }

    /// Stop recording and hand the transcript to the parser.
    func finishListening() {
        guard phase == .listening else { return }
        let transcript = transcriber.stop()
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            withAnimation(NotchAnimation.contentHug) { phase = .idle }
            return
        }
        withAnimation(NotchAnimation.contentHug) { phase = .parsing }

        parseTask?.cancel()
        parseTask = Task { @MainActor in
            let collections = TodoStore.shared.collections
            let parsed = await BrainDumpParser.parse(transcript: transcript,
                                                     collections: collections)
            guard !Task.isCancelled else { return }
            drafts = parsed
            focusedDraftIndex = 0
            withAnimation(NotchAnimation.contentHug) {
                phase = parsed.isEmpty ? .idle : .review
            }
        }
    }

    func cancel() {
        parseTask?.cancel()
        parseTask = nil
        transcriber.stop()
        drafts = []
        withAnimation(NotchAnimation.contentHug) { phase = .idle }
    }

    // MARK: Review editing (VC-5)

    func remove(at index: Int) {
        guard drafts.indices.contains(index) else { return }
        withAnimation(NotchAnimation.contentHug) {
            drafts.remove(at: index)
            focusedDraftIndex = min(focusedDraftIndex, max(0, drafts.count - 1))
            if drafts.isEmpty { phase = .idle }
        }
    }

    func updateTitle(_ title: String, at index: Int) {
        guard drafts.indices.contains(index) else { return }
        drafts[index].title = title
    }

    func cycleUrgency(at index: Int) {
        guard drafts.indices.contains(index) else { return }
        withAnimation(NotchAnimation.hintFade) {
            drafts[index].urgency = drafts[index].urgency.next
        }
    }

    func setCategory(_ name: String?, at index: Int) {
        guard drafts.indices.contains(index) else { return }
        withAnimation(NotchAnimation.hintFade) {
            drafts[index].suggestedCategoryName = name
        }
    }

    func moveFocus(_ offset: Int) {
        guard !drafts.isEmpty else { return }
        focusedDraftIndex = max(0, min(drafts.count - 1, focusedDraftIndex + offset))
    }

    /// VC-8: resolve a draft's category to a real collection — the suggested
    /// name if it matches, else the app's existing default.
    func resolvedCollectionID(for draft: ParsedTodo) -> UUID? {
        let store = TodoStore.shared
        if let name = draft.suggestedCategoryName {
            let assignable = store.collections.filter { !$0.isSystemToday }
            if let exact = assignable.first(where: {
                $0.name.compare(name, options: .caseInsensitive) == .orderedSame
            }) { return exact.id }
            if let fuzzy = assignable.first(where: {
                $0.name.localizedCaseInsensitiveContains(name)
                    || name.localizedCaseInsensitiveContains($0.name)
            }) { return fuzzy.id }
        }
        return store.defaultCreationCollectionID
    }

    // MARK: Confirm (VC-6) — the ONLY path that writes to the store

    func confirm() {
        guard phase == .review, !drafts.isEmpty else { return }
        let store = TodoStore.shared
        for draft in drafts {
            guard let collectionID = resolvedCollectionID(for: draft) else { continue }
            store.addItem(title: draft.title,
                          collectionID: collectionID,
                          urgency: draft.urgency,
                          dueDate: draft.dueDate)
        }
        drafts = []
        withAnimation(NotchAnimation.contentHug) { phase = .idle }
    }
}
