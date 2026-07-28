import Foundation

// MARK: - LaunchIntegrity — why a permission prompt never appeared
//
// TCC (the privacy system) identifies an app by its CODE SIGNATURE, not its
// name or path. NotchSnap is currently ad-hoc signed — no Developer ID, no
// Team ID, and a hash that changes on every rebuild. On the Mac it was built
// on that is fine: the bundle sits in a stable location and macOS lets it ask.
//
// Copy that same app to another Mac and it breaks, in a way that looks like a
// bug in our code but isn't:
//
//   1. Downloading sets com.apple.quarantine on the bundle.
//   2. Launching a quarantined, non-Developer-ID app from Downloads triggers
//      APP TRANSLOCATION — macOS runs it from a randomized read-only mount
//      under /private/var/folders/…/AppTranslocation/… instead of its real
//      path.
//   3. TCC cannot pin a stable identity to that, so the calendar request is
//      refused outright. No prompt appears, and the app never shows up in
//      System Settings › Privacy & Security › Calendars.
//
// The result is an app reporting "access was denied" while pointing the user
// at a list it isn't in — which is a dead end. This type detects the three
// conditions so the UI can say what is actually wrong.
//
// The real fix is signing with a Developer ID certificate and notarizing;
// none of this code is a substitute for that.

enum LaunchIntegrity {
    /// macOS is running us from a randomized read-only copy, so nothing we do
    /// can persist — not permissions, not preferences tied to the bundle.
    static var isTranslocated: Bool {
        Bundle.main.bundleURL.path.contains("/AppTranslocation/")
    }

    /// The bundle still carries the download quarantine flag.
    static var isQuarantined: Bool {
        guard let values = try? Bundle.main.bundleURL.resourceValues(
            forKeys: [.quarantinePropertiesKey]
        ) else { return false }
        return values.quarantineProperties != nil
    }

    /// True when the bundle carries an ad-hoc signature — no stable identity
    /// for TCC to pin a permission grant to.
    ///
    /// This tests the CodeDirectory's adhoc FLAG, not the absence of a Team ID.
    /// Those are not the same thing and the difference matters: Apple's own
    /// binaries (Safari, Finder) have no teamid either, because they are signed
    /// by the platform identity rather than a developer team. Keying off teamid
    /// reported every Apple app as ad-hoc.
    static var isAdHocSigned: Bool {
        // kSecCodeSignatureAdhoc from <Security/CSCommon.h>. The enum is not
        // bridged into Swift, so the value is spelled out here.
        let adhocFlag: UInt32 = 0x0002

        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess,
              let code else { return false }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation),
                                            &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let flags = dict["flags"] as? UInt32 else {
            return true   // unreadable signature: treat as unidentified
        }
        return flags & adhocFlag != 0
    }

    /// A specific, actionable explanation, or nil when nothing is wrong with
    /// how we were launched (in which case a denial really is just a denial).
    static func permissionBlockReason() -> String? {
        if isTranslocated {
            return L10n.t("integrity.translocated")
        }
        if isQuarantined && isAdHocSigned {
            return L10n.t("integrity.quarantined")
        }
        return nil
    }
}
