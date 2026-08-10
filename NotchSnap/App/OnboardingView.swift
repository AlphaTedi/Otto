import SwiftUI

// MARK: - Otto onboarding
//
// Four acts, following the plan (Marcello, 2026-08-06):
//
//   Act 1  value, nothing asked   — Meet Otto → what it does → what you want first
//   Act 2  learn by doing         — where it lives → PRESS THE SHORTCUT → nice
//   Act 3  calendar, if wanted    — trust copy, then the real prompt
//   Act 4  send-off               — "Otto will stay quiet until you need it."
//
// The centre of gravity is Act 2. A notch app cannot rely on a visible window to
// teach itself: if onboarding never physically walks someone through summoning
// Otto, they close it once and never look up at the notch again. So the practice
// step listens for the REAL ⌃⇧N — the same Carbon hot key the shipped app
// registers, firing the same code path — and then waits again for the to-do to
// actually be committed. No "Next" button, no simulation.
//
// The practice step also SHRINKS the window and parks it near the bottom of the
// screen, because the notch expands downward over anything centred and would
// otherwise cover the very instructions it is following.
//
// Two things in the plan are deliberately NOT built:
//
//   * An Accessibility permission screen. Otto's global shortcut is a Carbon
//     RegisterEventHotKey, which needs no permission at all — HotkeyManager
//     even logs "No Accessibility permission needed." Asking would have trained
//     users to grant something Otto never uses.
//   * Email sign-in, and any promise of sync. There is no Otto server; to-dos
//     are local JSON. Sign-in exists for the calendar, and says so.
//
// The sign-in step appears ONLY when a bundled OAuth client exists. Without one
// the Google button can only produce a developer-facing error, so the step is
// omitted rather than shown broken.

enum OnboardingFocus: String, CaseIterable {
    case tasks, meetings, both

    var wantsCalendar: Bool { self != .tasks }
}

private enum OnboardingStep {
    case welcome, value, focus, whereItLives, practice, calendar, signIn, allSet
}

struct OnboardingFlowView: View {
    @State private var stepIndex = 0
    @AppStorage("onboardingVersion") var onboardingVersion: Int = 0
    @AppStorage("onboardingFocus") private var focusRaw: String = OnboardingFocus.both.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var focus: OnboardingFocus {
        OnboardingFocus(rawValue: focusRaw) ?? .both
    }

    /// A confirmation that rides on top of the current screen instead of
    /// stopping the flow for one. nil = nothing showing.
    @State private var toast: String?

    /// The calendar step only exists for someone who said meetings matter, so
    /// a pure to-do user is never asked for a permission they will not use.
    ///
    /// `.celebrate` is gone: a full screen whose only job was to say "that
    /// worked" cost a click to deliver information the user had just watched
    /// happen. It is a toast on the practice screen now, and the flow
    /// auto-advances underneath it — two fewer screens across the flow once
    /// the calendar confirmation moved the same way.
    private var steps: [OnboardingStep] {
        var s: [OnboardingStep] = [.welcome, .value, .focus, .whereItLives, .practice]
        if focus.wantsCalendar { s.append(.calendar) }
        // Only offer sign-in when it can actually complete, AND only when it
        // is not already redundant. Connecting Google Calendar on the
        // previous step IS signing in with Google — both go through the same
        // GoogleOAuth.shared singleton and the same account — so a user who
        // just connected their calendar was being asked to "Continue with
        // Google" a second time for an identity the app already had
        // (Marcello, 2026-08-09: "it shouldn't be prompting me again"). This
        // is a computed property, re-evaluated on every render, so the moment
        // a connection completes — even mid-flow — this step drops out of the
        // array on the very next advance. With no bundled OAuth client the
        // Google button could only ever surface "Add your Google OAuth client
        // ID and secret first" — a message meant for whoever builds Otto, not
        // shown to someone trying to use it (Marcello, 2026-08-06). A missing
        // step beats a broken or a redundant one.
        let alreadySignedIn = GoogleOAuth.shared.isSignedIn || AppleSignIn.shared.isSignedIn
        if GoogleOAuth.hasBundledCredentials, !alreadySignedIn { s.append(.signIn) }
        s.append(.allSet)
        return s
    }

    private var step: OnboardingStep {
        let all = steps
        return all[min(stepIndex, all.count - 1)]
    }

    var body: some View {
        ZStack {
            // Window-wide frosted glass — wallpaper bleeds through with depth.
            FrostedGlassBackground()
                .ignoresSafeArea()

            Group {
                switch step {
                case .welcome:
                    OnboardingWelcomeView(onAdvance: advanceStep)
                case .value:
                    OnboardingValueView(onAdvance: advanceStep)
                case .focus:
                    OnboardingFocusView(selection: $focusRaw, onAdvance: advanceStep)
                case .whereItLives:
                    OnboardingNotchView(onAdvance: advanceStep)
                case .practice:
                    OnboardingPracticeView(onAdvance: advanceStep, onToast: showToast)
                case .calendar:
                    OnboardingCalendarView(onAdvance: advanceStep, onToast: showToast)
                case .signIn:
                    OnboardingSignInView(onAdvance: advanceStep)
                case .allSet:
                    OnboardingAllSetView(onFinish: completeOnboarding)
                }
            }
            .transition(stepTransition)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: stepIndex)

            // Non-blocking, bottom-left, above whatever screen is showing.
            if let toast {
                VStack {
                    Spacer()
                    HStack {
                        SuccessToast(text: toast)
                        Spacer()
                    }
                }
                .padding(.leading, 22)
                .padding(.bottom, 18)
                .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: toast)
        // Bounded, not `maxWidth/maxHeight: .infinity`. This view sits in a
        // plain NSHostingView (not NSHostingController, which would manage
        // sizing safely) — telling it "I can be arbitrarily large" is what
        // made the window balloon to fill the screen the moment setCompact's
        // setFrame competed with the hosting view's own intrinsic-size-driven
        // layout, hiding the footer off the bottom of every screen below it
        // (Marcello, 2026-08-09: "I cannot go through the onboarding"). The
        // two real sizes are 520x300 and 600x560; these bounds cover both with
        // a margin and nothing more.
        .frame(minWidth: 480, maxWidth: 640, minHeight: 260, maxHeight: 620)
        // Its own strip, below everything — never on top of a button.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StepDotIndicator(current: stepIndex, total: steps.count)
                .padding(.top, 2)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
        }
        .onAppear { OnboardingWindowController.setCompact(step == .practice) }
        // Single-parameter form: the two-parameter onChange is macOS 14+, and
        // Otto's deployment target is 13.0.
        .onChange(of: stepIndex) { _ in
            OnboardingWindowController.setCompact(step == .practice)
        }
        // Reduce Motion: flatten every staggered spring in the flow into a
        // quick fade — one override here instead of gating each subview.
        .transaction { t in
            if reduceMotion, t.animation != nil {
                t.animation = .easeInOut(duration: 0.15)
            }
        }
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal:   .move(edge: .leading).combined(with: .opacity)
        )
    }

    func advanceStep() {
        SoundManager.shared.play(.stepAdvance)
        withAnimation { stepIndex = min(stepIndex + 1, steps.count - 1) }
    }

    /// Show a confirmation without stopping the flow. Auto-dismisses; the
    /// screen underneath is free to advance while it is still fading.
    private func showToast(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            if toast == text { toast = nil }
        }
    }

    func completeOnboarding() {
        SoundManager.shared.play(.onboardingComplete)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        onboardingVersion = 1
        OnboardingWindowController.dismiss()
    }
}


// MARK: - OnboardingScaffold — one layout every screen shares
//
// The page dots used to be an .overlay(alignment: .bottom) on the whole flow,
// floating over whatever each screen happened to put at its own bottom edge —
// which is why they collided with the footer buttons (Marcello, 2026-08-06).
// Overlays do not reserve space; that is the entire bug.
//
// Here the window is one vertical stack: a content region that takes what is
// left, a footer that is as tall as it needs to be, and a dot rail with its own
// fixed strip underneath. Nothing can overlap anything, on any screen, because
// no two things are ever in the same space.
private struct OnboardingScaffold<Content: View, Footer: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 44)

            footer
                .padding(.horizontal, 44)
                .padding(.top, 8)
                .padding(.bottom, 20)
        }
    }
}

/// The standard header: category chip, one strong line, one quiet line.
/// Same rhythm on every screen so the eye lands in the same place each time.
private struct OnboardingHeader: View {
    /// Category chip above the headline — "Welcome", "Setup", "Shortcut".
    /// Declared first so call sites read in the order the user sees them.
    var eyebrow: String? = nil
    let title: String
    var subtitle: String? = nil
    var topPadding: CGFloat = 52

    var body: some View {
        VStack(spacing: 10) {
            if let eyebrow {
                OnboardingEyebrowPill(text: eyebrow)
                    .padding(.bottom, 2)
            }
            Text(title)
                .font(.system(size: 25, weight: .bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
            }
        }
        .padding(.top, topPadding)
    }
}

/// The one primary button shape used on every screen, so the eye lands in the
/// same place each time instead of hunting for a differently-sized control.
private struct OnboardingPrimaryButton: View {
    let title: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!isEnabled)
        .keyboardShortcut(.return, modifiers: [])
    }
}

private struct OnboardingQuietButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { Text(title) }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.system(size: 12.5))
    }
}

// MARK: - Act 1 · Value (Step 2) — what Otto is for, nothing asked

private struct OnboardingValueView: View {
    var onAdvance: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 46)

            OnboardingEyebrowPill(text: "Why Otto")
                .padding(.bottom, 12)

            Text("Never a window in your way")
                .font(.system(size: 26, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)

            Text("Your tasks and today's meetings live in the notch. One glance up, and back to what you were doing.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 56)
                .padding(.top, 10)

            Spacer().frame(height: 26)

            // Each row shows its benefit happening rather than labelling it
            // with an icon — the one change that turns this from a feature
            // list into a demo reel.
            VStack(spacing: 10) {
                ValueRow(demo: .todoAppears,
                         title: "To-dos that stay out of the way",
                         detail: "Capture one in a second, from any app.")
                ValueRow(demo: .meetingNudge,
                         title: "Meetings before they start",
                         detail: "A quiet nudge, then a card with the join link.")
                ValueRow(demo: .goesQuiet,
                         title: "Silent the rest of the time",
                         detail: "No dock icon, no badge, no noise.")
            }
            .padding(.horizontal, 40)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.15), value: appeared)

            Spacer()

            Button(action: onAdvance) {
                Text("Continue \u{2192}")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])
            .padding(.horizontal, 48)
            .padding(.bottom, 40)
        }
        .onAppear { appeared = true }
    }
}

private struct ValueRow: View {
    let demo: FeatureDemo
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            FeatureDemoLoop(demo: demo)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(GlassTile())
    }
}

// MARK: - Act 1 · Focus (Step 3) — self-identification, non-blocking
//
// Lightweight personalisation that also primes someone to see themselves as
// a person who needs this. Its only mechanical effect is whether the calendar
// step appears at all — nobody is asked for a permission they said they did
// not want.

private struct OnboardingFocusView: View {
    @Binding var selection: String
    var onAdvance: () -> Void

    private let options: [(OnboardingFocus, String, String, String)] = [
        (.tasks,    "checklist",       "Tasks",    "Keep a list I can reach instantly"),
        (.meetings, "calendar",        "Meetings", "Know what's next without opening my calendar"),
        (.both,     "sparkles",        "Both",     "The whole day, in one place"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 58)

            OnboardingEyebrowPill(text: "Setup")
                .padding(.bottom, 12)

            Text("What should Otto help with first?")
                .font(.system(size: 24, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)

            Text("You can change this later — it just decides what we set up now.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            Spacer().frame(height: 28)

            VStack(spacing: 10) {
                ForEach(options, id: \.0) { option in
                    FocusOptionRow(
                        icon: option.1, title: option.2, detail: option.3,
                        isSelected: selection == option.0.rawValue
                    ) {
                        selection = option.0.rawValue
                    }
                }
            }
            .padding(.horizontal, 40)

            Spacer()

            Button(action: onAdvance) {
                Text("Continue \u{2192}")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])
            .padding(.horizontal, 48)
            .padding(.bottom, 40)
        }
    }
}

private struct FocusOptionRow: View {
    let icon: String
    let title: String
    let detail: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(isSelected ? 0.10 : (hover ? 0.06 : 0.03)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.7)
                                             : Color.primary.opacity(0.08),
                                  lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Frosted Glass Background — heavy blur + soft tint, used by onboarding & settings

struct FrostedGlassBackground: View {
    /// Drives the slow drift of the ambient glows. One shared phase so the
    /// two blobs move in a loose, non-synchronised way rather than in lockstep.
    @State private var drift = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Layer 1: behind-window blur of the wallpaper
            VisualEffectBackground(material: .fullScreenUI, blendingMode: .behindWindow)

            // Layer 2: soft tint that picks up the wallpaper hue but pushes it lighter
            LinearGradient(
                colors: [
                    Color.white.opacity(0.18),
                    Color.white.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Layer 3: ambient colour wash — the single cheapest thing that
            // makes a flow read as "premium" rather than "a form". Two large,
            // heavily blurred radial gradients anchored off-canvas at opposite
            // corners, drifting slowly against each other so the light never
            // sits still but never draws the eye either. No assets, no video.
            //
            // Saturated at the edges, nothing in the centre: content always
            // sits on calm background, which is the rule that keeps this from
            // competing with the copy.
            GeometryReader { geo in
                ZStack {
                    ambientBlob(
                        colors: [Color(hex: "#7C5CFF"), Color(hex: "#C86DD7")],
                        size: geo.size.width * 0.95
                    )
                    .offset(x: -geo.size.width * 0.30,
                            y: drift ? -geo.size.height * 0.34 : -geo.size.height * 0.22)

                    ambientBlob(
                        colors: [Color(hex: "#FF8A4C"), Color(hex: "#4C8DFF")],
                        size: geo.size.width * 0.85
                    )
                    .offset(x: geo.size.width * 0.34,
                            y: drift ? geo.size.height * 0.30 : geo.size.height * 0.18)
                }
                .blur(radius: 90)
                .allowsHitTesting(false)
            }

            // Layer 4: faint vignette to anchor the floating cards
            RadialGradient(
                colors: [Color.clear, Color.black.opacity(0.10)],
                center: .center,
                startRadius: 200,
                endRadius: 700
            )
        }
        .onAppear {
            // Reduce Motion: keep the colour, drop the drift. The glow is
            // decorative, so holding it still costs nothing.
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 11).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private func ambientBlob(colors: [Color], size: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: colors.map { $0.opacity(0.55) } + [.clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
    }
}

// MARK: - OnboardingEyebrowPill — what kind of step this is, before you read
//
// A small category chip above every headline. It does more work than its size
// suggests: it tells someone whether they are being sold to, set up, or asked
// for something, before they have read a single word of the actual copy.

private struct OnboardingEyebrowPill: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(Color(hex: "#FF7A4D"))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color(hex: "#FF7A4D").opacity(0.15))
            )
            .accessibilityHidden(true)   // decorative; the headline carries meaning
    }
}

// MARK: - SuccessToast — confirmation that does not cost a whole screen
//
// Replaces two full-screen "it worked!" steps. A dedicated screen to say
// "Nice, that happened" is two extra clicks for information the user already
// has — they just watched it happen. This says the same thing without
// stopping them, and the flow keeps moving underneath it.

private struct SuccessToast: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.green)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.28), radius: 12, y: 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Step Dot Indicator

struct StepDotIndicator: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                let isCurrent = i == current
                let isDone = i < current
                Capsule()
                    // Three states, not two: done reads slightly brighter than
                    // upcoming, so the bar shows how far along you are without
                    // ever printing "4 of 8" and making anyone count.
                    .fill(isCurrent ? Color.accentColor
                                    : Color.secondary.opacity(isDone ? 0.55 : 0.25))
                    .frame(width: isCurrent ? 22 : 8, height: 6)
                    // The glow is what makes "you are here" read instantly at a
                    // glance, rather than being a slightly wider grey dash.
                    .shadow(color: isCurrent ? Color.accentColor.opacity(0.55) : .clear,
                            radius: 5)
                    .animation(.spring(response: 0.42, dampingFraction: 0.7), value: current)
            }
        }
    }
}

// MARK: - Visual Effect Background (blur wallpaper)

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .fullScreenUI
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Welcome View (Step 1)

struct OnboardingWelcomeView: View {
    var onAdvance: () -> Void
    @State private var iconAppeared = false
    @State private var textAppeared = false
    @State private var previewAppeared = false
    @State private var buttonAppeared = false

    var body: some View {
        VStack(spacing: 0) {
            // App icon with bounce
            Image(systemName: "checklist")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .scaleEffect(iconAppeared ? 1.0 : 0.5)
                .opacity(iconAppeared ? 1.0 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.1), value: iconAppeared)
                .padding(.top, 48)

            Spacer().frame(height: 20)

            OnboardingEyebrowPill(text: "Welcome")
                .padding(.bottom, 12)

            Text("Otto")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.primary)
                .opacity(textAppeared ? 1.0 : 0)
                .offset(y: textAppeared ? 0 : 12)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: textAppeared)

            Text("Your to-dos and today's meetings, always in reach of the notch.")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .opacity(textAppeared ? 1.0 : 0)
                .offset(y: textAppeared ? 0 : 8)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: textAppeared)

            Spacer().frame(height: 32)

            // Mini preview
            NotchMiniPreview()
                .frame(height: 120)
                .padding(.horizontal, 48)
                .opacity(previewAppeared ? 1.0 : 0)
                .scaleEffect(previewAppeared ? 1.0 : 0.95)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: previewAppeared)

            Spacer()

            // CTA button
            Button(action: onAdvance) {
                HStack {
                    Text("Get Started")
                        .fontWeight(.semibold)
                    Image(systemName: "arrow.right")
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])
            .padding(.horizontal, 48)
            .opacity(buttonAppeared ? 1.0 : 0)
            .offset(y: buttonAppeared ? 0 : 8)
            .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.55), value: buttonAppeared)
            .padding(.bottom, 40)
        }
        .onAppear {
            iconAppeared = true
            textAppeared = true
            previewAppeared = true
            buttonAppeared = true
        }
    }
}

// MARK: - Act 2 · Where Otto lives (Step 4)
//
// Show the gesture before asking for it. The animation is the same
// NotchMiniPreview loop the welcome screen uses, so by the time someone is
// asked to press the shortcut they have watched the notch open twice.

private struct OnboardingNotchView: View {
    var onAdvance: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 50)

            OnboardingEyebrowPill(text: "Where it lives")
                .padding(.bottom, 12)

            Text("Otto lives in the notch")
                .font(.system(size: 24, weight: .bold))

            Text("Not in the Dock, not in a window. Move your cursor up to the notch and it opens.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 60)
                .padding(.top, 8)

            Spacer().frame(height: 24)

            NotchMiniPreview()
                .frame(width: 340, height: 170)
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.96)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1), value: appeared)

            Spacer().frame(height: 20)

            Text("There's a keyboard way too — that's next.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)

            Spacer()

            Button(action: onAdvance) {
                Text("Show me \u{2192}")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])
            .padding(.horizontal, 48)
            .padding(.bottom, 40)
        }
        .onAppear { appeared = true }
    }
}

// MARK: - Act 2 · Practice (Step 5) — the core of the whole flow
//
// The user performs the app's actual core action, for real, before onboarding
// ends. Two stages, because opening the panel is only half the lesson:
//
//   1. press ⌃⇧N          → the real Carbon hot key, the real notch opens
//   2. type it and ⏎      → the real to-do is really saved
//
// Stage 2 exists because the first version stopped at stage 1: the notch
// appeared and onboarding moved on, so nobody was ever shown the part where
// you actually write something (Marcello, 2026-08-06). Someone who finishes
// this screen has created a to-do, not watched a panel open.
//
// Neither stage can be completed with a "Next" button. A skip appears after
// 15s so a user whose keyboard is intercepted by a launcher is never trapped.

private struct OnboardingPracticeView: View {
    var onAdvance: () -> Void
    var onToast: (String) -> Void

    private enum Stage { case awaitingShortcut, awaitingTodo }
    @State private var stage: Stage = .awaitingShortcut
    @State private var pulse = false
    @State private var showSkip = false
    @State private var done = false

    var body: some View {
        OnboardingScaffold {
            VStack(spacing: 0) {
                OnboardingHeader(
                    eyebrow: "Shortcut",
                    title: stage == .awaitingShortcut
                        ? "Add your first to-do"
                        : "Now type it",
                    subtitle: stage == .awaitingShortcut
                        ? "Press the shortcut. It works from any app — you don't have to be in Otto."
                        : "Otto is open at the notch with the cursor already in the field. Write anything and press Return."
                )

                Spacer(minLength: 20)

                if stage == .awaitingShortcut {
                    ShortcutKeys(keys: ["\u{2303}", "\u{21E7}", "N"])
                        .scaleEffect(pulse ? 1.03 : 1)
                        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                                   value: pulse)
                } else {
                    ShortcutKeys(keys: ["\u{21A9}"])
                        .scaleEffect(pulse ? 1.03 : 1)
                        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                                   value: pulse)
                }

                Spacer(minLength: 18)

                Label(stage == .awaitingShortcut
                        ? "Waiting for the shortcut\u{2026}"
                        : "Waiting for your first to-do\u{2026}",
                      systemImage: stage == .awaitingShortcut ? "keyboard" : "pencil.line")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)

                Spacer(minLength: 12)
            }
        } footer: {
            // The footer keeps its height whether or not the skip is showing,
            // so the screen does not jump when it appears.
            Group {
                if showSkip {
                    OnboardingQuietButton(title: "Skip this step", action: onAdvance)
                        .transition(.opacity)
                } else {
                    Color.clear
                }
            }
            .frame(height: 20)
        }
        .onAppear {
            pulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                withAnimation { showSkip = true }
            }
        }
        // Stage 1 → 2. The real hot key: HotkeyManager posts this from the same
        // handler the shipped shortcut runs through.
        .onReceive(NotificationCenter.default.publisher(for: .quickEntryFired)) { _ in
            guard stage == .awaitingShortcut else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                stage = .awaitingTodo
            }
        }
        // Stage 2 → done. A real row in the real store.
        .onReceive(NotificationCenter.default.publisher(for: .todoCreated)) { _ in
            guard !done else { return }
            done = true
            // Confirmation rides along instead of taking a screen of its own.
            onToast("Nice \u{2014} that\u{2019}s it.")
            // Let the row land in the notch before the window moves on.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { onAdvance() }
        }
    }
}

/// The shortcut as physical keys, not a text string — the subject of the
/// screen, not a hint printed on it.
///
/// Three things separate this from flat evenly-spaced rectangles: each cap
/// has a lit top edge and a shadow so it reads as a physical object; caps sit
/// at slight alternating rotations and overlap so the group looks placed
/// rather than laid out; and ghost caps sit behind at low opacity implying a
/// whole keyboard around them. They settle in on the app's own contentHug
/// spring (response 0.45 / damping 0.60), the same spring the notch itself
/// animates on, so the moment feels like Otto rather than a generic modal.
private struct ShortcutKeys: View {
    let keys: [String]
    /// Ghost caps and rotation are for the practice moment, where the keys ARE
    /// the screen. A plain inline row (a settings hint, say) sets this false
    /// and gets flat, upright, evenly spaced caps.
    var isHero: Bool = true

    @State private var landed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Alternating tilt, deterministic per position rather than random, so the
    /// composition is the same every time the screen is shown.
    private func rotation(_ index: Int) -> Double {
        guard isHero else { return 0 }
        let pattern: [Double] = [-6, 3.5, -2.5, 5]
        return pattern[index % pattern.count]
    }

    var body: some View {
        ZStack {
            if isHero {
                // Faint keys behind, implying the rest of a keyboard. Purely
                // atmospheric — hidden from accessibility, never announced.
                HStack(spacing: 26) {
                    ghostCap("K", rotation: -14, size: 44)
                    ghostCap("O", rotation: 10, size: 52)
                    ghostCap("\u{2713}", rotation: -7, size: 40)
                }
                .offset(y: 6)
                .accessibilityHidden(true)
            }

            HStack(spacing: isHero ? -6 : 8) {
                ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                    keycap(key)
                        .rotationEffect(.degrees(landed ? rotation(index) : 0))
                        .offset(y: landed ? 0 : 14)
                        .opacity(landed ? 1 : 0)
                        .zIndex(Double(keys.count - index))
                        .animation(
                            reduceMotion
                                ? .easeOut(duration: 0.2)
                                : .spring(response: 0.45, dampingFraction: 0.60)
                                    .delay(Double(index) * 0.07),
                            value: landed
                        )
                }
            }
        }
        .onAppear { landed = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(keys.joined(separator: " "))
    }

    private func keycap(_ key: String) -> some View {
        Text(key)
            .font(.system(size: 21, weight: .medium))
            .frame(minWidth: 52, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(
                        // Top-lit: brighter at the top edge, darker at the
                        // bottom, which is what sells "object" over "rectangle".
                        LinearGradient(
                            colors: [Color.primary.opacity(0.14), Color.primary.opacity(0.05)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.28), Color.white.opacity(0.06)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(isHero ? 0.42 : 0), radius: 12, y: 6)
    }

    private func ghostCap(_ key: String, rotation: Double, size: CGFloat) -> some View {
        Text(key)
            .font(.system(size: size * 0.38, weight: .medium))
            .foregroundStyle(Color.primary.opacity(0.10))
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )
            .rotationEffect(.degrees(rotation))
    }
}
// MARK: - Act 3 · Calendar (Step 7) — trust copy BEFORE the system dialog
//
// Two macOS realities shape this screen:
//
//   * A permission prompt often fires only once per install. If someone
//     dismisses it, relaunching does NOT reliably re-ask — so the "Open System
//     Settings" link is permanent, not a fallback that appears after failure.
//   * Otto cannot detect a grant that happens in System Settings while it sits
//     here, so the state is re-checked every time the app regains focus.
//
// Only reached when the user said meetings matter to them.

private struct OnboardingCalendarView: View {
    var onAdvance: () -> Void
    var onToast: (String) -> Void
    @ObservedObject private var calendar = CalendarStore.shared
    @State private var asking = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 50)

            OnboardingEyebrowPill(text: "Permission")
                .padding(.bottom, 14)

            Image(systemName: calendar.isConnected ? "calendar.badge.checkmark" : "calendar")
                .font(.system(size: 40))
                .foregroundStyle(calendar.isConnected ? .green : .orange)

            Text(calendar.isConnected ? "Calendar connected" : "See today's meetings")
                .font(.system(size: 24, weight: .bold))
                .padding(.top, 14)

            Text(calendar.isConnected
                 ? "Today's events will show at the top of the notch, with a nudge before each one starts."
                 : "Otto reads the calendars already on this Mac so it can show what's next and warn you before it starts.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 56)
                .padding(.top, 8)

            Spacer().frame(height: 22)

            if !calendar.isConnected {
                // The trade, stated plainly, BEFORE macOS asks.
                VStack(alignment: .leading, spacing: 8) {
                    TrustLine(icon: "eye.slash", text: "Read-only. Otto never creates, edits or deletes an event.")
                    TrustLine(icon: "laptopcomputer", text: "Nothing leaves this Mac. There is no Otto server.")
                    TrustLine(icon: "hand.raised", text: "Skip it and everything else still works.")
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background(GlassTile())
                .padding(.horizontal, 44)
            }

            Spacer()

            VStack(spacing: 10) {
                if calendar.isConnected {
                    Button(action: onAdvance) {
                        Text("Continue \u{2192}").fontWeight(.semibold)
                            .frame(maxWidth: .infinity).frame(height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.return, modifiers: [])
                    .padding(.horizontal, 48)
                } else {
                    Button {
                        asking = true
                        Task {
                            await calendar.connect()
                            asking = false
                            // Confirm inline and keep moving, rather than
                            // spending a whole screen on "it worked".
                            if calendar.isConnected {
                                onToast("Calendar connected")
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { onAdvance() }
                            }
                        }
                    } label: {
                        Text(asking ? "Waiting for macOS\u{2026}" : "Connect calendar")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity).frame(height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(asking)
                    .keyboardShortcut(.return, modifiers: [])
                    .padding(.horizontal, 48)

                    // Permanent, not conditional: macOS may never prompt again.
                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))

                    Button("Not now") { onAdvance() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 12))
                }
            }
            .padding(.bottom, 34)
        }
        // A grant made in System Settings is invisible to us until we look
        // again, and coming back to the app is exactly when to look.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            calendar.refreshNow()
        }
    }
}

private struct TrustLine: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}


// MARK: - Act 3 · Sign in (Step 8) — after the value is felt, never before
//
// Placed last because nothing above it needed an account: Otto's to-dos are
// local JSON and work signed out forever. "Set up later" is therefore a real
// escape hatch, not a dark pattern — skipping costs the user nothing today.
//
// WHAT IS REAL HERE, precisely:
//
//   * Google works end to end. GoogleOAuth already runs PKCE + loopback and
//     already asks for openid/email, so the token response carries an id_token
//     it reads the address out of. Signing in gives a genuine account.
//   * Apple works end to end too (added 2026-08-09), via AppleSignIn in
//     KeychainStore.swift — real ASAuthorizationController, real Keychain
//     storage, real Touch ID / Apple Watch on a Mac already signed into
//     iCloud. It needs one one-time portal step only Marcello can do: "Sign
//     In with Apple" enabled on the com.notchsnap.app identifier at
//     developer.apple.com. Until that is flipped, the request reaches Apple's
//     servers and comes back with a permission error, which SignInError
//     surfaces as readable text rather than a raw OSStatus.
//
// Neither one syncs anything yet — there is no Otto server. The screen claims
// only what is true: it identifies you, and it is what future sync will hang
// off. Promising "your to-dos everywhere" today would be a lie.

private struct OnboardingSignInView: View {
    var onAdvance: () -> Void
    @State private var busyProvider: SignInButton.Provider?
    @State private var error: String?
    @State private var signedInAs: String? = GoogleOAuth.shared.account ?? AppleSignIn.shared.account

    var body: some View {
        OnboardingScaffold {
            VStack(spacing: 0) {
                OnboardingHeader(
                    eyebrow: "Account",
                    title: signedInAs == nil ? "Bring your calendar with you" : "Signed in",
                    subtitle: signedInAs == nil
                        ? "Connect Google and Otto shows today's meetings, the join link, and who else is coming — with their faces, not their initials."
                        : nil
                )

                if let signedInAs {
                    Spacer(minLength: 18)
                    VStack(spacing: 10) {
                        AccountAvatar(email: signedInAs, diameter: 56)
                        Text(signedInAs)
                            .font(.system(size: 13, weight: .medium))
                    }
                    Spacer(minLength: 18)
                } else {
                    Spacer(minLength: 22)

                    VStack(spacing: 10) {
                        SignInButton(provider: .google, busy: busyProvider == .google) { signInWithGoogle() }
                        SignInButton(provider: .apple, busy: busyProvider == .apple) { signInWithApple() }
                    }
                    .frame(maxWidth: 320)

                    if let error {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.top, 12)
                            .padding(.horizontal, 20)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 16)

                    Text("Read-only, and nothing leaves this Mac. Your to-dos stay local either way — this is about your calendar.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } footer: {
            VStack(spacing: 10) {
                if signedInAs != nil {
                    OnboardingPrimaryButton(title: "Continue", action: onAdvance)
                } else {
                    OnboardingQuietButton(title: "Set up later", action: onAdvance)
                }
            }
        }
        // Belt-and-suspenders alongside the `steps` array skipping this
        // screen entirely once signed in: `signedInAs` is a `@State` initial
        // value, captured once when this view is constructed, not something
        // that re-reads GoogleOAuth on its own. If a sign-in from the
        // previous (calendar) step is still finishing its async token
        // exchange at the exact moment this view happens to render, that
        // snapshot could be stale for one frame. Re-checking on appear costs
        // nothing and closes that gap completely.
        .onAppear {
            signedInAs = GoogleOAuth.shared.account ?? AppleSignIn.shared.account
        }
    }

    private func signInWithGoogle() {
        busyProvider = .google
        error = nil
        Task {
            do {
                try await GoogleOAuth.shared.signIn()
                signedInAs = GoogleOAuth.shared.account
            } catch {
                self.error = error.localizedDescription
            }
            busyProvider = nil
        }
    }

    private func signInWithApple() {
        busyProvider = .apple
        error = nil
        Task {
            do {
                try await AppleSignIn.shared.signIn()
                signedInAs = AppleSignIn.shared.account
            } catch AppleSignIn.SignInError.cancelled {
                // A changed mind is not a failure worth a red line of text.
            } catch {
                self.error = error.localizedDescription
            }
            busyProvider = nil
        }
    }
}

/// Provider buttons drawn to each vendor's shape conventions: Google's is the
/// light pill with the four-colour G, Apple's the black pill with the logo
/// glyph. Both use the vendor's own mark rather than a generic SF Symbol,
/// which is a branding requirement for real sign-in buttons, not a nicety.
private struct SignInButton: View {
    enum Provider { case google, apple }
    let provider: Provider
    let busy: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                switch provider {
                case .google: GoogleGlyph().frame(width: 17, height: 17)
                case .apple:
                    Image(systemName: "apple.logo")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                }
                Text(busy
                     ? (provider == .google ? "Waiting for the browser\u{2026}" : "Waiting for Touch ID\u{2026}")
                     : (provider == .google ? "Continue with Google" : "Continue with Apple"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(provider == .google ? Color.black.opacity(0.82) : .white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(provider == .google ? Color.white : Color.black)
                    .opacity(hover ? 0.92 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.black.opacity(provider == .google ? 0.16 : 0), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .onHover { hover = $0 }
        .help(provider == .apple
              ? "Sign in with your Apple ID — Touch ID or Apple Watch if this Mac is signed into iCloud"
              : "Sign in with your Google account")
    }
}

/// Google's "G", drawn as its four arcs rather than shipped as a bitmap, so it
/// stays crisp and carries no asset.
private struct GoogleGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                Circle().trim(from: 0.0,  to: 0.25).stroke(Color(hex: "#EA4335"), lineWidth: s * 0.26)
                    .rotationEffect(.degrees(-135))
                Circle().trim(from: 0.0,  to: 0.25).stroke(Color(hex: "#FBBC05"), lineWidth: s * 0.26)
                    .rotationEffect(.degrees(135))
                Circle().trim(from: 0.0,  to: 0.25).stroke(Color(hex: "#34A853"), lineWidth: s * 0.26)
                    .rotationEffect(.degrees(45))
                Circle().trim(from: 0.0,  to: 0.28).stroke(Color(hex: "#4285F4"), lineWidth: s * 0.26)
                    .rotationEffect(.degrees(-45))
                Rectangle()
                    .fill(Color(hex: "#4285F4"))
                    .frame(width: s * 0.42, height: s * 0.24)
                    .offset(x: s * 0.20, y: s * 0.02)
            }
            .frame(width: s, height: s)
        }
    }
}

// MARK: - GlassTile — reusable liquid-glass background pane

struct GlassTile: View {
    var cornerRadius: CGFloat = 14

    var body: some View {
        // Clean blur — no sheen, no gradient overlay. Just the material.
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
    }
}

// MARK: - NotchMiniPreview (animated loop for Welcome screen)

/// A miniature of the real interaction: a cursor travels to the notch, the
/// notch opens, and a to-do lands in it.
///
/// This screen exists to demonstrate a SPATIAL behaviour that words genuinely
/// cannot carry — "it lives up there, and it grows downward when you need it."
/// The previous version animated a bare black rounded rectangle with nothing
/// inside, which read as an unfinished placeholder rather than a demo
/// (Marcello, 2026-08-09). The fix is not more motion, it is CONTENT: a
/// pretend menu bar for context, a cursor that moves on its own, and a real-
/// looking row appearing inside the opened panel.
///
/// Built in SwiftUI rather than as a recorded screen capture on purpose: no
/// asset to ship or keep in sync with the UI, crisp at any size, adapts to
/// light and dark, and no AVPlayer burning CPU behind an onboarding window.
struct NotchMiniPreview: View {
    @State private var phase = 0
    @State private var loop: DispatchWorkItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// phase 0 idle · 1 cursor arriving · 2 notch open · 3 to-do landed
    private var isOpen: Bool { phase >= 2 }

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay { screen }
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onAppear { startLoop() }
            .onDisappear { loop?.cancel(); loop = nil }
            .accessibilityHidden(true)   // decorative; the copy explains it
    }

    private var screen: some View {
        GeometryReader { geo in
            let notchWidth: CGFloat = isOpen ? min(geo.size.width * 0.62, 190) : 54
            let notchHeight: CGFloat = isOpen ? 62 : 16

            ZStack(alignment: .top) {
                // A hint of desktop, so the notch has something to sit against
                // and the whole thing reads as "a Mac screen" immediately.
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.07))
                        .frame(height: 16)
                    Spacer()
                }

                // The notch itself.
                VStack(spacing: 0) {
                    ZStack {
                        RoundedRectangle(cornerRadius: isOpen ? 13 : 7, style: .continuous)
                            .fill(Color.black)
                            .frame(width: notchWidth, height: notchHeight)

                        if phase >= 3 {
                            miniTodoRow
                                .frame(width: notchWidth - 22)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    Spacer()
                }
                // The app's own contentHug spring — the miniature opens with
                // exactly the motion the real notch uses.
                .animation(.spring(response: 0.45, dampingFraction: 0.60), value: phase)

                // Cursor travelling up to the notch, then resting there.
                Image(systemName: "cursorarrow")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .position(
                        x: geo.size.width * (phase == 0 ? 0.30 : 0.5),
                        y: phase == 0 ? geo.size.height * 0.72 : 30
                    )
                    .opacity(phase >= 2 ? 0 : 1)
                    .animation(.easeInOut(duration: 0.75), value: phase)
            }
        }
    }

    private var miniTodoRow: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Color.accentColor, lineWidth: 1.4)
                .frame(width: 9, height: 9)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.85))
                .frame(height: 5)
            Spacer(minLength: 0)
        }
        .padding(.top, 26)
    }

    private func startLoop() {
        // Reduce Motion: settle on the finished frame and stop. The point of
        // the demo is the end state; the journey is the decorative part.
        guard !reduceMotion else { phase = 3; return }

        let delays: [Double] = [0, 0.9, 1.9, 2.7]
        for (i, delay) in delays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation { phase = i }
            }
        }
        // Held in a cancellable work item so leaving the screen actually stops
        // the loop — the old version rescheduled itself forever, outliving the
        // view that started it.
        let next = DispatchWorkItem { [self] in
            phase = 0
            startLoop()
        }
        loop = next
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.6, execute: next)
    }
}

// MARK: - FeatureDemoLoop — a value row that shows instead of tells
//
// Replaces the static icon beside each benefit line with a small looping
// animation of the thing actually happening, badged with a play triangle so it
// reads as a demo rather than decoration.
//
// SwiftUI animation rather than recorded video, for the same reasons as
// NotchMiniPreview: nothing to ship, nothing to re-record when the UI moves,
// and it stays sharp at any size.

private enum FeatureDemo {
    case todoAppears, meetingNudge, goesQuiet
}

private struct FeatureDemoLoop: View {
    let demo: FeatureDemo
    @State private var t = 0
    @State private var loop: DispatchWorkItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))

            content
                .padding(6)

            // Play badge — Raycast's tell that a tile is a demo, not an icon.
            Image(systemName: "play.fill")
                .font(.system(size: 5))
                .foregroundStyle(.white.opacity(0.85))
                .padding(3)
                .background(Circle().fill(Color.black.opacity(0.45)))
                .padding(3)
        }
        .frame(width: 46, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear { start() }
        .onDisappear { loop?.cancel(); loop = nil }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch demo {
        case .todoAppears:
            // A row drops into a short list.
            VStack(alignment: .leading, spacing: 3) {
                miniRow(filled: true)
                miniRow(filled: true).opacity(0.5)
                miniRow(filled: false)
                    .opacity(t >= 1 ? 1 : 0)
                    .offset(y: t >= 1 ? 0 : -5)
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.60), value: t)

        case .meetingNudge:
            // A card slides in from the top edge, the way an alert arrives.
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: "#E8C15A").opacity(0.9))
                    .frame(height: 9)
                    .overlay(alignment: .leading) {
                        Circle().fill(.black.opacity(0.5))
                            .frame(width: 4, height: 4).padding(.leading, 3)
                    }
                    .offset(y: t >= 1 ? 0 : -14)
                    .opacity(t >= 1 ? 1 : 0)
                Spacer(minLength: 0)
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.60), value: t)

        case .goesQuiet:
            // The panel shrinks back to a resting pill.
            VStack {
                RoundedRectangle(cornerRadius: t >= 1 ? 2 : 4, style: .continuous)
                    .fill(Color.black.opacity(0.65))
                    .frame(width: t >= 1 ? 16 : 34, height: t >= 1 ? 5 : 18)
                Spacer(minLength: 0)
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.60), value: t)
        }
    }

    private func miniRow(filled: Bool) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1.5)
                .strokeBorder(Color.accentColor.opacity(filled ? 0.5 : 1), lineWidth: 1)
                .frame(width: 5, height: 5)
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.primary.opacity(filled ? 0.25 : 0.55))
                .frame(height: 3)
        }
    }

    private func start() {
        guard !reduceMotion else { t = 1; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { withAnimation { t = 1 } }
        let next = DispatchWorkItem { t = 0; start() }
        loop = next
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: next)
    }
}

// MARK: - All Set View (Step 2) — How to use Otto

struct OnboardingAllSetView: View {
    var onFinish: () -> Void
    @State private var headerAppeared = false
    @State private var tipsAppeared = false
    @State private var buttonAppeared = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.18))
                    .frame(width: 84, height: 84)
                Image(systemName: "checkmark")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.green)
            }
            .scaleEffect(headerAppeared ? 1.0 : 0.6)
            .opacity(headerAppeared ? 1 : 0)
            .animation(.spring(response: 0.55, dampingFraction: 0.6).delay(0.05), value: headerAppeared)
            .padding(.top, 36)

            Spacer().frame(height: 16)

            OnboardingEyebrowPill(text: "Done")
                .padding(.bottom, 12)

            Text("You\u{2019}re set")
                .font(.system(size: 28, weight: .bold))
                .opacity(headerAppeared ? 1 : 0)
                .offset(y: headerAppeared ? 0 : 8)
                .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.18), value: headerAppeared)

            Text("Otto will stay quiet until you need it.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .opacity(headerAppeared ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(0.28), value: headerAppeared)

            Spacer().frame(height: 22)

            VStack(spacing: 10) {
                AllSetTip(icon: "bolt", iconTint: .blue,
                          title: "Add a to-do from anywhere",
                          detail: "Works even when Otto isn't the active app.",
                          shortcut: "\u{2325}\u{2318}N")
                AllSetTip(icon: "text.cursor", iconTint: .purple,
                          title: "Quick Find",
                          detail: "Just start typing to search across every category.",
                          shortcut: "a\u{2026}z")
                AllSetTip(icon: "calendar", iconTint: .orange,
                          title: "See today's meetings",
                          detail: "Connect a calendar in Settings and Today shows what's next.",
                          shortcut: nil)
                AllSetTip(icon: "macbook", iconTint: .pink,
                          title: "Reach the notch",
                          detail: "Hover to peek, click to open. Press ? inside for every shortcut.",
                          shortcut: nil)
            }
            .padding(.horizontal, 32)
            .opacity(tipsAppeared ? 1 : 0)
            .offset(y: tipsAppeared ? 0 : 14)
            .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.35), value: tipsAppeared)

            Spacer()

            Button(action: onFinish) {
                Text("Done")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])
            .padding(.horizontal, 48)
            .opacity(buttonAppeared ? 1 : 0)
            .offset(y: buttonAppeared ? 0 : 8)
            .animation(.spring(response: 0.4, dampingFraction: 0.85).delay(0.55), value: buttonAppeared)
            .padding(.bottom, 40)
        }
        .onAppear {
            headerAppeared = true
            tipsAppeared = true
            buttonAppeared = true
        }
    }
}

private struct AllSetTip: View {
    let icon: String
    let iconTint: Color
    let title: String
    let detail: String
    let shortcut: String?

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(iconTint.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(iconTint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }

            Spacer()

            if let shortcut {
                Text(shortcut)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.18))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                    )
            }
        }
        .padding(12)
        .background(GlassTile(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

// MARK: - Tutorial Card (kept for compatibility)

struct TutorialCard: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(.accentColor)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(description).font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}
