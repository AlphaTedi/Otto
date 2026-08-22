import SwiftUI

// MARK: - Onboarding design system
//
// Every number, colour and shape in the onboarding flow, in one place, taken
// from the Figma CSS exports of Sketch A (welcome) and Sketch B (feature
// grid). The rest of the flow is re-skinned FROM here rather than each screen
// carrying its own values — which is how the old flow ended up with a green
// accent on some screens, bordered rows on others, and three different card
// treatments (Marcello, 2026-08-22).
//
// Two deliberate departures from the export, both forced:
//
//   Inter. The export specifies Inter throughout. Otto does not bundle it —
//   the type-system export was tried on 2026-07-26 and reverted, and the app
//   is on SF. The sizes, weights and line heights below are the export's; only
//   the family differs. Bundling Inter is a separate decision with licensing
//   and binary-size consequences, so it is not made here.
//
//   The window is 1200x800 in the export. Otto's onboarding shrinks to
//   520x300 for the practice step so the notch panel cannot cover the
//   instructions; that behaviour is kept, and the compact screen uses the same
//   tokens at a smaller size.

enum OnbColor {
    /// The window itself: purple at the top falling to near-black at the foot.
    static let windowGradient = LinearGradient(
        colors: [Color(hex: "#816BD2"), Color(hex: "#160D35")],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Feature cards and every grouped row (feature bullets, the preference
    /// picker, the final tips).
    static let card = Color.black.opacity(0.3)
    /// The bottom navigation pill.
    static let nav = Color.black.opacity(0.2)
    /// Frosted buttons. The old flow used a solid green fill here.
    static let button = Color.white.opacity(0.1)
    static let buttonHover = Color.white.opacity(0.16)

    static let text = Color.white
    /// Taglines and secondary copy.
    static let subtext = Color.white.opacity(0.6)
    /// Keyboard-badge stroke and label.
    static let badge = Color(hex: "#E6E6E6")
    /// Steps not yet reached.
    static let progressIdle = Color(hex: "#413374")

    /// The wordmark's gradient.
    static let markGradient = LinearGradient(
        colors: [Color(hex: "#B5A5F0"), Color(hex: "#6338FF")],
        startPoint: .top,
        endPoint: .bottom
    )

    // Window controls. Near the system colours but not identical — the export
    // is explicit about these, so they are stated rather than inherited.
    static let close = Color(hex: "#FF736A")
    static let minimize = Color(hex: "#FEBC2E")
    static let zoom = Color(hex: "#19C332")
}

enum OnbMetric {
    static let windowWidth: CGFloat = 1200
    static let windowHeight: CGFloat = 800
    static let windowRadius: CGFloat = 26

    /// Window controls: three 14pt circles, 9pt apart, 18pt in from the corner.
    static let controlDot: CGFloat = 14
    static let controlGap: CGFloat = 9
    static let controlInset: CGFloat = 18

    static let cardRadius: CGFloat = 24
    static let cardPadding: CGFloat = 24
    static let cardGap: CGFloat = 24
    static let imageRadius: CGFloat = 16

    /// Side gutters on the grid screen.
    static let gridInset: CGFloat = 48
    static let gridTop: CGFloat = 72
    /// Room under the grid for the floating nav pill.
    static let gridBottom: CGFloat = 168

    static let navRadius: CGFloat = 999
    static let navPadding: CGFloat = 24
    static let navBottom: CGFloat = 45
    static let navIconButton: CGFloat = 48

    static let buttonRadius: CGFloat = 72
    static let buttonPaddingH: CGFloat = 24
    static let buttonPaddingV: CGFloat = 12
    static let buttonGap: CGFloat = 12

    static let badgeRadius: CGFloat = 6
    static let badgePaddingH: CGFloat = 7.5
    static let badgePaddingV: CGFloat = 2

    /// Progress: the current step is a wide pill, the rest are dots.
    static let progressPill = CGSize(width: 40, height: 8)
    static let progressDot: CGFloat = 8
    static let progressGap: CGFloat = 14
}

enum OnbFont {
    /// 22/27 Medium — taglines and screen subtext.
    static let tagline = Font.system(size: 22, weight: .medium)
    /// 18/22 SemiBold — card titles.
    static let cardTitle = Font.system(size: 18, weight: .semibold)
    /// 16/19 Medium — button labels.
    static let button = Font.system(size: 16, weight: .medium)
    /// 10/12 SemiBold — keyboard badges.
    static let badge = Font.system(size: 10, weight: .semibold)
    /// Screen headlines. Not in the export (both sketches are headline-less),
    /// so it is derived: the tagline's weight ramp, one step up in scale.
    static let title = Font.system(size: 34, weight: .bold)
    static let rowTitle = Font.system(size: 16, weight: .semibold)
    static let rowSubtitle = Font.system(size: 13.5, weight: .regular)
}

// MARK: - Pieces

/// The small bordered key hint that rides next to a button — "↵", "⌥⌘N".
struct OnbKeyBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(OnbFont.badge)
            .foregroundStyle(OnbColor.badge)
            .padding(.horizontal, OnbMetric.badgePaddingH)
            .padding(.vertical, OnbMetric.badgePaddingV)
            .overlay(
                RoundedRectangle(cornerRadius: OnbMetric.badgeRadius, style: .continuous)
                    .strokeBorder(OnbColor.badge, lineWidth: 1)
            )
    }
}

/// The one button shape in the flow. Frosted, pill, optionally carrying the
/// key that also triggers it — replacing the solid green `borderedProminent`
/// the old flow used for Get Started / Continue / Show me / Done.
struct OnbButton: View {
    let title: String
    var key: String? = "\u{21B5}"
    var isEnabled: Bool = true
    var fillsWidth: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: OnbMetric.buttonGap) {
                Text(title)
                    .font(OnbFont.button)
                    .foregroundStyle(OnbColor.text)
                if let key { OnbKeyBadge(text: key) }
            }
            .padding(.horizontal, OnbMetric.buttonPaddingH)
            .padding(.vertical, OnbMetric.buttonPaddingV)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .background(
                Capsule().fill(hovering && isEnabled ? OnbColor.buttonHover : OnbColor.button)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// A quiet text action — "Skip this step".
struct OnbQuietButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(OnbColor.subtext)
        }
        .buttonStyle(.plain)
    }
}

/// The frosted dark surface every grouped thing sits on: feature cards, the
/// preference rows, the tips list.
struct OnbCard<Content: View>: View {
    var padding: CGFloat = OnbMetric.cardPadding
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: OnbMetric.cardRadius, style: .continuous)
                    .fill(OnbColor.card)
            )
    }
}

/// Where the image for a feature card goes. Deliberately a marked, empty slot:
/// the five cards need one bespoke visual each — a small real interface
/// preview, the way Raycast's "Out of the box" screen does it — and that is
/// copy and art direction, not layout. Dropping a real image in here later
/// changes nothing around it.
struct OnbCardImageSlot: View {
    var body: some View {
        RoundedRectangle(cornerRadius: OnbMetric.imageRadius, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: OnbMetric.imageRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One feature card: a centred title over its visual.
struct OnbFeatureCard: View {
    let title: String

    var body: some View {
        OnbCard {
            VStack(spacing: OnbMetric.cardGap) {
                Text(title)
                    .font(OnbFont.cardTitle)
                    .foregroundStyle(OnbColor.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                OnbCardImageSlot()
            }
        }
    }
}

/// Where you are in the flow: the current step widens into a pill, the rest
/// stay dots. No "4 of 8" — nobody should have to count.
struct OnbProgress: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: OnbMetric.progressGap) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i == current ? OnbColor.text : OnbColor.progressIdle)
                    .frame(width: i == current ? OnbMetric.progressPill.width
                                              : OnbMetric.progressDot,
                           height: i == current ? OnbMetric.progressPill.height
                                                : OnbMetric.progressDot)
                    .animation(.spring(response: 0.42, dampingFraction: 0.75), value: current)
            }
        }
    }
}

/// The three window controls.
///
/// The real ones are hidden — they have been since this window was written —
/// so these are not decoration over working buttons; they ARE the controls,
/// and each is wired to the window action it depicts. Their colours are the
/// export's, which sit a shade off the system's on purpose.
struct OnbWindowControls: View {
    @State private var hovering = false

    var body: some View {
        HStack(spacing: OnbMetric.controlGap) {
            dot(OnbColor.close, symbol: "xmark") {
                OnboardingWindowController.dismiss()
            }
            dot(OnbColor.minimize, symbol: "minus") {
                NSApp.keyWindow?.miniaturize(nil)
            }
            dot(OnbColor.zoom, symbol: "arrow.up.left.and.arrow.down.right") {
                NSApp.keyWindow?.zoom(nil)
            }
        }
        .onHover { hovering = $0 }
        .padding(OnbMetric.controlInset)
    }

    private func dot(_ color: Color, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: OnbMetric.controlDot, height: OnbMetric.controlDot)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5))
                // The glyph appears on hover, the way the real ones do.
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.5))
                        .opacity(hovering ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
    }
}

/// The floating bar under the feature grid: back, progress, continue.
struct OnbBottomNav: View {
    var onBack: (() -> Void)?
    let current: Int
    let total: Int
    let continueTitle: String
    let onContinue: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(OnbColor.text)
                        .frame(width: OnbMetric.navIconButton, height: OnbMetric.navIconButton)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: OnbMetric.navIconButton, height: OnbMetric.navIconButton)
            }

            Spacer(minLength: 0)

            OnbProgress(current: current, total: total)

            OnbButton(title: continueTitle, action: onContinue)
        }
        .padding(OnbMetric.navPadding)
        .background(Capsule().fill(OnbColor.nav))
    }
}

// MARK: - Compact

/// True on the practice step, where the window shrinks to 520x300 so the notch
/// panel cannot cover the instructions.
///
/// The design is drawn at 1200x800 and its type is sized for it — a 34pt
/// headline and a 22pt tagline are right there and far too big in a window a
/// quarter the size. Rather than each screen guessing, the flow states which
/// mode it is in and the shared header answers to it.
private struct OnbCompactKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var onbCompact: Bool {
        get { self[OnbCompactKey.self] }
        set { self[OnbCompactKey.self] = newValue }
    }
}

extension OnbFont {
    static func title(compact: Bool) -> Font {
        .system(size: compact ? 22 : 34, weight: .bold)
    }
    static func tagline(compact: Bool) -> Font {
        .system(size: compact ? 13.5 : 22, weight: .medium)
    }
}
