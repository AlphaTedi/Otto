import SwiftUI
import Sparkle

// MARK: - UpdateController — in-app updates (Sparkle)
//
// NotchSnap is distributed from a website and GitHub, not the App Store, so
// nothing updates it for us. Without this, fixing a bug means asking every user
// to go find a new DMG and drag it over the old app — which in practice means
// most of them never update.
//
// How it works: the app checks a small `appcast.xml` feed for a newer version,
// and if there is one it offers to download and install it in place, then
// relaunches. The DMG is only ever the FIRST install.
//
// The part that matters for safety: every update is signed with an EdDSA key
// that exists only in Marcello's keychain, and the app carries the matching
// public key (SUPublicEDKey in Info.plist). Sparkle refuses anything that does
// not verify. So even if the GitHub account or the website were compromised, an
// attacker could not push code onto users' machines — they would need the
// private key, which never leaves his Mac and is never in the repository.

@MainActor
final class UpdateController: ObservableObject {
    static let shared = UpdateController()

    /// Whether a check is currently allowed — false while one is in flight, so
    /// the menu item and button can disable rather than queue duplicates.
    @Published private(set) var canCheck = true

    private let controller: SPUStandardUpdaterController
    private var observation: NSKeyValueObservation?

    private init() {
        // startingUpdater: true wires the scheduled background check. The
        // interval and opt-in live in Info.plist (SUScheduledCheckInterval,
        // SUEnableAutomaticChecks) so they can change without code.
        // `startingUpdater` is what schedules the background check. Off in the
        // lab: its feed is the production appcast, so a check there would offer
        // the shipped Otto as an update to the experiment. See AppBuild.
        controller = SPUStandardUpdaterController(
            startingUpdater: AppBuild.updatesEnabled,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) {
            [weak self] updater, _ in
            Task { @MainActor in self?.canCheck = updater.canCheckForUpdates }
        }
    }

    /// The explicit "Check for Updates…" path. Shows Sparkle's own UI, including
    /// "you're up to date" — an explicit check that silently does nothing reads
    /// as broken.
    func checkForUpdates() {
        guard AppBuild.updatesEnabled else { return }
        controller.checkForUpdates(nil)
    }

    /// Mirrors Sparkle's own preference, so the Settings toggle and whatever
    /// Sparkle's UI does stay in agreement.
    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            controller.updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
        }
    }

    /// Human-readable last-check time for the Settings row, so "automatic
    /// updates" is verifiable rather than a claim.
    var lastCheckDescription: String {
        guard let date = controller.updater.lastUpdateCheckDate else {
            return L10n.t("update.neverChecked")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// The running version, for display. Reads the bundle rather than a
    /// constant so it can never disagree with what Sparkle compares against.
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}
