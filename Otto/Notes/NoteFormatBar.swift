import SwiftUI

// MARK: - NoteFormatBar — variant 5a, the fixed bar in the note's bottom row
//
// Chosen because the tools are always visible and always in the same place:
// nothing to discover, no selection needed first, and not one pixel of text
// width spent — the 52pt row already existed for the word count and the
// download. The accepted cost is that the row is dense and the tools are shown
// even when there is nothing to format.
//
// It is drawn in BOTH layouts. It was held back from the notch container on
// the grounds that the container has no 52pt row to spare — but it does: the
// note's bottom bar is already there, in both, carrying the word count and the
// download. Only the toolbar inside it was missing, so the container was
// paying the row's height and getting none of its use, and the same note
// offered different tools depending on which build you were in
// (Marcello, 2026-09-06). Parity costs nothing here because the silhouette
// does not grow.

struct NoteFormatBar: View {
    /// The B3 dock's version: the same tools in a 38-pt glass capsule in the
    /// bar at the panel's foot, each with an animated tooltip carrying its
    /// real shortcut (final flow 4.11).
    var docked = false

    @AppStorage("notchLayout") private var notchLayout: NotchLayout = .panels

    @ObservedObject private var editor = NoteEditorController.shared
    @State private var showsBlockMenu = false
    @State private var showsTextStyleMenu = false

    var body: some View {
        if docked { dockedBody } else { panelBody }
    }

    // MARK: Docked (final flow 4.11)

    private var dockedBody: some View {
        HStack(spacing: 2) {
            DockToolButton(label: L10n.t("dock.fmt.style"), shortcut: nil,
                           isActive: editor.activeBlock == .h1 || editor.activeBlock == .h2) {
                showsBlockMenu.toggle()
            } glyph: {
                Text(blockLabel).font(.system(size: 13, weight: .semibold))
            }
            .popover(isPresented: $showsBlockMenu, arrowEdge: .top) {
                BlockMenu { block in
                    editor.setBlock(block)
                    showsBlockMenu = false
                }
            }
            dockDivider
            DockToolButton(label: L10n.t("notes.fmt.bulleted"), shortcut: "\u{2318}\u{21E7}8",
                           isActive: editor.activeBlock == .bullet) {
                editor.toggleBlock(.bullet)
            } glyph: { DockIcon(.bullets, size: 17) }
            DockToolButton(label: L10n.t("notes.fmt.numbered"), shortcut: "\u{2318}\u{21E7}7",
                           isActive: editor.activeBlock == .numbered) {
                editor.toggleBlock(.numbered)
            } glyph: { DockIcon(.numbers, size: 17) }
            DockToolButton(label: L10n.t("notes.fmt.checklist"), shortcut: "\u{2318}\u{21E7}9",
                           isActive: editor.activeBlock.isChecklist) {
                editor.toggleBlock(.checklistOpen)
            } glyph: { DockIcon(.checklist, size: 17) }
            dockDivider
            // Bold, italic and underline under ONE "Text style" — its popover
            // lists the three (Marcello, 2026-10-18: room for Link without a
            // longer bar). Their shortcuts still work straight from the body.
            Group {
                DockToolButton(label: L10n.t("dock.fmt.textStyle"), shortcut: nil,
                               isActive: editor.bold || editor.italic || editor.underline) {
                    showsTextStyleMenu.toggle()
                } glyph: { DockIcon(.textStyle, size: 17) }
                .popover(isPresented: $showsTextStyleMenu, arrowEdge: .top) {
                    TextStyleMenu { showsTextStyleMenu = false }
                }
                DockToolButton(label: L10n.t("dock.fmt.link"), shortcut: "\u{2318}K",
                               isActive: editor.currentLink != nil) {
                    editor.beginLink()
                } glyph: { DockIcon(.link, size: 17) }
                .popover(isPresented: Binding(get: { editor.editingLink },
                                              set: { if !$0 { editor.cancelLink() } }),
                         arrowEdge: .top) {
                    LinkEditor(initial: editor.currentLink?.absoluteString ?? "")
                }
            }
            .disabled(editor.activeBlock == .code)
            dockDivider
            DockToolButton(label: L10n.t("notes.fmt.inlineCode"), shortcut: "\u{2318}\u{21E7}C",
                           isActive: editor.code) {
                editor.toggleInlineCode()
            } glyph: { DockIcon(.inlineCode, size: 17) }
                .disabled(editor.activeBlock == .code)
            DockToolButton(label: L10n.t("notes.fmt.quote"), shortcut: "\u{2318}'",
                           isActive: editor.activeBlock == .quote) {
                editor.toggleQuote()
            } glyph: { DockIcon(.quote, size: 17) }
            DockToolButton(label: L10n.t("notes.fmt.codeBlock"), shortcut: "\u{2318}\u{2325}\u{21E7}C",
                           isActive: editor.activeBlock == .code) {
                editor.toggleCodeBlock()
            } glyph: { DockIcon(.codeBlock, size: 17) }
        }
        .padding(.horizontal, 4)
        .frame(height: NotchContainerMetrics.roundButton)
        .notchGlass(in: Capsule(style: .circular))
        .opacity(editor.bodyFocused ? 1 : 0.45)
        .allowsHitTesting(editor.bodyFocused)
        .animation(Motion.hintFade, value: editor.bodyFocused)
    }

    private var dockDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 3)
    }

    // MARK: The panels / container bar

    private var panelBody: some View {
        HStack(spacing: 2) {
            // Group 1 — block type
            Button { showsBlockMenu.toggle() } label: {
                Text(blockLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .fixedSize()
            }
            .buttonStyle(FormatControlStyle(isActive: editor.activeBlock == .h1
                                                   || editor.activeBlock == .h2))
            .popover(isPresented: $showsBlockMenu, arrowEdge: .top) {
                BlockMenu { block in
                    editor.setBlock(block)
                    showsBlockMenu = false
                }
            }

            divider

            // Group 2 — lists
            Button { editor.toggleBlock(.bullet) } label: { BulletGlyph() }
                .buttonStyle(FormatControlStyle(isActive: editor.activeBlock == .bullet))
            Button { editor.toggleBlock(.numbered) } label: {
                // The system face: monospace is for code only.
                Text("1.").font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(FormatControlStyle(isActive: editor.activeBlock == .numbered))
            Button { editor.toggleBlock(.checklistOpen) } label: { ChecklistGlyph() }
                .buttonStyle(FormatControlStyle(isActive: editor.activeBlock.isChecklist))

            divider

            // Group 3 — inline style
            // A code block is code through and through: no typography in it.
            Group {
                Button { editor.toggleBold() } label: {
                    Text("B").font(.system(size: 12.5, weight: .bold))
                }
                .buttonStyle(FormatControlStyle(isActive: editor.bold))
                Button { editor.toggleItalic() } label: {
                    Text("I").font(.system(size: 12.5).italic())
                }
                .buttonStyle(FormatControlStyle(isActive: editor.italic))
                Button { editor.toggleUnderline() } label: {
                    Text("U").font(.system(size: 12.5)).underline()
                }
                .buttonStyle(FormatControlStyle(isActive: editor.underline))
            }
            .disabled(editor.activeBlock == .code)

            divider

            // Group 4 — code and quote: three separate verbs, as in Slack.
            Button { editor.toggleInlineCode() } label: {
                // Lucide glyphs for both code verbs (Marcello, 2026-10-12: the
                // boxed "</>" read badly): </> inline, { } for the block.
                OttoIcon("chevron.left.forwardslash.chevron.right", pointSize: 12)
            }
            .buttonStyle(FormatControlStyle(isActive: editor.code))
            .disabled(editor.activeBlock == .code)
            .panelTooltip(L10n.t("notes.fmt.inlineCode") + "  \u{2318}\u{21E7}C")
            .accessibilityLabel(L10n.t("notes.fmt.inlineCode"))
            Button { editor.toggleQuote() } label: { QuoteGlyph() }
                .buttonStyle(FormatControlStyle(isActive: editor.activeBlock == .quote))
                .panelTooltip(L10n.t("notes.fmt.quote") + "  \u{2318}'")
                .accessibilityLabel(L10n.t("notes.fmt.quote"))
            Button { editor.toggleCodeBlock() } label: { OttoIcon("curlybraces", pointSize: 12) }
                .buttonStyle(FormatControlStyle(isActive: editor.activeBlock == .code))
                .panelTooltip(L10n.t("notes.fmt.codeBlock") + "  \u{2318}\u{2325}\u{21E7}C")
                .accessibilityLabel(L10n.t("notes.fmt.codeBlock"))
            // No image button (Marcello, 2026-10-12: picking from the vault
            // did not work). Images come in by paste and by drop.
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        // In the floating panel's corner it is concentric with the window
        // (24 − 16 = 8); the container keeps its capsule.
        .floatingGlass(in: RoundedRectangle(
            cornerRadius: notchLayout == .container ? 20 : SpaceChrome.cornerRadius, style: .continuous))
        // The whole bar steps back when the body has no caret: the note is
        // being read, not edited, and tools that cannot act should not look
        // like they can.
        .opacity(editor.bodyFocused ? 1 : 0.45)
        .allowsHitTesting(editor.bodyFocused)
        .animation(Motion.hintFade, value: editor.bodyFocused)
    }

    private var blockLabel: String {
        switch editor.activeBlock {
        case .h1: return "H1"
        case .h2: return "H2"
        default:  return "Aa"
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(DSColor.hairlineOnPanel)
            .frame(width: 1, height: 16)
            .padding(.horizontal, 3)
    }
}

/// One tool in the docked bar: a circular hover fill (white 9 %) and its
/// tooltip, which reads the same hover.
private struct DockToolButton<Glyph: View>: View {
    let label: String
    let shortcut: String?
    let isActive: Bool
    let action: () -> Void
    @ViewBuilder let glyph: Glyph
    @State private var hover = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            glyph
                .foregroundStyle(isActive ? DSDock.notesLight : DSDock.text)
                .frame(width: 32, height: 32)
                .background(Circle().fill(isActive ? DSDock.notes.opacity(0.18)
                                          : (hover ? Color.white.opacity(0.09) : .clear)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { hover = $0 }
        .animation(Motion.hoverFade, value: hover)
        .barTip("fmt." + label, isEnabled ? BarTip(label: label, shortcut: shortcut) : nil)
        .accessibilityLabel(label)
    }
}

/// Rest, hover, active, pressed — one style so the controls cannot drift
/// apart. A 28×28 hit area under glyphs that are much smaller, so the row is
/// dense to look at and not to use.
///
/// A compact ROUNDED RECTANGLE, concentric with the bar it sits in: the bar
/// is an 8-pt rounded rectangle with 4 of padding, so each control is 8 − 4
/// = 4, rounded to 5 for the eye (2026-09-25 spec, replacing the circles that
/// matched the old capsule bar). Rest, hover, selected, pressed and disabled
/// all read differently; the 28×28 frame is exact so no glyph stretches it.
private struct FormatControlStyle: ButtonStyle {
    let isActive: Bool
    @State private var hover = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        return configuration.label
            .foregroundStyle(isActive ? PanelMetrics.accent : DSColor.textPrimary)
            .frame(width: 28, height: 28)
            .background(
                shape.fill(configuration.isPressed ? PanelMetrics.accent.opacity(0.28)
                           : (isActive ? PanelMetrics.accent.opacity(0.18)
                              : (hover ? DSColor.fieldBackground : Color.clear)))
            )
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.35)
            .onHover { hover = $0 }
            .animation(Motion.hoverFade, value: hover)
            .animation(Motion.hoverFade, value: isActive)
    }
}

// MARK: Glyphs — CSS shapes in the design, Shapes here. No icon font, no SVG.

private struct BulletGlyph: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2.5) {
            ForEach(0..<3, id: \.self) { row in
                Capsule()
                    .frame(width: row == 2 ? 8 : 13, height: 1.5)
            }
        }
        .frame(width: 13)
    }
}

/// A leading rule and two lines: the quote's own shape, not a quote mark.
private struct QuoteGlyph: View {
    var body: some View {
        HStack(spacing: 3) {
            Capsule().frame(width: 2, height: 13)
            VStack(alignment: .leading, spacing: 3.5) {
                Capsule().frame(width: 9, height: 1.5)
                Capsule().frame(width: 6, height: 1.5)
            }
        }
        .frame(width: 14)
    }
}

private struct ChecklistGlyph: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .strokeBorder(lineWidth: 1.5)
            .frame(width: 13, height: 13)
    }
}

// MARK: The Text style popover — bold, italic, underline

private struct TextStyleMenu: View {
    let done: () -> Void
    @ObservedObject private var editor = NoteEditorController.shared
    @State private var hovered: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            row(0, glyph: Text("B").font(.system(size: 14, weight: .bold)),
                label: L10n.t("dock.fmt.bold"), shortcut: "\u{2318}B", isOn: editor.bold) { editor.toggleBold() }
            row(1, glyph: Text("I").font(.system(size: 14).italic()),
                label: L10n.t("dock.fmt.italic"), shortcut: "\u{2318}I", isOn: editor.italic) { editor.toggleItalic() }
            row(2, glyph: Text("U").font(.system(size: 14)).underline(),
                label: L10n.t("dock.fmt.underline"), shortcut: "\u{2318}U", isOn: editor.underline) { editor.toggleUnderline() }
        }
        .padding(OttoMenuStyle.padding - 4)
        .frame(width: 220)
    }

    private func row(_ index: Int, glyph: some View, label: String, shortcut: String, isOn: Bool,
                     action: @escaping () -> Void) -> some View {
        Button {
            action()
            done()
        } label: {
            HStack(spacing: 10) {
                glyph
                    .foregroundStyle(isOn ? DSDock.notes : DSColor.textPrimaryBright)
                    .frame(width: 22, alignment: .leading)
                Text(label)
                    .font(.system(size: OttoMenuStyle.rowFont, weight: isOn ? .medium : .regular))
                    .foregroundStyle(isOn ? DSColor.textPrimaryBright : DSColor.textPrimary)
                Spacer(minLength: 8)
                Text(shortcut)
                    .font(.system(size: OttoMenuStyle.shortcutFont))
                    .foregroundStyle(DSDock.text3)
            }
            .padding(.horizontal, OttoMenuStyle.rowPaddingH)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: OttoMenuStyle.rowRadius, style: .continuous)
                .fill(OttoMenuStyle.rowFill(highlighted: hovered == index, current: isOn)))
            .contentShape(RoundedRectangle(cornerRadius: OttoMenuStyle.rowRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? index : (hovered == index ? nil : hovered) }
    }
}

// MARK: The Link popover — one field

private struct LinkEditor: View {
    let initial: String
    @State private var text = ""
    @FocusState private var focused: Bool
    @ObservedObject private var editor = NoteEditorController.shared

    var body: some View {
        HStack(spacing: 8) {
            DockIcon(.link, size: 15)
                .foregroundStyle(DSDock.notes)
            TextField(L10n.t("dock.linkPlaceholder"), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit { editor.commitLink(text) }
                .onExitCommand { editor.cancelLink() }
            if !initial.isEmpty {
                // Remove: the same verb as committing an empty field.
                Button(L10n.t("dock.linkRemove")) { editor.commitLink("") }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: "#FF6961"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 300)
        .onAppear {
            text = initial
            DispatchQueue.main.async { focused = true }
        }
    }
}

// MARK: The Aa popover — every block type in one place

private struct BlockMenu: View {
    let apply: (NoteBlock) -> Void
    @ObservedObject private var editor = NoteEditorController.shared
    @State private var hovered: NoteBlock?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            row(.h1, glyph: "H1", glyphSize: 14, label: L10n.t("notes.fmt.title"))
            row(.h2, glyph: "H2", glyphSize: 13, label: L10n.t("notes.fmt.subtitle"))
            row(.body, glyph: "Aa", glyphSize: 12.5, label: L10n.t("notes.fmt.body"))
            Divider().padding(.horizontal, 8).padding(.vertical, 5)
            row(.bullet, glyph: "\u{2022}", glyphSize: 13, label: L10n.t("notes.fmt.bulleted"))
            row(.numbered, glyph: "1.", glyphSize: 12, label: L10n.t("notes.fmt.numbered"))
            row(.checklistOpen, glyph: "\u{2610}", glyphSize: 13, label: L10n.t("notes.fmt.checklist"))
            Divider().padding(.horizontal, 8).padding(.vertical, 5)
            row(.quote, glyph: "\u{201C}", glyphSize: 15, label: L10n.t("notes.fmt.quote"))
            row(.code, glyph: "{ }", glyphSize: 12, label: L10n.t("notes.fmt.codeBlock"))
        }
        .padding(OttoMenuStyle.padding - 4)
        .frame(width: 220)
    }

    private func row(_ block: NoteBlock, glyph: String, glyphSize: CGFloat, label: String) -> some View {
        let isCurrent = editor.activeBlock == block
            || (block == .checklistOpen && editor.activeBlock.isChecklist)
        return Button { apply(block) } label: {
            HStack(spacing: 10) {
                Text(glyph)
                    .font(.system(size: glyphSize, weight: block == .body ? .regular : .semibold))
                    .foregroundStyle(isCurrent ? DSDock.notes : DSColor.textPrimaryBright)
                    .frame(width: 22, alignment: .leading)
                Text(label)
                    .font(.system(size: OttoMenuStyle.rowFont, weight: isCurrent ? .medium : .regular))
                    .foregroundStyle(isCurrent ? DSColor.textPrimaryBright : DSColor.textPrimary)
                Spacer(minLength: 0)
            }
            // The panel menus' row: same radius, type and cyan treatment,
            // hover included (2026-09-26).
            .padding(.horizontal, OttoMenuStyle.rowPaddingH)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: OttoMenuStyle.rowRadius, style: .continuous)
                    .fill(OttoMenuStyle.rowFill(highlighted: hovered == block, current: isCurrent))
            )
            .contentShape(RoundedRectangle(cornerRadius: OttoMenuStyle.rowRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? block : (hovered == block ? nil : hovered) }
    }
}
