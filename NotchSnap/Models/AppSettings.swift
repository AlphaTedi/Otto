import Foundation
import AppKit

// MARK: - Enums

enum NotchTrigger: String, Codable, CaseIterable {
    case hover
    case click
    case never
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

// MARK: - AppSettings

struct AppSettings: Codable {
    // Notch
    var notchTrigger: NotchTrigger = .hover
    var hoverDelayMs: Int = 0
    var autoCollapseSeconds: Int? = 5

    // General
    var launchAtLogin: Bool = false
    var showInDock: Bool = false
    var appTheme: AppTheme = .system
    /// Anonymous usage data (docs/TELEMETRY.md). nil = never asked; the
    /// onboarding or a one-time panel card asks. Opt-in: nothing is sent
    /// unless this is `.granted`.
    var analyticsConsent: AnalyticsConsent? = nil

    // Storage — Markdown defaults to Application Support. Users can choose a
    // more visible folder in Settings; see MarkdownVault.
    var vaultDirectory: URL = MarkdownVault.defaultDirectory

    init() {}

    // Hand-rolled, decodeIfPresent for EVERY field — the same forward-compat
    // hook TodoItem has. The synthesized decoder throws on any missing key,
    // and `load()` answers a throw with factory defaults: with synthesized
    // decoding, ADDING a settings field silently reset every setting a user
    // had (theme, notch behaviour) on their first launch of the new
    // version. Adding a field now means adding one line here.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        notchTrigger = (try? c.decodeIfPresent(NotchTrigger.self, forKey: .notchTrigger)) ?? defaults.notchTrigger
        hoverDelayMs = (try? c.decodeIfPresent(Int.self, forKey: .hoverDelayMs)) ?? defaults.hoverDelayMs
        autoCollapseSeconds = (try? c.decodeIfPresent(Int.self, forKey: .autoCollapseSeconds)) ?? defaults.autoCollapseSeconds
        launchAtLogin = (try? c.decodeIfPresent(Bool.self, forKey: .launchAtLogin)) ?? defaults.launchAtLogin
        showInDock = (try? c.decodeIfPresent(Bool.self, forKey: .showInDock)) ?? defaults.showInDock
        appTheme = (try? c.decodeIfPresent(AppTheme.self, forKey: .appTheme)) ?? defaults.appTheme
        analyticsConsent = (try? c.decodeIfPresent(AnalyticsConsent.self, forKey: .analyticsConsent)) ?? nil
        let savedVaultDirectory = (try? c.decodeIfPresent(URL.self, forKey: .vaultDirectory)) ?? nil
        // Older versions used ~/Documents/Otto implicitly, prompting for
        // Documents access during startup exports. Redirect only that default;
        // preserve any folder the user explicitly selected.
        vaultDirectory = savedVaultDirectory == MarkdownVault.legacyDefaultDirectory
            ? defaults.vaultDirectory
            : (savedVaultDirectory ?? defaults.vaultDirectory)
    }

    // MARK: Persistence

    private static let storageKey = "notchsnap.settings"

    private struct StoredVaultLocation: Decodable {
        let vaultDirectory: URL?
    }

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        // Persist the redirected default. Debug builds from other workspaces
        // share this preference domain; without saving it, an older build
        // would continue opening Documents and blocking at the TCC prompt.
        if (try? JSONDecoder().decode(StoredVaultLocation.self, from: data))?.vaultDirectory
            == MarkdownVault.legacyDefaultDirectory {
            settings.save()
        }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
