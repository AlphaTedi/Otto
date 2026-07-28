import Foundation

// MARK: - Voice capture feature flag
//
// The voice brain-dump (VoiceTranscriber / BrainDumpParser /
// VoiceCaptureController / VoiceCaptureView) is fully implemented but
// SHELVED as of 2026-07-25 — Marcello is prioritizing other work and the
// microphone path still needs a real end-to-end test on his Mac.
//
// Everything stays compiled and reachable from tests/DebugDriver; only the
// USER-FACING entry points are gated:
//   • the mic chip in the tab row
//   • the ⇧⌘V shortcut
//
// Nothing can enter TodoPanelMode.voice while this is false, so the mic is
// never touched and the app can't crash on it.
//
// TO RE-ENABLE: flip `isEnabled` to true (or, without a rebuild, run
//   defaults write com.notchsnap.app voiceCaptureEnabled -bool true
// and relaunch). Before shipping it, re-test: mic + speech permission
// prompts, the live waveform, and the review → confirm flow.

enum VoiceFeature {
    /// Compile-time default. Flip to `true` to bring the feature back.
    private static let defaultEnabled = false

    /// Runtime override so the shelved feature can still be exercised
    /// without a code change (handy for a quick test on a capable Mac).
    static var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: "voiceCaptureEnabled") != nil {
            return UserDefaults.standard.bool(forKey: "voiceCaptureEnabled")
        }
        return defaultEnabled
    }
}
