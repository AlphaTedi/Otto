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
    @ObservedObject private var editor = NoteEditorController.shared
    @State private var showsBlockMenu = false

    var body: some View {
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
                Text("1.").font(.system(size: 11, design: .monospaced))
            }
            .buttonStyle(FormatControlStyle(isActive: editor.activeBlock == .numbered))
            Button { editor.toggleBlock(.checklistOpen) } label: { ChecklistGlyph() }
                .buttonStyle(FormatControlStyle(isActive: editor.activeBlock.isChecklist))

            divider

            // Group 3 — inline style
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
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Capsule().fill(DSColor.fieldBackground))
        .overlay(Capsule().strokeBorder(DSColor.panelBorder, lineWidth: 0.5))
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

/// Rest, hover, active, pressed — one style so the nine controls cannot drift
/// apart. A 28×28 hit area under glyphs that are much smaller, so the row is
/// dense to look at and not to use.
///
/// CIRCLES, not rounded squares. At 28×28 a corner radius of 8 is a square
/// with the corners taken off, and nine of them sitting inside a capsule read
/// as badges pasted onto a pill rather than as controls belonging to it
/// (Marcello, 2026-09-06, on the lit underline button). A circle is concentric
/// with the capsule it lives in: same centre, same curvature at the ends, one
/// object.
///
/// The frame is EXACT rather than a minimum, because a circle behind a frame
/// that grows to its label is an ellipse — the wide glyphs ("1.", "H1") were
/// exactly the ones that would have stretched.
private struct FormatControlStyle: ButtonStyle {
    let isActive: Bool
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isActive ? LabMetrics.accent : DSColor.textPrimary)
            .frame(width: 28, height: 28)
            .background(
                Circle()
                    .fill(configuration.isPressed ? LabMetrics.accent.opacity(0.28)
                          : (isActive ? LabMetrics.accent.opacity(0.18)
                             : (hover ? DSColor.fieldBackground : Color.clear)))
            )
            .contentShape(Circle())
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

private struct ChecklistGlyph: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .strokeBorder(lineWidth: 1.5)
            .frame(width: 13, height: 13)
    }
}

// MARK: The Aa popover — every block type in one place

private struct BlockMenu: View {
    let apply: (NoteBlock) -> Void
    @ObservedObject private var editor = NoteEditorController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            row(.h1, glyph: "H1", glyphSize: 14, label: L10n.t("notes.fmt.title"))
            row(.h2, glyph: "H2", glyphSize: 13, label: L10n.t("notes.fmt.subtitle"))
            row(.body, glyph: "Aa", glyphSize: 12.5, label: L10n.t("notes.fmt.body"))
            Divider().padding(.horizontal, 8).padding(.vertical, 5)
            row(.bullet, glyph: "\u{2022}", glyphSize: 13, label: L10n.t("notes.fmt.bulleted"))
            row(.numbered, glyph: "1.", glyphSize: 12, label: L10n.t("notes.fmt.numbered"))
            row(.checklistOpen, glyph: "\u{2610}", glyphSize: 13, label: L10n.t("notes.fmt.checklist"))
        }
        .padding(6)
        .frame(width: 214)
    }

    private func row(_ block: NoteBlock, glyph: String, glyphSize: CGFloat, label: String) -> some View {
        let isCurrent = editor.activeBlock == block
            || (block == .checklistOpen && editor.activeBlock.isChecklist)
        return Button { apply(block) } label: {
            HStack(spacing: 10) {
                Text(glyph)
                    .font(.system(size: glyphSize, weight: block == .body ? .regular : .semibold))
                    .foregroundStyle(isCurrent ? LabMetrics.accent : DSColor.textPrimaryBright)
                    .frame(width: 22, alignment: .leading)
                Text(label)
                    .font(.system(size: 12.5))
                    .foregroundStyle(isCurrent ? DSColor.textPrimaryBright : DSColor.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isCurrent ? LabMetrics.accent.opacity(0.14) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
