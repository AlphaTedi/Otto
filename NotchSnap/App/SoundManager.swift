import AppKit

// MARK: - SoundManager — Single source of truth for sound effects
//
// Custom AIFF files go in Resources/Sounds/ (AIFF, 16-bit, 44.1kHz, mono).
// Until those exist, each event falls back to a macOS system sound chosen
// to match the OS's native sound language:
//   • Confirmations are soft and short (Tink / Pop).
//   • UI expansion is silent unless a custom AIFF is bundled — macOS
//     never sounds on open/close chrome by default.

final class SoundManager: @unchecked Sendable {
    static let shared = SoundManager()

    private var cache: [SoundName: NSSound] = [:]

    // Rate limiting — even if callers misbehave, the same sound never
    // fires more often than this. Prevents "machine-gun" stutter when an
    // event (e.g. mouse-move-driven collapse) retriggers rapidly.
    private var lastPlayed: [SoundName: Date] = [:]
    private let minInterval: TimeInterval = 0.25

    private init() {
        // Pre-load custom sounds from bundle
        for name in SoundName.allCases {
            if let url = Bundle.main.url(forResource: name.rawValue, withExtension: "aiff"),
               let sound = NSSound(contentsOf: url, byReference: false) {
                cache[name] = sound
            }
        }
    }

    private var isUserEnabled: Bool {
        UserDefaults.standard.object(forKey: "soundEffectsEnabled") == nil
            || UserDefaults.standard.bool(forKey: "soundEffectsEnabled")
    }

    func play(_ name: SoundName) {
        guard isUserEnabled else { return }

        // Drop plays that arrive too soon after the previous one.
        let now = Date()
        if let last = lastPlayed[name], now.timeIntervalSince(last) < minInterval {
            return
        }
        lastPlayed[name] = now

        let vol = name.volume

        // Try cached custom sound first (copy for concurrent playback)
        if let cached = cache[name], let sound = cached.copy() as? NSSound {
            sound.volume = vol
            sound.play()
            return
        }

        // Fallback to system sound (nil = intentionally silent)
        if let fallback = name.systemFallback {
            fallback.volume = vol
            fallback.play()
        }
    }

    // MARK: - Sound Names

    // Raw values match the AIFF filenames in Resources/Sounds/.
    enum SoundName: String, CaseIterable {
        case expand             = "notch_expand"
        case collapse           = "notch_collapse"
        case delete             = "item_delete"

        var volume: Float {
            switch self {
            case .expand:             return 0.18
            case .collapse:           return 0.14
            case .delete:             return 0.22
            }
        }

        // macOS system sounds as fallback while custom AIFFs don't exist.
        // Ref: /System/Library/Sounds/
        var systemFallback: NSSound? {
            switch self {
            case .expand:             return nil   // silent — haptic only
            case .collapse:           return nil   // silent — haptic only
            case .delete:             return NSSound(named: "Bottle")
            }
        }
    }
}
