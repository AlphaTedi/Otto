import SwiftUI

// MARK: - Checkbox
//
// Every tick-box in the notch is this one view (there were five, 2026-11-08).
// A checkbox is a SELECTION control, so it stays a rounded square, never a
// circle or a capsule (DSShape).
//
//   .row      18 pt, radius 6, 2-pt stroke — a to-do. In the container the
//             check is a little larger and pure black (spec §5.3).
//   .step     10 pt, radius 3, 1-pt stroke — a checklist step in the panels.
//   .archive  16 pt, radius 5, 1.2-pt stroke — a completion in the log.
//
// `tint` is the section's own colour: the box is never a generic grey.
// `dashed` draws an empty SLOT (the step draft row), not a box.

struct DSCheckbox: View {
    enum Size { case row, step, archive }

    let size: Size
    let isChecked: Bool
    let tint: Color
    /// The stroke while unchecked, when it differs from `tint`.
    var uncheckedStroke: Color? = nil
    /// The fill once checked, when it differs from `tint`.
    var checkedFill: Color? = nil
    /// The stroke once checked. Nil = the fill.
    var checkedStroke: Color? = nil
    var checkColor: Color? = nil
    var dashed = false

    @Environment(\.ottoSurface) private var surface

    private var side: CGFloat {
        switch size {
        case .row: return DSSize.box
        case .step: return DSSize.miniBox
        case .archive: return 16
        }
    }
    private var radius: CGFloat {
        switch size {
        case .row: return DSRadius.keycap
        case .step: return DSRadius.checkbox
        case .archive: return 5
        }
    }
    private var lineWidth: CGFloat {
        switch size {
        case .row: return 2
        case .step: return 1
        case .archive: return 1.2
        }
    }
    private var checkSize: CGFloat {
        switch size {
        case .row: return surface == .container ? 11 : 10
        case .step: return 6
        case .archive: return 8
        }
    }
    private var check: Color {
        if let checkColor { return checkColor }
        return surface == .container ? .black : DSColor.onAccentFill.opacity(0.85)
    }

    var body: some View {
        let shape = DSShape.squircle(radius)
        ZStack {
            if dashed {
                shape.strokeBorder(uncheckedStroke ?? tint.opacity(0.5),
                                   style: StrokeStyle(lineWidth: lineWidth, dash: [2, 2]))
            } else {
                shape.fill(isChecked ? (checkedFill ?? tint) : .clear)
                shape.strokeBorder(isChecked ? (checkedStroke ?? checkedFill ?? tint) : (uncheckedStroke ?? tint),
                                   lineWidth: lineWidth)
                if isChecked {
                    OttoIcon("checkmark", pointSize: checkSize)
                        .foregroundStyle(check)
                        .transition(DSTransition.pop())
                }
            }
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        .animation(Motion.complete, value: isChecked)
    }
}
