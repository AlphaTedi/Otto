import AppKit
import SwiftUI

// MARK: - Space chrome — U5's ambient colour, capture header and gear
//
// Everything in here is FURNITURE around the list: the light behind it, the
// field above it, the rim and the settings button. Rows, checkboxes and steps
// are not touched by any of it (U5 §8) — colour is ambient, never on content.

// MARK: Ink

/// The reference is drawn on the dark panel, in white at fixed strengths. The
/// floating panel follows the system appearance, so the same strengths are
/// taken from black in light mode — otherwise the field would go invisible.
enum SpaceInk {
    static func a(_ alpha: Double) -> Color { Color.dynamicOverlay(light: alpha, dark: alpha) }
}

// MARK: Tint crossfade

/// The three tint colours at one point of a switch.
struct MixedTint {
    let base: SpaceTint.RGB
    let light: SpaceTint.RGB
    let neighbour: SpaceTint.RGB
}

/// Crossfades a tint over 350 ms, interpolating in OKLCH (U5 §6.2).
///
/// A plain `Color` animation would blend in sRGB, and green → blue through
/// sRGB goes through a muddy grey-teal. The progress is what animates; the
/// colours are computed from it on every frame.
struct TintTransition<Content: View>: View {
    let target: SpaceTint
    @ViewBuilder let content: (MixedTint) -> Content

    @State private var from: SpaceTint?
    @State private var to: SpaceTint?
    @State private var progress: Double = 1

    var body: some View {
        TintMixer(from: from ?? target, to: to ?? target, progress: progress, content: content)
            .onChange(of: target) { next in
                let start = to ?? next
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) {
                    from = start
                    to = next
                    progress = 0
                }
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.35)) { progress = 1 }
                }
            }
    }
}

private struct TintMixer<Content: View>: View, @preconcurrency Animatable {
    let from: SpaceTint
    let to: SpaceTint
    var progress: Double
    let content: (MixedTint) -> Content

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        content(MixedTint(base: SpaceTint.mix(from.base, to.base, progress),
                          light: SpaceTint.mix(from.light, to.light, progress),
                          neighbour: SpaceTint.mix(from.neighbour, to.neighbour, progress)))
    }
}

// MARK: Ambient glow (U5 §6)

/// Where the selected space pill's centre is, in the panel's coordinates — the
/// glow rises from under it.
struct ActivePillXKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}

enum SpaceChrome {
    /// The coordinate space the glow and the pills agree on.
    static let panelSpace = "otto.panel"
}

extension View {
    /// Reports this pill's centre as the glow's anchor, when it is the
    /// selected one.
    func reportsActivePill(_ active: Bool) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ActivePillXKey.self,
                    value: active ? proxy.frame(in: .named(SpaceChrome.panelSpace)).midX : nil)
            }
        )
    }
}

/// Two soft radial lights behind the content: A in the space's base colour
/// under the selected pill, B in its neighbour hue drifting at the right.
struct SpaceAmbientGlow: View {
    let tint: SpaceTint
    /// The selected pill's centre; nil falls back to the middle.
    let pillX: CGFloat?
    /// The notch container keeps its top black and puts B lower (U5 §2, §6.1).
    let isContainer: Bool

    @ObservedObject private var controller = NotchController.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var driftA = false
    @State private var driftB = false

    /// Drift only while the panel is actually open (U5 §6.2, performance).
    private var drifting: Bool { controller.state == .expanded && !reduceMotion }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            // The reference draws both layers in a box 40 pt larger than the
            // panel on every side, and places them by percentage of THAT box.
            let boxW = w + 80, boxH = h + 80
            let alphaScale = (colorScheme == .dark || isContainer) ? 1.0 : 0.6
            TintTransition(target: tint) { mixed in
                ZStack(alignment: .topLeading) {
                    GlowEllipse(color: mixed.base, rx: 400, ry: 250, peak: 0.36 * alphaScale)
                        .scaleEffect(driftA ? 1.06 : 1)
                        .offset(x: driftA ? 18 : 0, y: driftA ? -10 : 0)
                        .position(x: pillX ?? w / 2, y: -40 + boxH * 0.96)
                        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.9),
                                   value: pillX)
                    GlowEllipse(color: mixed.neighbour, rx: 320, ry: 230, peak: 0.18 * alphaScale)
                        .offset(x: driftB ? -22 : 0, y: driftB ? 8 : 0)
                        .position(x: -40 + boxW * 0.88, y: -40 + boxH * (isContainer ? 0.95 : 0.70))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { setDrift(drifting) }
        .onChange(of: drifting) { setDrift($0) }
    }

    private func setDrift(_ on: Bool) {
        if on {
            withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) { driftA = true }
            withAnimation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true)) { driftB = true }
        } else {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { driftA = false; driftB = false }
        }
    }
}

/// One elliptical light, `peak × (1 − t)^2.2` over 11 stops — no visible edge.
private struct GlowEllipse: View {
    let color: SpaceTint.RGB
    let rx: CGFloat
    let ry: CGFloat
    let peak: Double

    var body: some View {
        Canvas { context, size in
            let stops = (0...10).map { i -> Gradient.Stop in
                let t = Double(i) / 10
                return .init(color: color.color.opacity(peak * pow(1 - t, 2.2)), location: t)
            }
            var layer = context
            layer.translateBy(x: size.width / 2, y: size.height / 2)
            layer.scaleBy(x: 1, y: ry / rx)
            layer.fill(Path(ellipseIn: CGRect(x: -rx, y: -rx, width: rx * 2, height: rx * 2)),
                       with: .radialGradient(Gradient(stops: stops), center: .zero,
                                             startRadius: 0, endRadius: rx))
        }
        .frame(width: rx * 2, height: ry * 2)
    }
}

/// The floating panel's 1-pt rim in the active space's colour at 22%,
/// crossfading with the glow.
struct SpaceRim<S: InsettableShape>: View {
    let tint: SpaceTint
    let shape: S

    var body: some View {
        TintTransition(target: tint) { mixed in
            shape.strokeBorder(mixed.base.color.opacity(0.22), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

// MARK: Capture header (U5 §4) — floating panels only

/// The borderless, Raycast-style capture field: a space dot, the text, and a
/// trailing hint that is "Switch space ⇥" while empty and "Save to <Space> ↵"
/// once something is typed. 60 pt tall whatever state it is in, with a
/// hairline under it across the whole panel.
///
/// Shared by the to-do field and the Notes composer; each brings its own text
/// view, since one is an NSTextView with inline date colouring and the other
/// a multi-line TextField.
struct CaptureHeader<Field: View>: View {
    let tint: SpaceTint
    let placeholder: String
    /// Nothing at all in the field — the placeholder shows.
    let showsPlaceholder: Bool
    /// Something other than whitespace — "Save to …" replaces "Switch space".
    let isTyping: Bool
    /// "Save to Work" — nil when the space has nothing to save (Calendar).
    let saveLabel: String?
    let onSave: () -> Void
    let onDot: () -> Void
    /// Where the ⇥ hint goes; nil hides it.
    var switchHint = true
    @ViewBuilder let field: Field

    static var height: CGFloat { 60 }

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            SpaceDot(tint: tint, action: onDot)
            ZStack(alignment: .leading) {
                if showsPlaceholder {
                    Text(placeholder)
                        .font(.system(size: 18))
                        .foregroundStyle(SpaceInk.a(0.40))
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }
                field
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 8)
        .frame(minHeight: Self.height)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SpaceInk.a(0.08)).frame(height: 1)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        ZStack(alignment: .trailing) {
            if !isTyping || saveLabel == nil {
                if switchHint {
                    HStack(spacing: 10) {
                        Text(L10n.t("todo.switchSpace"))
                            .font(.system(size: 12.5))
                            .foregroundStyle(SpaceInk.a(0.45))
                            .fixedSize()
                        CaptureKeyHint(label: L10n.t("capture.tab"))
                    }
                    .transition(.opacity)
                }
            } else if let saveLabel {
                SaveButton(label: saveLabel, action: onSave)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isTyping)
    }
}

/// The 9-pt space dot in an 18-pt slot — the checkbox column's width, so its
/// centre lines up with every checkbox below it.
private struct SpaceDot: View {
    let tint: SpaceTint
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TintTransition(target: tint) { mixed in
                Circle()
                    .fill(mixed.light.color)
                    .frame(width: 9, height: 9)
                    .shadow(color: mixed.base.color.opacity(0.9), radius: 5)
            }
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.t("todo.switchSpace"))
        .accessibilityLabel(L10n.t("todo.switchSpace"))
    }
}

/// The generic key hint: 1-pt border at 22%, 10.5 pt at 60% (U5 §4.1).
struct CaptureKeyHint: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.system(size: 10.5))
            .foregroundStyle(SpaceInk.a(0.6))
            // Content-box, as the reference renders it: 18 of content, 5 of
            // padding each side, then the border.
            .frame(minWidth: 18, minHeight: 18)
            .padding(.horizontal, 5)
            .padding(1)
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(SpaceInk.a(0.22), lineWidth: 1))
            .fixedSize()
            .accessibilityHidden(true)
    }
}

/// "Save to Work" + a filled white ↵ cap; on hover the label brightens and the
/// cap takes a soft violet glow (U5 §4.2, `02b`).
private struct SaveButton: View {
    let label: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(SpaceInk.a(hover ? 1 : 0.72))
                    .lineLimit(1)
                Text("\u{21B5}")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color(hex: "#111111"))
                    .frame(minWidth: 22, minHeight: 20)
                    .padding(.horizontal, 5)
                    .padding(1)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hover ? Color.white : Color(hex: "#F2F1F5")))
                    .shadow(color: Color(hex: "#B69CFF").opacity(hover ? 0.55 : 0), radius: 6)
            }
            .padding(.leading, 6)
            .padding(.trailing, 2)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.2)) { hover = hovering } }
        .accessibilityLabel(label + ", Return")
    }
}

// MARK: Settings (U5 §5.2)

/// A 34-pt gear circle where the avatar was. No shortcut is printed; ⌘, still
/// opens Settings. It opens the same menu the avatar did — Preferences,
/// Insights, the shortcuts, the notes folder and Quit all live there.
struct SettingsGearButton: View {
    @ObservedObject private var store = TodoStore.shared
    @State private var hover = false

    var body: some View {
        Button {
            if store.showsAvatarMenu { store.closeAvatarMenu() } else { store.openAvatarMenu() }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(SpaceInk.a(0.75))
                .frame(width: 34, height: 34)
                .background(Circle().fill(SpaceInk.a(hover || store.showsAvatarMenu ? 0.12 : 0.07)))
                .overlay(Circle().strokeBorder(SpaceInk.a(0.10), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Motion.hoverFade) { hover = hovering } }
        .help(L10n.t("settings.open"))
        .accessibilityLabel(L10n.t("settings.open"))
    }
}

// MARK: The to-do capture header (floating panels)

private struct CaptureFieldWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// The floating panels' to-do field. Same store, same keys and the same
/// NSTextView (with its inline date colouring) as the container's draft row;
/// only the chrome is U5's.
struct TodoCaptureHeader: View {
    @ObservedObject private var store = TodoStore.shared
    @State private var fieldWidth: CGFloat = 0

    private var parsed: NLDateMatch? { NLDateParser.parse(store.draftTitle) }
    private var isTyping: Bool {
        !store.draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Driven from here, where `draftTitle` is observed: an NSViewRepresentable
    /// is not re-measured on a pure content change (see InlineDraftRow).
    private var fieldHeight: CGFloat {
        let width = fieldWidth > 0 ? fieldWidth : 360
        let text = store.draftTitle.isEmpty ? " " : store.draftTitle
        let measured = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 18)])
            .boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                          options: [.usesLineFragmentOrigin, .usesFontLeading]).height
        return max(HighlightingTitleField.lineHeight(18),
                   min(ceil(measured), HighlightingTitleField.maxHeight))
    }

    var body: some View {
        CaptureHeader(
            tint: store.draftSpaceTint,
            placeholder: L10n.t("capture.placeholder"),
            showsPlaceholder: store.draftTitle.isEmpty,
            isTyping: isTyping,
            saveLabel: String(format: L10n.t("capture.saveTo"), store.draftDestination?.name ?? ""),
            onSave: { store.commitDraft() },
            onDot: { store.cycleCollection() }
        ) {
            HighlightingTitleField(
                text: $store.draftTitle,
                highlightRange: parsed?.nsRange,
                accent: SpaceInk.a(1),
                wantsFocus: store.draftWantsFocus,
                onFocusChange: { focused in
                    store.draftFocused = focused
                    if focused { store.draftWantsFocus = false }
                },
                fontSize: 18
            )
            .frame(height: fieldHeight)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: CaptureFieldWidthKey.self, value: proxy.size.width)
            })
            .onPreferenceChange(CaptureFieldWidthKey.self) { fieldWidth = $0 }
        }
        // The resolved date sits in the header's own foot room, so typing
        // "tomorrow" never changes the header's 60 pt.
        .overlay(alignment: .bottomLeading) {
            if let parsed {
                Text("\u{2192} \(parsed.display)")
                    .font(.system(size: 10))
                    .foregroundStyle(SpaceInk.a(0.45))
                    .padding(.leading, 22 + 18 + 13)
                    .padding(.bottom, 4)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { store.draftWantsFocus = true }
    }
}
