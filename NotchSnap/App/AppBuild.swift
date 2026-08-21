import Foundation

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

    /// The folder under Application Support holding every store's data.
    ///
    /// Separate for the lab, and that is the entire point: an experiment that
    /// can eat your real to-dos is not one you can run on a working Tuesday.
    /// `Scripts/lab.sh --seed` copies production data across once, so the lab
    /// has realistic content to be judged against without sharing a file with
    /// the app you actually depend on.
    static var supportRoot: String { isLab ? "NotchSnapLab" : "NotchSnap" }

    /// Keychain items are scoped by service string. A separate one keeps the
    /// lab's Google tokens out of the shipped app's, so signing out of one
    /// cannot sign the other out.
    static var keychainService: String {
        isLab ? "com.notchsnap.app.lab.google" : "com.notchsnap.app.google"
    }

    /// Sparkle is OFF in the lab, and this is the single most important line
    /// in the file.
    ///
    /// The feed URL in Info.plist points at the production appcast. A lab build
    /// that checked it would be offered the shipped Otto as an "update", and
    /// installing it would silently replace the experiment with the thing the
    /// experiment exists to avoid touching — while keeping the lab's bundle id,
    /// so the two would then be indistinguishable.
    static var updatesEnabled: Bool { !isLab }
}
