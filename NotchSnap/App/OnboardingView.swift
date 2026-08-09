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
    case welcome, value, focus, whereItLives, practice, celebrate, calendar, signIn, allSet
}

struct OnboardingFlowView: View {
    @State private var stepIndex = 0
    @AppStorage("onboardingVersion") var onboardingVersion: Int = 0
    @AppStorage("onboardingFocus") private var focusRaw: String = OnboardingFocus.both.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var focus: OnboardingFocus {
        OnboardingFocus(rawValue: focusRaw) ?? .both
    }

    /// The calendar step only exists for someone who said meetings matter, so
    /// a pure to-do user is never asked for a permission they will not use.
    private var steps: [OnboardingStep] {
        var s: [OnboardingStep] = [.welcome, .value, .focus, .whereItLives, .practice, .celebrate]
        if focus.wantsCalendar { s.append(.calendar) }
        // Only offer sign-in when it can actually complete. With no bundled
        // OAuth client the Google button could only ever surface
        // "Add your Google OAuth client ID and secret first" — a message meant
        // for whoever builds Otto, shown to someone trying to use it
        // (Marcello, 2026-08-06). A missing step beats a broken one.
        if GoogleOAuth.hasBundledCredentials { s.append(.signIn) }
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
                    OnboardingPracticeView(onAdvance: advanceStep)
                case .celebrate:
                    OnboardingCelebrateView(onAdvance: advanceStep)
                case .calendar:
                    OnboardingCalendarView(onAdvance: advanceStep)
                case .signIn:
                    OnboardingSignInView(onAdvance: advanceStep)
                case .allSet:
                    OnboardingAllSetView(onFinish: completeOnboarding)
                }
            }
            .transition(stepTransition)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: stepIndex)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// The standard header: one strong line, one quiet line, consistent rhythm.
private struct OnboardingHeader: View {
    let title: String
    var subtitle: String? = nil
    var topPadding: CGFloat = 52

    var body: some View {
        VStack(spacing: 10) {
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
            Spacer().frame(height: 56)

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

            Spacer().frame(height: 30)

            VStack(spacing: 10) {
                ValueRow(icon: "checklist", tint: .blue,
                         title: "To-dos that stay out of the way",
                         detail: "Capture one in a second, from any app.")
                ValueRow(icon: "calendar", tint: .orange,
                         title: "Meetings before they start",
                         detail: "A quiet nudge, then a card with the join link.")
                ValueRow(icon: "moon.zzz", tint: .purple,
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
    let icon: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(tint.opacity(0.14)))

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

            // Layer 3: faint vignette to anchor the floating cards
            RadialGradient(
                colors: [Color.clear, Color.black.opacity(0.10)],
                center: .center,
                startRadius: 200,
                endRadius: 700
            )
        }
    }
}

// MARK: - Step Dot Indicator

struct StepDotIndicator: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: i == current ? 20 : 8, height: 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: current)
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

    private enum Stage { case awaitingShortcut, awaitingTodo }
    @State private var stage: Stage = .awaitingShortcut
    @State private var pulse = false
    @State private var showSkip = false
    @State private var done = false

    var body: some View {
        OnboardingScaffold {
            VStack(spacing: 0) {
                OnboardingHeader(
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
            // Let the row land in the notch before the window moves on.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { onAdvance() }
        }
    }
}

/// Keycaps at hero size — the shortcut is the subject of the screen, not a hint.
private struct ShortcutKeys: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 21, weight: .medium))
                    .frame(minWidth: 50, minHeight: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
                    )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(keys.joined(separator: " "))
    }
}
// MARK: - Act 2 · Celebrate (Step 6)

private struct OnboardingCelebrateView: View {
    var onAdvance: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(.green)
                .scaleEffect(appeared ? 1 : 0.5)
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: appeared)

            Text("Nice — that's it.")
                .font(.system(size: 26, weight: .bold))
                .padding(.top, 18)

            Text("That's the whole interaction. Anything you typed is already saved in your list, and the same shortcut works from any app, any time.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 60)
                .padding(.top, 10)

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
    @ObservedObject private var calendar = CalendarStore.shared
    @State private var asking = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 50)

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
                        Task { await calendar.connect(); asking = false }
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
//   * Apple is UI + the correct button, but it CANNOT complete until "Sign in
//     with Apple" is enabled on the App ID at developer.apple.com and the
//     com.apple.developer.applesignin entitlement is added. That is Marcello's
//     to do in the portal; shipping the button wired to nothing would be worse
//     than shipping it honest, so it says so on the screen.
//
// Neither one syncs anything yet — there is no Otto server. The screen claims
// only what is true: it identifies you, and it is what future sync will hang
// off. Promising "your to-dos everywhere" today would be a lie.

private struct OnboardingSignInView: View {
    var onAdvance: () -> Void
    @State private var busy = false
    @State private var error: String?
    @State private var signedInAs: String? = GoogleOAuth.shared.account

    var body: some View {
        OnboardingScaffold {
            VStack(spacing: 0) {
                OnboardingHeader(
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
                        SignInButton(provider: .google, busy: busy) { signInWithGoogle() }
                        SignInButton(provider: .apple, busy: false) { }
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
    }

    private func signInWithGoogle() {
        busy = true
        error = nil
        Task {
            do {
                try await GoogleOAuth.shared.signIn()
                signedInAs = GoogleOAuth.shared.account
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
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
                Text(busy ? "Waiting for the browser\u{2026}"
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
              ? "Needs Sign in with Apple enabled on the App ID before it can complete."
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

struct NotchMiniPreview: View {
    @State private var phase = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        Rectangle()
                            .fill(Color(NSColor.windowBackgroundColor).opacity(0.7))
                            .frame(height: 24)

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.black)
                            .frame(width: phase >= 2 ? 160 : 60, height: phase >= 2 ? 44 : 20)
                            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: phase)
                    }
                    .frame(height: 44)

                    Spacer()

                    Text(phaseLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 12)
                        .animation(.easeInOut(duration: 0.2), value: phase)
                }
            }
            .onAppear { startLoop() }
    }

    var phaseLabel: String {
        switch phase {
        case 0: return "Press \u{2325}\u{2318}N from anywhere"
        case 1: return "The notch opens"
        case 2: return "Type what needs doing"
        case 3: return "It\u{2019}s on your list"
        default: return ""
        }
    }

    func startLoop() {
        let delays: [Double] = [0, 1.2, 2.0, 3.0]
        for (i, delay) in delays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation { phase = i }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            phase = 0
            startLoop()
        }
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
