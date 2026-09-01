import SwiftUI

// MARK: - CaptureActionBar — Action pill below selection area
//
// [X red]  [Salva outlined]  [Copia ⌘C blue filled]
// Appears below selection rect (or above if near screen bottom)

struct CaptureActionBar: View {
    let onCancel: () -> Void
    let onSave: () -> Void
    let onCopy: () -> Void

    @State private var appeared = false

    var body: some View {
        HStack(spacing: 6) {
            // Cancel — red X, no label
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 1, green: 0.23, blue: 0.19))
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)

            Divider()
                .frame(height: 20)
                .opacity(0.3)

            // Save — outlined secondary
            Button(action: onSave) {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 12, weight: .medium))
                    Text("Save")
                        .font(.system(size: 12, weight: .medium))
                    Text("\u{2318}S")
                        .font(.system(size: 10, weight: .regular).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            // Copy — primary blue filled
            Button(action: onCopy) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .medium))
                    Text("Copy")
                        .font(.system(size: 12, weight: .medium))
                    Text("\u{2318}C")
                        .font(.system(size: 10, weight: .regular).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // Floating chrome over a capture — real glass on 26.
        .floatingGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 4)
        // Same rule as the annotation toolbar beside it: this bar floats over
        // a screenshot that can be any brightness, so it keeps one look and
        // supplies its own dark ground rather than following the system.
        .darkGroundSurface()
        .scaleEffect(appeared ? 1.0 : 0.7)
        .opacity(appeared ? 1.0 : 0.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: appeared)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                appeared = true
            }
        }
    }
}
