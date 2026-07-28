import SwiftUI
import AppKit

// MARK: - AnnotationToolbar — Unified toolbar for both inline capture and editor
//
// Single horizontal pill, .ultraThinMaterial, 4 groups separated by dividers.
// Used identically in AreaSelector (inline capture) and EditorView (gallery editor).

struct AnnotationToolbar: View {
    @Binding var activeTool: AnnotationToolType
    @Binding var activeColor: NSColor
    @Binding var brushSize: CGFloat   // range 2...20
    var canUndo: Bool
    var canRedo: Bool
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onOCR: (() -> Void)? = nil
    // Optional action buttons — when provided, replace the separate CaptureActionBar.
    var onCancel: (() -> Void)? = nil
    var onCopy: (() -> Void)? = nil
    var onSave: (() -> Void)? = nil

    // Output option: round the corners of the final capture. Persisted so
    // the choice sticks between captures; read by CaptureManager on export.
    @AppStorage("captureRoundedCorners") private var roundedCorners = false

    static let paletteColors: [NSColor] = [
        NSColor(red: 1.0,   green: 0.231, blue: 0.188, alpha: 1),  // #FF3B30
        NSColor(red: 1.0,   green: 0.584, blue: 0.0,   alpha: 1),  // #FF9500
        NSColor(red: 1.0,   green: 0.8,   blue: 0.0,   alpha: 1),  // #FFCC00
        NSColor(red: 0.204, green: 0.78,  blue: 0.349, alpha: 1),  // #34C759
        NSColor(red: 0.0,   green: 0.478, blue: 1.0,   alpha: 1),  // #007AFF
        .white,                                                       // #FFFFFF
    ]

    var body: some View {
        HStack(spacing: 10) {
            // Cancel (optional, leftmost)
            if let onCancel {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(red: 1, green: 0.23, blue: 0.19))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                toolbarDivider
            }

            // GROUP 1: Tools
            HStack(spacing: 2) {
                ToolbarToolButton(symbol: "pencil.tip",     tool: .pen,       active: $activeTool)
                ToolbarToolButton(symbol: nil, letter: "T",  tool: .text,      active: $activeTool)
                ToolbarToolButton(symbol: "arrow.up.right",  tool: .arrow,     active: $activeTool)
                ToolbarToolButton(symbol: "rectangle",       tool: .rectangle, active: $activeTool)

                if let onOCR {
                    Button(action: onOCR) {
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .help("Extract text (X)")
                }

                // Rounded-corner output toggle — square icon ↔ rounded icon
                Button {
                    roundedCorners.toggle()
                } label: {
                    Image(systemName: roundedCorners ? "app.fill" : "square")
                        .font(.system(size: 14))
                        .foregroundStyle(roundedCorners ? Color.accentColor : .secondary)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(roundedCorners ? Color.accentColor.opacity(0.15) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .help(roundedCorners ? "Rounded corners: on" : "Rounded corners: off")
            }

            toolbarDivider

            // GROUP 2: Color (single swatch + popover)
            ToolbarColorPicker(selected: $activeColor, palette: Self.paletteColors)

            // GROUP 3: Brush size
            ToolbarBrushSlider(value: $brushSize, range: 2...20)
                .frame(width: 72)

            toolbarDivider

            // GROUP 4: Undo / Redo
            HStack(spacing: 4) {
                ToolbarUndoRedoButton(symbol: "arrow.uturn.backward", enabled: canUndo, action: onUndo)
                ToolbarUndoRedoButton(symbol: "arrow.uturn.forward",  enabled: canRedo, action: onRedo)
            }

            // GROUP 5: Actions (optional)
            if onCopy != nil || onSave != nil {
                toolbarDivider

                if let onSave {
                    Button(action: onSave) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 11, weight: .medium))
                            Text("Save")
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                                .fixedSize()
                            Text("\u{2318}S")
                                .font(.system(size: 10, weight: .regular).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.5))
                                .fixedSize()
                        }
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let onCopy {
                    Button(action: onCopy) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11, weight: .medium))
                            Text("Copy")
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                                .fixedSize()
                            Text("\u{2318}C")
                                .font(.system(size: 10, weight: .regular).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.6))
                                .fixedSize()
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.accentColor)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
        // Force a dark appearance so the toolbar keeps its familiar look (and
        // readable white/secondary icons) even when it floats over a bright
        // screenshot in light mode.
        .environment(\.colorScheme, .dark)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(width: 1, height: 20)
    }
}

// MARK: - ToolbarColorPicker — single swatch, expands to palette on click

private struct ToolbarColorPicker: View {
    @Binding var selected: NSColor
    let palette: [NSColor]
    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            Circle()
                .fill(Color(nsColor: selected))
                .frame(width: 20, height: 20)
                .overlay(
                    Circle().stroke(Color.white.opacity(0.4), lineWidth: 1)
                )
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .padding(-3)
                        .opacity(isOpen ? 1 : 0)
                )
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .top) {
            HStack(spacing: 10) {
                ForEach(0..<palette.count, id: \.self) { idx in
                    Circle()
                        .fill(Color(nsColor: palette[idx]))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                                .padding(-3)
                                .opacity(selected.isClose(to: palette[idx]) ? 1 : 0)
                        )
                        .onTapGesture {
                            selected = palette[idx]
                            isOpen = false
                        }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - ToolbarToolButton

private struct ToolbarToolButton: View {
    let symbol: String?
    var letter: String? = nil
    let tool: AnnotationToolType
    @Binding var active: AnnotationToolType
    @State private var isHovered = false

    private var isActive: Bool { active == tool }

    var body: some View {
        Button { active = tool } label: {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: isActive ? .semibold : .regular))
                } else if let letter {
                    Text(letter)
                        .font(.system(size: 15, weight: isActive ? .bold : .semibold, design: .serif))
                }
            }
            .foregroundStyle(isActive ? .primary : .secondary)
            .frame(width: 30, height: 30)
            .background(
                Circle().fill(Color.white.opacity(isActive ? 0.15 : 0))
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.06 : 1.0)
        .animation(.spring(duration: 0.18, bounce: 0.4), value: isHovered)
        .onHover { isHovered = $0 }
        .help(shortcutHint)
    }

    private var shortcutHint: String {
        switch tool {
        case .pen:       return "Penna (P)"
        case .text:      return "Testo (T)"
        case .arrow:     return "Freccia (A)"
        case .rectangle: return "Rettangolo (R)"
        case .blur:      return "Blur (B)"
        }
    }
}

// MARK: - ToolbarColorSwatch

private struct ToolbarColorSwatch: View {
    let color: Color
    let isActive: Bool

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 22, height: 22)
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .padding(-4)
                    .opacity(isActive ? 1.0 : 0)
            )
            .scaleEffect(isActive ? 1.12 : 1.0)
            .animation(.spring(duration: 0.18, bounce: 0.35), value: isActive)
            .frame(width: 30, height: 30)
            .contentShape(Circle())
    }
}

// MARK: - ToolbarBrushSlider

private struct ToolbarBrushSlider: View {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>

    var body: some View {
        GeometryReader { geo in
            // Fill the GeometryReader so the ZStack's default center vertical
            // alignment actually centers the track/thumb — otherwise the ZStack
            // sits top-leading and the thumb visibly sits above the other icons.
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: 3)
                Circle()
                    .fill(Color.white)
                    .frame(width: 13, height: 13)
                    .shadow(radius: 1.5)
                    .offset(x: thumbX(in: geo.size.width))
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    let norm = max(0, min(1, g.location.x / geo.size.width))
                    value = range.lowerBound + norm * (range.upperBound - range.lowerBound)
                }
            )
        }
        .frame(height: 28)
    }

    private func thumbX(in width: CGFloat) -> CGFloat {
        let norm = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return norm * (width - 13)
    }
}

// MARK: - ToolbarUndoRedoButton

private struct ToolbarUndoRedoButton: View {
    let symbol: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1.0 : 0.3)
        .disabled(!enabled)
    }
}

// MARK: - NSColor comparison helper

extension NSColor {
    func isClose(to other: NSColor) -> Bool {
        guard let c1 = self.usingColorSpace(.sRGB),
              let c2 = other.usingColorSpace(.sRGB) else { return false }
        return abs(c1.redComponent - c2.redComponent) < 0.05 &&
               abs(c1.greenComponent - c2.greenComponent) < 0.05 &&
               abs(c1.blueComponent - c2.blueComponent) < 0.05
    }
}
