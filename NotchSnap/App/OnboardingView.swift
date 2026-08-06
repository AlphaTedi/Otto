import SwiftUI
import ScreenCaptureKit

// MARK: - OnboardingFlowView — 3-step onboarding (Welcome → Permissions → All Set)

struct OnboardingFlowView: View {
    @State private var currentStep = 0
    @AppStorage("onboardingVersion") var onboardingVersion: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let totalSteps = 3

    var body: some View {
        ZStack {
            // Window-wide frosted glass — wallpaper bleeds through with depth.
            FrostedGlassBackground()
                .ignoresSafeArea()

            Group {
                switch currentStep {
                case 0:
                    OnboardingWelcomeView(onAdvance: advanceStep)
                        .transition(stepTransition)
                case 1:
                    OnboardingPermissionsView(onContinue: advanceStep)
                        .transition(stepTransition)
                default:
                    OnboardingAllSetView(onFinish: completeOnboarding)
                        .transition(stepTransition)
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: currentStep)
        }
        .frame(width: 600, height: 540)
        .overlay(alignment: .bottom) {
            StepDotIndicator(current: currentStep, total: totalSteps)
                .padding(.bottom, 14)
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
        withAnimation { currentStep += 1 }
    }

    func completeOnboarding() {
        SoundManager.shared.play(.onboardingComplete)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        onboardingVersion = 1
        OnboardingWindowController.dismiss()
        // Warm the capture cache now that permission may have been granted
        CaptureManager.shared.warmContentCache()
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
            Image(systemName: "camera.viewfinder")
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

            Text("Your screenshots, always within reach of the notch.")
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

// MARK: - Permissions View (Step 2)

struct OnboardingPermissionsView: View {
    var onContinue: () -> Void
    @State private var screenRecordingGranted = false
    @State private var hasAskedOnce = false
    @State private var pollTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            Text("Set up Otto")
                .font(.system(size: 28, weight: .bold))
                .padding(.top, 40)

            Text("Grant permissions to use all features.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
                .padding(.horizontal, 48)

            Spacer().frame(height: 32)

            // Permission card
            VStack(spacing: 12) {
                PermissionCard(
                    icon: "camera.viewfinder",
                    iconColor: .blue,
                    title: "Screen Recording",
                    description: screenRecordingGranted
                        ? "You're all set. Otto can capture screenshots."
                        : "Needed to capture screenshots. We never record or save your screen.",
                    isGranted: screenRecordingGranted,
                    onGrant: requestScreenRecording
                )

                if hasAskedOnce && !screenRecordingGranted {
                    Text("Flip the Otto toggle in System Settings — this window updates by itself.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            // Footer buttons
            VStack(spacing: 10) {
                Button(action: onContinue) {
                    Text(screenRecordingGranted ? "Continue \u{2192}" : "Continue anyway \u{2192}")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [])
                .padding(.horizontal, 48)

                if !screenRecordingGranted {
                    Button("Skip for now") { onContinue() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))
                }
            }
            .padding(.bottom, 36)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: screenRecordingGranted)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: hasAskedOnce)
        .onAppear {
            checkScreenRecording()
            startPolling()
        }
        .onDisappear {
            pollTimer?.invalidate()
            pollTimer = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // User came back from System Settings — re-check immediately.
            checkScreenRecording()
        }
    }

    /// The Wispr-style grant flow:
    /// 1. CGRequestScreenCaptureAccess() registers Otto in the Screen
    ///    Recording list (without this the toggle doesn't exist to flip!)
    ///    and shows the system dialog the very first time.
    /// 2. Deep-link to the exact Settings pane as well, so the user lands
    ///    on the right screen even if they dismiss the system dialog.
    /// 3. The poll below picks up the grant and flips the card live.
    private func requestScreenRecording() {
        hasAskedOnce = true
        CGRequestScreenCaptureAccess()
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        )
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in checkScreenRecording() }
        }
    }

    private func checkScreenRecording() {
        // CGPreflightScreenCaptureAccess is the passive check — instant,
        // synchronous, and never shows a prompt.
        let granted = CGPreflightScreenCaptureAccess()
        if granted && !screenRecordingGranted {
            screenRecordingGranted = true
            pollTimer?.invalidate()
            pollTimer = nil
            SoundManager.shared.play(.permissionGranted)
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
}

// MARK: - Permission Card

struct PermissionCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let isGranted: Bool
    let onGrant: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: isGranted ? "checkmark" : icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isGranted ? .green : iconColor)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isGranted)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 22))
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button("Grant") { onGrant() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(16)
        .background(GlassTile(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isGranted ? Color.green.opacity(0.45) : Color.white.opacity(0.10),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isGranted)
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
        case 0: return "Press \u{2303}\u{21E7}4 to capture"
        case 1: return "Screenshot captured"
        case 2: return "It appears in the notch"
        case 3: return "Drag it anywhere"
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

// MARK: - All Set View (Step 3) — How to use Otto

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

            Text("You're all set!")
                .font(.system(size: 28, weight: .bold))
                .opacity(headerAppeared ? 1 : 0)
                .offset(y: headerAppeared ? 0 : 8)
                .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.18), value: headerAppeared)

            Text("Here's how to make the most of Otto.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .opacity(headerAppeared ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(0.28), value: headerAppeared)

            Spacer().frame(height: 22)

            VStack(spacing: 10) {
                AllSetTip(icon: "selection.pin.in.out", iconTint: .blue,
                          title: "Capture an area",
                          detail: "Press \u{2303}\u{21E7}4 anywhere on macOS.",
                          shortcut: "\u{2303}\u{21E7}4")
                AllSetTip(icon: "rectangle.dashed.badge.record", iconTint: .purple,
                          title: "Capture & edit",
                          detail: "Open the editor with annotations & OCR.",
                          shortcut: "\u{2303}\u{21E7}5")
                AllSetTip(icon: "display", iconTint: .orange,
                          title: "Full screen",
                          detail: "Capture the entire display in one shot.",
                          shortcut: "\u{2303}\u{21E7}3")
                AllSetTip(icon: "macbook", iconTint: .pink,
                          title: "Reach the notch",
                          detail: "Hover the notch to browse, drag thumbnails out, or press Space to Quick Look.",
                          shortcut: nil)
            }
            .padding(.horizontal, 32)
            .opacity(tipsAppeared ? 1 : 0)
            .offset(y: tipsAppeared ? 0 : 14)
            .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.35), value: tipsAppeared)

            Spacer()

            Button(action: onFinish) {
                Text("Start using Otto")
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
