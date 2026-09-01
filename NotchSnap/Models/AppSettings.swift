import Foundation
import AppKit

// MARK: - Enums

enum NotchTrigger: String, Codable, CaseIterable {
    case hover
    case click
    case never
}

enum FileFormat: String, Codable, CaseIterable {
    case png
    case jpeg
}

enum CaptureMode: String, Codable, CaseIterable {
    case area
    case window
    case fullscreen
}

/// Which shape the notch takes when it opens.
///
/// Two designs are kept side by side on purpose. `.panels` is the current
/// one: the notch stays a small object and the blocks float below it with
/// real gaps, so the desktop shows through. `.container` is the design that
/// preceded it — the notch itself grows downward and the content lives
/// INSIDE the silhouette, one object rather than three.
///
/// Everything that measures or hit-tests the expanded notch has to ask which
/// of the two is up, because the two draw to different rectangles: the
/// column's own measured height versus the grown silhouette.
enum NotchLayout: String, Codable, CaseIterable {
    case panels
    case container

    var label: String {
        switch self {
        case .panels:    return "Floating panels"
        case .container: return "Notch container"
        }
    }

    var summary: String {
        switch self {
        case .panels:
            return "The notch stays small and the meeting and to-do blocks hang below it as separate cards."
        case .container:
            return "The notch itself grows downward and holds the content inside the silhouette."
        }
    }
}

enum AppTheme: String, Codable, CaseIterable {
    case system
    case light
    case dark

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
}

// MARK: - KeyCombo

struct KeyCombo: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: CGEventFlags

    enum CodingKeys: String, CodingKey {
        case keyCode, modifierRaw
    }

    init(keyCode: UInt16, modifiers: CGEventFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        let raw = try container.decode(UInt64.self, forKey: .modifierRaw)
        modifiers = CGEventFlags(rawValue: raw)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifiers.rawValue, forKey: .modifierRaw)
    }

    static func == (lhs: KeyCombo, rhs: KeyCombo) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifiers.rawValue == rhs.modifiers.rawValue
    }
}

// MARK: - AppSettings

struct AppSettings: Codable {
    // Hotkeys (Cmd+Shift+1/2/3/Space)
    var captureHotkey = KeyCombo(keyCode: 18, modifiers: CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue))
    var windowHotkey = KeyCombo(keyCode: 19, modifiers: CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue))
    var fullscreenHotkey = KeyCombo(keyCode: 20, modifiers: CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue))
    var repeatHotkey = KeyCombo(keyCode: 49, modifiers: CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue))

    // Capture
    var defaultCaptureMode: CaptureMode = .area
    var playSound: Bool = true
    var windowShadow: Bool = false

    // Notch
    var notchTrigger: NotchTrigger = .hover
    var hoverDelayMs: Int = 0
    var autoCollapseSeconds: Int? = 5
    var showBadgeCounter: Bool = true

    // Save
    var autoCopyToClipboard: Bool = true
    var autoSaveFile: Bool = false
    var saveDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/NotchSnap")
    var fileFormat: FileFormat = .png
    var jpegQuality: Double = 0.85

    // Gallery
    var maxSessionScreenshots: Int = 20
    var clearSessionOnLaunch: Bool = false

    // General
    var launchAtLogin: Bool = false
    var showInDock: Bool = false
    var appTheme: AppTheme = .system

    // Storage — the user-visible Markdown home of every to-do and note.
    // A plain URL, no security-scoped bookmark: the app is not sandboxed,
    // same as saveDirectory above. See MarkdownVault.
    var vaultDirectory: URL = MarkdownVault.defaultDirectory

    init() {}

    // Hand-rolled, decodeIfPresent for EVERY field — the same forward-compat
    // hook TodoItem has. The synthesized decoder throws on any missing key,
    // and `load()` answers a throw with factory defaults: with synthesized
    // decoding, ADDING a settings field silently reset every setting a user
    // had (hotkeys, save folder, theme) on their first launch of the new
    // version. Adding a field now means adding one line here.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        captureHotkey = (try? c.decodeIfPresent(KeyCombo.self, forKey: .captureHotkey)) ?? defaults.captureHotkey
        windowHotkey = (try? c.decodeIfPresent(KeyCombo.self, forKey: .windowHotkey)) ?? defaults.windowHotkey
        fullscreenHotkey = (try? c.decodeIfPresent(KeyCombo.self, forKey: .fullscreenHotkey)) ?? defaults.fullscreenHotkey
        repeatHotkey = (try? c.decodeIfPresent(KeyCombo.self, forKey: .repeatHotkey)) ?? defaults.repeatHotkey
        defaultCaptureMode = (try? c.decodeIfPresent(CaptureMode.self, forKey: .defaultCaptureMode)) ?? defaults.defaultCaptureMode
        playSound = (try? c.decodeIfPresent(Bool.self, forKey: .playSound)) ?? defaults.playSound
        windowShadow = (try? c.decodeIfPresent(Bool.self, forKey: .windowShadow)) ?? defaults.windowShadow
        notchTrigger = (try? c.decodeIfPresent(NotchTrigger.self, forKey: .notchTrigger)) ?? defaults.notchTrigger
        hoverDelayMs = (try? c.decodeIfPresent(Int.self, forKey: .hoverDelayMs)) ?? defaults.hoverDelayMs
        autoCollapseSeconds = (try? c.decodeIfPresent(Int.self, forKey: .autoCollapseSeconds)) ?? defaults.autoCollapseSeconds
        showBadgeCounter = (try? c.decodeIfPresent(Bool.self, forKey: .showBadgeCounter)) ?? defaults.showBadgeCounter
        autoCopyToClipboard = (try? c.decodeIfPresent(Bool.self, forKey: .autoCopyToClipboard)) ?? defaults.autoCopyToClipboard
        autoSaveFile = (try? c.decodeIfPresent(Bool.self, forKey: .autoSaveFile)) ?? defaults.autoSaveFile
        saveDirectory = (try? c.decodeIfPresent(URL.self, forKey: .saveDirectory)) ?? defaults.saveDirectory
        fileFormat = (try? c.decodeIfPresent(FileFormat.self, forKey: .fileFormat)) ?? defaults.fileFormat
        jpegQuality = (try? c.decodeIfPresent(Double.self, forKey: .jpegQuality)) ?? defaults.jpegQuality
        maxSessionScreenshots = (try? c.decodeIfPresent(Int.self, forKey: .maxSessionScreenshots)) ?? defaults.maxSessionScreenshots
        clearSessionOnLaunch = (try? c.decodeIfPresent(Bool.self, forKey: .clearSessionOnLaunch)) ?? defaults.clearSessionOnLaunch
        launchAtLogin = (try? c.decodeIfPresent(Bool.self, forKey: .launchAtLogin)) ?? defaults.launchAtLogin
        showInDock = (try? c.decodeIfPresent(Bool.self, forKey: .showInDock)) ?? defaults.showInDock
        appTheme = (try? c.decodeIfPresent(AppTheme.self, forKey: .appTheme)) ?? defaults.appTheme
        vaultDirectory = (try? c.decodeIfPresent(URL.self, forKey: .vaultDirectory)) ?? defaults.vaultDirectory
    }

    // MARK: Persistence

    private static let storageKey = "notchsnap.settings"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
