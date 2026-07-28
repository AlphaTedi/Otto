import SwiftUI

// MARK: - VoiceCaptureView — listening + review surfaces (PRD §3.2)
//
// Renders inside the notch panel like every other mode. All colors/metrics
// come from DesignSystem.swift.

struct VoiceCaptureView: View {
    @ObservedObject private var voice = VoiceCaptureController.shared
    @ObservedObject private var store = TodoStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch voice.phase {
            case .listening:  listening
            case .parsing:    parsing
            case .review:     review
            case .unavailable(let reason): unavailable(reason)
            case .idle:       EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Listening — waveform + live transcript

    private var listening: some View {
        VStack(spacing: 0) {
            WaveformView(level: voice.level)
                .frame(height: 36)
                .padding(.bottom, 14)

            // Provisional text: muted, because it isn't a to-do title yet.
            Text(voice.transcript.isEmpty ? L10n.t("voice.listeningHint") : voice.transcript)
                .font(.system(size: 13))
                .foregroundStyle(voice.transcript.isEmpty ? DSColor.textFaint
                                                          : Color(hex: "#CCCCCC"))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .lineLimit(4)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)
                .animation(.easeOut(duration: 0.12), value: voice.transcript)

            // The privacy claim, stated plainly (PRD §2).
            Text(L10n.t("voice.onDeviceCaption"))
                .font(.system(size: 10))
                .foregroundStyle(DSColor.textFaint)
                .frame(maxWidth: .infinity)

            HStack(spacing: 6) {
                Text(L10n.t("voice.stop"))
                    .font(.system(size: 10))
                    .foregroundStyle(DSColor.textHint)
                ShortcutHintBadge(text: "\u{21A9}")
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
        }
        .padding(.vertical, 4)
    }

    // MARK: Parsing

    private var parsing: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(L10n.t("voice.parsing"))
                .font(.system(size: 11))
                .foregroundStyle(DSColor.textMuted)
            Text(BrainDumpParser.activeEngine.caption)
                .font(.system(size: 10))
                .foregroundStyle(DSColor.textFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    // MARK: Review — editable cards, nothing created yet (VC-4/5/6)

    private var review: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(reviewHeading.uppercased())
                .font(DSFont.sectionLabel)
                .tracking(0.4)
                .foregroundStyle(DSColor.textFaint)
                .padding(.bottom, 12)

            VStack(spacing: 10) {
                ForEach(Array(voice.drafts.enumerated()), id: \.element.id) { index, draft in
                    DraftCard(
                        draft: draft,
                        isFocused: index == voice.focusedDraftIndex,
                        collectionColor: collectionColor(for: draft),
                        collectionName: collectionName(for: draft),
                        onTitleChange: { voice.updateTitle($0, at: index) },
                        onCycleUrgency: { voice.cycleUrgency(at: index) },
                        onPickCategory: { voice.setCategory($0, at: index) },
                        onRemove: { voice.remove(at: index) },
                        onFocus: { voice.focusedDraftIndex = index }
                    )
                }
            }
            .padding(.bottom, 14)

            Button(action: voice.confirm) {
                PrimaryActionButton(title: voice.confirmLabel, shortcutHint: "\u{21A9}")
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var reviewHeading: String {
        String(format: L10n.t(voice.drafts.count == 1 ? "voice.foundOne" : "voice.foundMany"),
               voice.drafts.count)
    }

    private func collectionColor(for draft: ParsedTodo) -> Color {
        guard let id = voice.resolvedCollectionID(for: draft),
              let collection = store.collection(id: id) else { return .gray }
        return collection.color
    }

    private func collectionName(for draft: ParsedTodo) -> String {
        guard let id = voice.resolvedCollectionID(for: draft),
              let collection = store.collection(id: id) else {
            return L10n.t("todo.noCollection")
        }
        return collection.name
    }

    // MARK: Unavailable (AV-2) — never a dead end

    private func unavailable(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("voice.unavailable").uppercased())
                .font(DSFont.sectionLabel)
                .tracking(0.4)
                .foregroundStyle(DSColor.textFaint)
            Text(reason)
                .font(.system(size: 11))
                .foregroundStyle(DSColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // Always point at the alternative that does work.
            Button {
                voice.cancel()
                TodoStore.shared.presetDraftToActiveCollection()
                TodoStore.shared.setMode(.create)
                NotchController.shared.focusPanel()
            } label: {
                HStack(spacing: 6) {
                    Text(L10n.t("voice.useTyping"))
                        .font(.system(size: 11))
                        .foregroundStyle(DSColor.focusAccent)
                    ShortcutHintBadge(text: "\u{2318}N")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

// MARK: - WaveformView — 7 bars driven by the real input level

private struct WaveformView: View {
    let level: CGFloat

    /// Per-bar weighting so the middle bars react most — a flat row of equal
    /// bars reads as a loading spinner, not as listening.
    private static let weights: [CGFloat] = [0.45, 0.8, 0.62, 1.0, 0.5, 0.75, 0.55]
    private static let minHeight: CGFloat = 4
    private static let maxHeight: CGFloat = 34

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(Self.weights.enumerated()), id: \.offset) { _, weight in
                Capsule(style: .continuous)
                    .fill(DSColor.focusAccent)
                    .frame(width: 3, height: height(for: weight))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.09), value: level)
    }

    private func height(for weight: CGFloat) -> CGFloat {
        let span = Self.maxHeight - Self.minHeight
        return Self.minHeight + span * min(1, level * weight * 1.6)
    }
}

// MARK: - DraftCard — one reviewable to-do (VC-5)

private struct DraftCard: View {
    let draft: ParsedTodo
    let isFocused: Bool
    let collectionColor: Color
    let collectionName: String
    let onTitleChange: (String) -> Void
    let onCycleUrgency: () -> Void
    let onPickCategory: (String?) -> Void
    let onRemove: () -> Void
    let onFocus: () -> Void

    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("", text: Binding(
                    get: { draft.title },
                    set: { onTitleChange($0) }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(DSColor.textPrimaryBright)
                .onSubmit(onFocus)

                if hover {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(DSColor.textFaint)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L10n.t("action.remove"))
                    .transition(.opacity)
                }
            }

            HStack(spacing: 6) {
                // Category chip — click cycles through the real categories.
                Menu {
                    ForEach(TodoStore.shared.collections.filter { !$0.isSystemToday }) { c in
                        Button(c.name) { onPickCategory(c.name) }
                    }
                } label: {
                    Text(collectionName)
                        .font(.system(size: 9))
                        .foregroundStyle(DSColor.primaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(collectionColor)
                        )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()

                if let phrase = draft.dueDatePhrase, !phrase.isEmpty {
                    metaChip(phrase.capitalizedFirst)
                }

                Button(action: onCycleUrgency) {
                    metaChip(draft.urgency.fullLabel)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DSRadius.controlCorner, style: .continuous)
                .fill(DSColor.fieldBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.controlCorner, style: .continuous)
                .stroke(isFocused ? DSColor.focusAccent : DSColor.panelBorder, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onFocus)
        .onHover { hovering in
            withAnimation(NotchAnimation.hintFade) { hover = hovering }
        }
    }

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9))
            .foregroundStyle(DSColor.textPrimaryBright)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(DSColor.panelBorder, lineWidth: 0.5)
            )
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
