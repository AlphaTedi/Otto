import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - InlineDraftRow — the to-do being typed
//
// The replacement for the creation card, and the panel's only visible way to
// make a to-do — so it is ALWAYS here, at the top of the list, whether or not
// anyone asked for it. Summoning it with ⌃⇧N was not enough: a user who opens
// the notch and looks at it has to be able to see how to add something.
//
// It is deliberately built out of the SAME parts as a real row — checkbox at
// 14pt, the same leading gap, the same title type — because the point of
// typing in place is that you can see the thing you are making take its final
// shape. It also spans the FULL panel width; a short box floating in the
// middle of a wide notch reads as a stray control rather than as the first
// row of the list.
//
// Four states, and they have to be told apart at a glance:
//
//   1. Idle + empty     neutral fill, muted placeholder — an invitation
//   2. Focused + empty  destination tint + border, caret blinking
//   3. Idle + typed     neutral fill, full-brightness text
//   4. Focused + typing tint + border, accent caret and selection
//
// The tint and the caret both take the DESTINATION section's color, so "where
// is my cursor" and "where is this going" have one answer. That also makes ⇥
// legible in the row itself, not only up in the tab bar — and it is what
// makes an honest job of Today, which cannot hold to-dos: aim at Today and
// the row quietly wears the section it will actually file into.

struct InlineDraftRow: View {
    /// Reported by the field itself; 0 until the first layout pass.
    @State private var measuredFieldWidth: CGFloat = 0
    /// The destination section's color.
    let accent: Color

    @ObservedObject private var store = TodoStore.shared
    @State private var hover = false

    /// The well is BLACK in both appearances, at different strengths, so it
    /// cannot be written with `dynamicOverlay` — that flips to white in the
    /// dark, which is the grey this is trying to stop being.
    @Environment(\.colorScheme) private var colorScheme

    private var focused: Bool { store.draftFocused }
    private var parsed: NLDateMatch? { NLDateParser.parse(store.draftTitle) }

    /// How far the well sits below the panel. Deeper in the dark, where there
    /// is more room beneath the panel before a well turns into a hole.
    private var wellOpacity: Double {
        if colorScheme == .dark {
            return focused ? 0.14 : (hover ? 0.18 : 0.22)
        }
        return focused ? 0.03 : (hover ? 0.04 : 0.05)
    }

    /// FB5, inherited from the creation card: an NSViewRepresentable's own
    /// sizeThatFits is NOT re-invoked on a pure content change, so the height
    /// has to be computed here — where `draftTitle` is observed — or the field
    /// stays stuck at one line while the text wraps out of sight.
    private var fieldHeight: CGFloat {
        // THE FIELD'S OWN WIDTH, measured — not the panel's minus a list of
        // subtractions.
        //
        // The estimate is where both bugs came from. It wrapped the text at a
        // different width than the field does, so the computed height was for
        // a different number of lines than the one on screen: the row spilled
        // out of its own box while the measurement still thought it fitted,
        // and then caught up all at once when the two finally agreed. That
        // catching-up is the jump (Marcello, 2026-09-21).
        //
        // The estimate survives only as the value for the first frame, before
        // the geometry reader has reported anything.
        let panelWidth = CGFloat(NotchController.shared.expandedWidth)
        let estimate = max(120, panelWidth - CGFloat(DSSpacing.panelPadding) * 2 - 20 - 24 - 112)
        let width = measuredFieldWidth > 0 ? measuredFieldWidth : estimate
        let text = store.draftTitle.isEmpty ? " " : store.draftTitle
        // As displayed: an image token is one chip, not its long markdown.
        let measured = AttachmentStore.chipped(
            text, attributes: [.font: NSFont.systemFont(ofSize: DSFont.todoTitleSize)]
        ).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height
        return max(HighlightingTitleField.lineHeight,
                   min(ceil(measured), HighlightingTitleField.maxHeight))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // CENTER, per the export's `align-items: center`. Top-aligning while
        // the label carries its own 8pt box is what left every checkbox
        // sitting visibly above the text it belongs to.
        HStack(alignment: .center, spacing: PanelMetrics.rowInnerGap) {
                // Back to a checkbox, and the SAME one the rows use: 18pt,
                // 2pt cyan, 6pt corner. The export draws the bar and the list
                // with one component, so the bar reads as the row you are
                // about to make rather than as a search field.
                // The DESTINATION's colour, so the bar says where the thing
                // being typed will land — the same pairing the rows use.
                RoundedRectangle(cornerRadius: PanelMetrics.checkboxRadius, style: .continuous)
                    .strokeBorder(accent, lineWidth: PanelMetrics.checkboxStroke)
                    .frame(width: PanelMetrics.checkboxSize, height: PanelMetrics.checkboxSize)

                ZStack(alignment: .topLeading) {
                    // Stays until the first character, the way every other
                    // Mac text field behaves — it brightens on focus instead
                    // of vanishing, so an empty focused field still says what
                    // it is for.
                    if store.draftTitle.isEmpty {
                        Text(L10n.t("todo.titlePlaceholder"))
                            .font(DSFont.todoTitle)
                            .foregroundStyle(focused ? DSColor.textFaint : DSColor.textHint)
                            .allowsHitTesting(false)
                    }
                    HighlightingTitleField(
                        text: $store.draftTitle,
                        // NL-2: a recognized date phrase colors inline, in
                        // place, and is stripped from the title only on commit.
                        highlightRange: parsed?.nsRange,
                        accent: accent,
                        wantsFocus: store.draftWantsFocus,
                        onFocusChange: { isFocused in
                            store.draftFocused = isFocused
                            if isFocused { store.draftWantsFocus = false }
                        },
                        // Pasted and dropped images, like the floating
                        // panels' field — this one never accepted them
                        // (Marcello, 2026-10-02).
                        allowsImages: true
                    )
                    .frame(height: fieldHeight)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: DraftFieldWidthKey.self,
                                               value: proxy.size.width)
                    }
                )
                .onPreferenceChange(DraftFieldWidthKey.self) { measuredFieldWidth = $0 }

                // Spelled out, not a bare ⇥. The glyph alone was "not really
                // clear enough, and it's really hard to understand what you
                // can do with it" (Marcello, 2026-08-16) — a keyboard hint
                // that has to be decoded is not a hint. The word plus what it
                // does needs no decoding, and there is room for it now that
                // the row spans the panel.
                //
                // Always present, just quieter when idle: this is the only
                // thing telling you the row has a destination at all, so
                // hiding it until hover hid the whole feature.
                // Two keys, no prose.
                //
                // "Switch section" spelled it out because the ⇥ glyph alone
                // was undecodable — but the words were only ever scaffolding
                // for one key, and now there are two to show. Raycast puts the
                // keys bare at the right edge and lets them be keys; the
                // tooltips still carry the words for anyone who wants them.
                // "Switch space", per the export — and always visible at the
                // stated 35%, not fading in on hover.
                HStack(spacing: 8) {
                    Text(L10n.t("todo.switchSpace"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DSColor.textFaint)
                        .fixedSize()
                    Text(L10n.t("key.tab"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DSColor.textFaint)
                        .frame(width: 32, height: 19)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(DSColor.textFaint, lineWidth: 1)
                        )
                }
            }

            // NL-3: live resolved-date caption, aligned with the title.
            if let parsed {
                Text("\u{2192} \(parsed.display)")
                    .font(.system(size: 10))
                    .foregroundStyle(DSColor.textFaint)
                    .padding(.leading, 14 + DSSpacing.rowInternalGap)
                    .transition(.opacity)
            }
        }
        // 24 / 16, as specified.
        .padding(.horizontal, PanelMetrics.barPaddingH)
        .padding(.vertical, PanelMetrics.barPaddingV)
        // Spans the notch. Without this the field reports its own ideal width
        // and the box floated mid-panel, detached from the list it belongs to.
        .frame(maxWidth: .infinity, alignment: .leading)
        // NOT a second sheet of glass. That is what made it disappear.
        //
        // Glass over glass means both layers sample the same desktop, so the
        // bar's colour was decided by the WALLPAPER — and over a dark one it
        // and the panel converged until the placeholder and the key hints were
        // barely legible (Marcello, Tahoe, 2026-08-22).
        //
        // Its contrast is now defined against the PANEL instead: a fixed step
        // away from whatever the panel resolved to, which cannot collapse no
        // matter what is behind the window. Plus a hairline that is always
        // drawn, so the bar has an edge even when the fills are close.
        .frame(minHeight: PanelMetrics.barHeight)
        // A WELL: darker than the panel, with the edge doing the finding.
        //
        // Two wrong answers came first. The export's flat black wash gave the
        // bar no edge at all, so on a dark desktop it vanished into the panel.
        // Lifting it with white made it findable and GREY — a filled slab, and
        // the brightest thing on a panel whose job is to be calm (Marcello,
        // 2026-08-24: "too grayish and too prominent").
        //
        // A recessed well is the third answer and the ordinary one: the fill
        // goes slightly DARKER than what surrounds it and a hairline draws the
        // boundary. Depth is what marks a field, not brightness — text goes
        // into an input, and it should look like somewhere text can go.
        //
        // Not glass, deliberately. The material is right for inputs in the
        // NAVIGATION layer — that is what `.searchable()` gets on macOS 26,
        // placed by the system in a toolbar. This one sits inside a panel that
        // is itself glass, and glass cannot sample glass; the prescribed
        // remedy is a shared container for NEARBY elements, which has no
        // answer for a child nested in a glass parent.
        .background(
            RoundedRectangle(cornerRadius: PanelMetrics.barRadius, style: .continuous)
                .fill(Color.black.opacity(wellOpacity))
        )
        // Soft. It only has to separate the well from the panel, and the well
        // already sits a shade below it.
        .overlay(
            RoundedRectangle(cornerRadius: PanelMetrics.barRadius, style: .continuous)
                .strokeBorder(focused ? accent.opacity(0.7)
                                      : Color.dynamicOverlay(light: 0.07, dark: 0.08),
                              lineWidth: 1)
        )
        .animation(NotchAnimation.hintFade, value: focused)

        // Clicking anywhere in the box takes the caret, not just the ~17pt
        // strip of text view inside it.
        .contentShape(RoundedRectangle(cornerRadius: DSRadius.controlCorner, style: .continuous))
        .onTapGesture { store.draftWantsFocus = true }
        .onHover { hovering in
            withAnimation(NotchAnimation.hintFade) { hover = hovering }
        }
        // Detachment is whitespace, not a rule: the fill already says "this is
        // not one of the list items", so a divider would be two devices doing
        // one job. The whitespace itself now lives at the placement site, as
        // `PanelMetrics.fieldToTabsGap` — a row that carries half of its own
        // separation is a row no other space can line up with.
        .animation(NotchAnimation.hintFade, value: focused)
        .animation(NotchAnimation.hintFade, value: parsed?.display)
        .animation(NotchAnimation.contentHug, value: accent)
    }
}
