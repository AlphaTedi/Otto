import AppKit

// MARK: - AppBuild — which build this is, and everything that must differ
//
// The lab build exists so a radical UI change can be lived with for days
// without risking the shipped app or the real to-do list (Marcello,
// 2026-08-19). It is the SAME source tree and the SAME Xcode target, built by
// `Scripts/lab.sh`, which flips the OTTO_LAB compilation condition and renames
// the product.
//
// Deliberately not a duplicated target. A second target is a second thing to
// keep in sync — new files get added to one and not the other, build settings
// drift, and the experiment stops being a fair test of the real app. One
// target with one switch cannot drift.
//
// Everything the two builds must NOT share is listed here, in one place, so
// that adding a new store means adding one line rather than remembering four.

enum AppBuild {
    #if OTTO_LAB
    static let isLab = true
    #else
    static let isLab = false
    #endif

    /// Human-readable, for anywhere the build has to identify itself.
    static var displayName: String { isLab ? "Otto Lab" : "Otto" }

    /// ~/Library/Application Support/Otto — the folder holding every store's
    /// data (to-dos, notes, the Markdown vault, telemetry and feedback queues).
    ///
    /// Separate for the lab, and that is the entire point: an experiment that
    /// can eat your real to-dos is not one you can run on a working Tuesday.
    /// `Scripts/lab.sh --seed` copies production data across once, so the lab
    /// has realistic content to be judged against without sharing a file with
    /// the app you actually depend on.
    ///
    /// The first read moves the folder over from its pre-Otto name, before any
    /// store has opened a file in it (see `adoptLegacySupportFolder`).
    nonisolated static let supportDirectory: URL = {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let current = base.appendingPathComponent(isLab ? "Otto Lab" : "Otto", isDirectory: true)
        let legacy = base.appendingPathComponent(legacySupportRoot, isDirectory: true)
        guard fm.fileExists(atPath: legacy.path) else { return current }
        // Another copy still running (an older build, or the installed app
        // beside a Debug build) has its files open in the old folder. Moving
        // it out from under that copy would split the data in two, so this
        // run uses the folder where it is; a launch that runs alone moves it.
        if otherInstanceIsRunning {
            return fm.fileExists(atPath: current.path) ? current : legacy
        }
        adoptLegacySupportFolder(legacy, into: current)
        return current
    }()

    private nonisolated static var otherInstanceIsRunning: Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .contains { $0.processIdentifier != me && !$0.isTerminated }
    }

    /// The folder's name before the app was called Otto. Read once, to move
    /// an upgraded install's data across; nothing is ever written there.
    private nonisolated static var legacySupportRoot: String { isLab ? "NotchSnapLab" : "NotchSnap" }

    /// Moves the pre-Otto data folder to its new name. A plain rename when the
    /// new folder does not exist yet (the normal upgrade); otherwise item by
    /// item, never overwriting anything already in the new folder, so running
    /// an old and a new build side by side cannot lose a file either way.
    private nonisolated static func adoptLegacySupportFolder(_ legacy: URL, into current: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacy.path) else { return }
        guard fm.fileExists(atPath: current.path) else {
            try? fm.moveItem(at: legacy, to: current)
            return
        }
        let items = (try? fm.contentsOfDirectory(atPath: legacy.path)) ?? []
        for name in items where !fm.fileExists(atPath: current.appendingPathComponent(name).path) {
            try? fm.moveItem(at: legacy.appendingPathComponent(name),
                             to: current.appendingPathComponent(name))
        }
        if (try? fm.contentsOfDirectory(atPath: legacy.path))?.isEmpty == true {
            try? fm.removeItem(at: legacy)
        }
    }

    /// A stored path that pointed inside the pre-Otto folder, rewritten to the
    /// same place in `supportDirectory`. Settings kept the vault folder as an
    /// absolute URL, which the move would otherwise leave pointing at nothing.
    nonisolated static func relocatedFromLegacySupport(_ url: URL) -> URL {
        let legacy = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(legacySupportRoot, isDirectory: true).standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path == legacy || path.hasPrefix(legacy + "/") else { return url }
        return URL(fileURLWithPath: supportDirectory.standardizedFileURL.path + path.dropFirst(legacy.count),
                   isDirectory: url.hasDirectoryPath)
    }

    /// Previous default folder name for the Markdown storage folder under
    /// ~/Documents, retained to recognize that implicit default on upgrade.
    static var vaultFolderName: String { isLab ? "Otto Lab" : "Otto" }

    /// Sparkle is OFF in the lab, and this is the single most important line
    /// in the file.
    ///
    /// The feed URL in Info.plist points at the production appcast. A lab build
    /// that checked it would be offered the shipped Otto as an "update", and
    /// installing it would silently replace the experiment with the thing the
    /// experiment exists to avoid touching — while keeping the lab's bundle id,
    /// so the two would then be indistinguishable.
    static var updatesEnabled: Bool { !isLab }

    /// Usage data never leaves a lab build: its numbers would be one person
    /// testing experiments, mixed in with everyone's real use.
    static var analyticsEnabled: Bool { !isLab }
}
