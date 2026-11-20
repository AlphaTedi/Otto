import SwiftUI
import Sparkle

// MARK: - UpdateController — in-app updates (Sparkle)
//
// Otto is distributed from a website and GitHub, not the App Store, so
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

    /// What the notch's update banner shows (UpdateAlertCard).
    enum Phase: Equatable {
        case idle
        /// A newer version is waiting: "Otto 1.5 is ready".
        case available(version: String)
        /// Downloading; nil progress while the size is not known.
        case downloading(progress: Double?)
        case installing
    }
    @Published var phase: Phase = .idle

    /// A release worth advertising: the notch shows the media banner
    /// (DSMediaBanner) instead of the plain one. Set per release; nil for an
    /// ordinary update.
    struct Featured: Equatable {
        let title: String
        let subtitle: String
        /// A short looping clip; nil plays the built-in AI scene.
        var video: URL? = nil
    }
    @Published var featured: Featured?
    /// "Not now" on the banner: hidden until the next version.
    @Published private(set) var dismissedVersion: String?

    /// The banner shows unless the person said "not now" to this version.
    var showsBanner: Bool {
        if case .available(let version) = phase { return version != dismissedVersion }
        return phase != .idle
    }

    private let controller: SPUStandardUpdaterController
    private let bridge = UpdateBridge()
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
            updaterDelegate: bridge,
            userDriverDelegate: bridge
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

    /// Every phase change goes through here, on the banner's spring: the
    /// card reshapes and its rows cross-fade instead of jumping
    /// (Marcello, 2026-11-15).
    func move(to next: Phase) {
        guard next != phase else { return }
        withAnimation(Motion.contentHug) { phase = next }
    }

    /// The banner's Update: Sparkle downloads and installs, and the banner
    /// follows its phases (UpdateBridge) until Otto relaunches.
    func installUpdate() {
        guard AppBuild.updatesEnabled else {
            #if DEBUG || OTTO_LAB
            simulateInstall()
            #endif
            return
        }
        move(to: .downloading(progress: nil))
        controller.checkForUpdates(nil)
    }

    /// The banner's Dismiss: this version is not offered again in the notch;
    /// Settings › About still has it.
    func dismissBanner() {
        if case .available(let version) = phase {
            withAnimation(Motion.contentHug) { dismissedVersion = version }
        }
    }

    #if DEBUG || OTTO_LAB
    /// Otto Lab has no feed: Update plays the phases, so the banner can be
    /// tried end to end.
    private func simulateInstall() {
        Task { @MainActor in
            for step in 0...10 {
                move(to: .downloading(progress: Double(step) / 10))
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            move(to: .installing)
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            move(to: .idle)
        }
    }

    /// Otto Lab's dial kit: the banner in each phase, without Sparkle.
    func stage(_ phase: Phase, featured: Featured? = nil) {
        withAnimation(Motion.contentHug) {
            dismissedVersion = nil
            self.featured = featured
        }
        move(to: phase)
    }
    #endif

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

/// Sparkle's delegates, which must be NSObjects: they tell the banner what
/// Sparkle found and where it is with it.
@MainActor
private final class UpdateBridge: NSObject, SPUUpdaterDelegate, @MainActor SPUStandardUserDriverDelegate {
    private func set(_ phase: UpdateController.Phase) {
        Task { @MainActor in UpdateController.shared.move(to: phase) }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in
            // A check the banner started is already past "available".
            if case .idle = UpdateController.shared.phase {
                UpdateController.shared.move(to: .available(version: item.displayVersionString))
            }
        }
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) { set(.idle) }
    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        set(.downloading(progress: nil))
    }
    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) { set(.installing) }
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) { set(.installing) }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        Task { @MainActor in
            // Back to the offer, so Update can be pressed again.
            switch UpdateController.shared.phase {
            case .downloading, .installing: UpdateController.shared.move(to: .idle)
            default: break
            }
        }
    }

    // Scheduled checks are announced by the notch's banner, not by a window
    // popping up over whatever the person is doing (gentle reminders).
    var supportsGentleScheduledUpdateReminders: Bool { true }
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }
}
