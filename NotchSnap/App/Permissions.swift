import Foundation
import AppKit
import ScreenCaptureKit

// MARK: - Permission Manager
//
// API facts (they're commonly mixed up):
//   • CGPreflightScreenCaptureAccess() — passive check, NEVER shows a prompt.
//     This is the right way to poll for status.
//   • CGRequestScreenCaptureAccess() — shows the system prompt ONCE (first
//     call ever) and, critically, REGISTERS the app in System Settings →
//     Privacy & Security → Screen Recording. Without this call the app may
//     not even appear in that list, so "open Settings and toggle it on"
//     fails because there is nothing to toggle.
//
// The smooth flow (Wispr Flow style):
//   1. User clicks Grant → we call CGRequestScreenCaptureAccess() so the
//      app is registered + the system shows its dialog with a direct
//      "Open System Settings" button.
//   2. We also deep-link to the Screen Recording pane as a fallback.
//   3. We poll with the preflight check; the instant the toggle flips we
//      show the granted state.
//   4. macOS applies the grant to a running process only after relaunch —
//      the caller offers a "Relaunch" button using `relaunchApp()`.

@MainActor
class PermissionManager: ObservableObject {
    @Published var hasScreenRecording: Bool = false
    @Published var hasAccessibility: Bool = true
    @Published var onboardingCompleted: Bool

    private var pollingTimer: Timer?

    private static let onboardingCompletedKey = "notchsnap.onboardingCompleted"

    init() {
        self.onboardingCompleted = UserDefaults.standard.bool(forKey: Self.onboardingCompletedKey)
        checkAllPermissions()
    }

    // MARK: - Check Permissions (passive — never prompts)

    func checkAllPermissions() {
        hasScreenRecording = CGPreflightScreenCaptureAccess()
    }

    var allPermissionsGranted: Bool {
        hasScreenRecording
    }

    var shouldShowOnboarding: Bool {
        // Was `&& !allPermissionsGranted`, from when onboarding existed to ask
        // for Screen Recording: a user who already had it never saw the flow.
        // Onboarding now just introduces the app, so completing it is the only
        // thing that should retire it (2026-08-06).
        !onboardingCompleted
    }

    // MARK: - Request Permissions

    /// Registers the app with TCC (so it appears in the Screen Recording
    /// list), triggers the one-time system prompt, and deep-links to the
    /// exact Settings pane. Returns immediately; observe `hasScreenRecording`.
    func requestScreenRecording() {
        // Already granted? Nothing to do.
        guard !CGPreflightScreenCaptureAccess() else {
            hasScreenRecording = true
            return
        }

        // Registers the app in the TCC database + shows the system dialog
        // (only the very first time; later calls are no-ops that return false).
        CGRequestScreenCaptureAccess()

        // Deep-link straight to the pane so the user lands on the toggle.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        startPolling()
    }

    func requestAccessibility() {
        // No-op
    }

    // MARK: - Polling (passive check)

    func startPolling() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.checkAllPermissions()
                if self.allPermissionsGranted {
                    self.stopPolling()
                }
            }
        }
    }

    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    // MARK: - Relaunch
    //
    // Screen-recording grants only apply to a freshly launched process.
    // Spawn a detached relaunch and terminate.

    static func relaunchApp() {
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }

    // MARK: - Complete Onboarding

    func completeOnboarding() {
        onboardingCompleted = true
        UserDefaults.standard.set(true, forKey: Self.onboardingCompletedKey)
        stopPolling()
    }
}
