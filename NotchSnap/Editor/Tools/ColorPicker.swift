import SwiftUI
import AppKit

// MARK: - NotchSnap Color Picker (palette + native picker)

struct NotchSnapColorPicker: View {
    @Binding var selectedColor: NSColor
    @State private var showNativePicker = false

    private let presetColors: [(String, NSColor)] = [
        ("Rosso", NSColor(red: 1, green: 0.23, blue: 0.19, alpha: 1)),
        ("Blu", NSColor(red: 0, green: 0.48, blue: 1, alpha: 1)),
        ("Verde", NSColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1)),
        ("Giallo", NSColor(red: 1, green: 0.8, blue: 0, alpha: 1)),
        ("Arancione", NSColor(red: 1, green: 0.58, blue: 0, alpha: 1)),
        ("Bianco", .white),
        ("Nero", .black),
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<presetColors.count, id: \.self) { index in
                let (name, color) = presetColors[index]
                Button {
                    selectedColor = color
                } label: {
                    Circle()
                        .fill(Color(nsColor: color))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .stroke(DSColor.selectionRing, lineWidth: selectedColor == color ? 2.5 : 0)
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.15), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .help(name)
            }

            // Custom color "+" button
            ColorPicker("", selection: Binding(
                get: { Color(nsColor: selectedColor) },
                set: { selectedColor = NSColor($0) }
            ))
            .labelsHidden()
            .frame(width: 22, height: 22)
        }
    }
}
