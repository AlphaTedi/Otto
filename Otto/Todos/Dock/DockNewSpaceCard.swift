import SwiftUI

// MARK: - New space: the dock grows into a card (final flow §4.7, screens 07–09)
//
// No separate screen. The "+" (or ⇧⌘N) morphs the dock capsule into a small
// glass card — DockBottomBar runs the morph with a matched geometry between
// the two — holding a name field and the seven swatches. The next unused
// colour is preselected; ⇥ / ⇧⇥ walk the colours (DockState.handleKey);
// ⏎ or ✓ creates, Esc cancels. Creating folds the card back into the dock,
// pops the new space in as the active pill and puts the caret in its first
// row.

struct DockNewSpaceCard: View {
    @ObservedObject private var dock = DockState.shared
    @FocusState private var nameFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entered = false

    static let size = CGSize(width: 300, height: 104)
    static let radius: CGFloat = 24

    private var tint: DockTint { DockTint(dock.newSpaceTint) }
    private var hasName: Bool { !dock.newSpaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Row 1: name · ✓, in a 32-pt well. No dot and regular weight
            // (Marcello, 2026-10-17: simpler, and the bold read too heavy).
            HStack(spacing: 10) {
                ZStack(alignment: .leading) {
                    if dock.newSpaceName.isEmpty {
                        Text(L10n.t("dock.nameSpace"))
                            .font(.system(size: 13.5))
                            .foregroundStyle(DSDock.placeholder)
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $dock.newSpaceName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13.5))
                        .foregroundStyle(DSDock.textStrong)
                        .tint(tint.base)
                        .focused($nameFocused)
                        .onSubmit { dock.createSpace() }
                }
                Button { dock.createSpace() } label: {
                    DockIcon(.check, size: 14)
                        .foregroundStyle(hasName ? Color.black : DSDock.text3)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(hasName ? tint.base : Color.white.opacity(0.10)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!hasName)
                .accessibilityLabel(L10n.t("todo.newCollection"))
            }
            .padding(.leading, 14)
            .padding(.trailing, 3)
            .frame(height: 32)
            .background(Capsule(style: .circular).fill(Color.black.opacity(0.35)))
            .opacity(entered ? 1 : 0)
            .offset(y: entered || reduceMotion ? 0 : 6)

            // Row 2: the nine swatches across the whole card — no "esc"
            // hint; Esc and a click outside still close it.
            HStack(spacing: 0) {
                ForEach(Array(SpaceTint.palette.enumerated()), id: \.element.key) { index, swatch in
                    if index > 0 { Spacer(minLength: 0) }
                    let color = DockTint(swatch).base
                    let selected = swatch.key == dock.newSpaceTint.key
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { dock.newSpaceTint = swatch }
                    } label: {
                        Circle()
                            .fill(color)
                            .frame(width: 16, height: 16)
                            .padding(3)
                            .overlay(Circle().strokeBorder(selected ? color : .clear, lineWidth: 1.5))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .opacity(entered ? 1 : 0)
                    .scaleEffect(entered || reduceMotion ? 1 : 0.6)
                    .offset(y: entered || reduceMotion ? 0 : 6)
                    .animation(reduceMotion ? .easeOut(duration: 0.15)
                               : .timingCurve(0.22, 1, 0.36, 1, duration: 0.36)
                                    .delay(0.21 + 0.022 * Double(index)), value: entered)
                    .accessibilityLabel(swatch.key)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 3)
        }
        .padding(10)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        .notchGlass(in: RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("todo.newCollection"))
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15)
                          : .timingCurve(0.22, 1, 0.36, 1, duration: 0.32).delay(0.12)) { entered = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { nameFocused = true }
        }
    }
}
