# Otto — Distribution, Signing, and Auto-Update

How a build on Marcello's Mac becomes an app a stranger can download, open, and keep
updated. Written 2026-08-05, covering v1.2.0 → v1.6.3.

Everything here was learned by getting it wrong first. The failure modes in §7 are the
real content of this document — the happy path is short and the traps are not.

---

## 1. The shape of the problem

An unsigned `.app` handed to another Mac does three hostile things:

1. **Gatekeeper refuses to open it** — "cannot be opened because the developer cannot be
   verified."
2. **App Translocation** runs it from a randomized read-only copy, so no permission it is
   ever granted will persist.
3. **TCC cannot identify it**, so it never appears in System Settings → Privacy.

All three are solved by the same thing: a **Developer ID signature plus notarization**.
This is why the Apple Developer Program subscription was necessary — not to ship on the
Mac App Store, but so that a downloaded app opens by double-clicking.

Team ID: `5N7QPZ6H87` · Bundle id: `com.notchsnap.app`

> **The app was renamed NotchSnap → Otto on 2026-08-06.** The bundle id was
> deliberately NOT changed: it is the app's TCC identity (renaming it re-locks
> calendar access, which took days to recover) and the key its data directory
> hangs off. Users never see it. The Xcode target, scheme and source folders
> are also still called NotchSnap — only `PRODUCT_NAME` changed, so the shipped
> bundle is `Otto.app`.

---

## 2. Configuration — `Config/Local.xcconfig`

Gitignored; `Config/Local.xcconfig.example` is the committed template. Defines:

| Key | Purpose |
|---|---|
| `CODE_SIGN_IDENTITY` | `Developer ID Application: Marcello Zanetta (5N7QPZ6H87)` |
| `DEVELOPMENT_TEAM` | `5N7QPZ6H87` |
| `NOTARY_PROFILE` | `NotchSnap` — the keychain item holding the notary credential |
| `ENABLE_HARDENED_RUNTIME[config=Release]` | `YES` — required for notarization |
| `CODE_SIGN_INJECT_BASE_ENTITLEMENTS[config=Release]` | `NO` — see §7.4 |
| `GoogleOAuthClientID` / `GoogleOAuthClientSecret` | shipped OAuth credential |

The notary credential is created **once**, by Marcello, and never by the agent:

```bash
xcrun notarytool store-credentials "NotchSnap" \
  --apple-id marcello.zanetta1@gmail.com --team-id 5N7QPZ6H87 \
  --password APP-SPECIFIC-PASSWORD
```

**An app-specific password is a credential. It is generated at appleid.apple.com, typed
by Marcello into his own terminal, and never pasted into a chat.** One was pasted once
and had to be revoked.

> **xcconfig is only a base.** A value hardcoded on the *target* silently overrides it.
> `CODE_SIGN_IDENTITY = "-"` sat on the target for several releases and quietly produced
> ad-hoc builds while the xcconfig said otherwise. When signing looks configured but
> isn't applied, check the target before doubting the xcconfig.

---

## 3. Entitlements — `NotchSnap/Resources/NotchSnap.entitlements`

```xml
com.apple.security.app-sandbox                        false
com.apple.security.device.audio-input                 true
com.apple.security.files.downloads.read-write         true
com.apple.security.files.user-selected.read-write     true
com.apple.security.personal-information.addressbook   true
com.apple.security.personal-information.calendars     true
```

**This file is load-bearing in a way that is easy to miss.** Hardened Runtime gates
access to calendars, contacts, microphone and camera behind entitlements. Without the
matching entitlement, macOS refuses the resource **with no prompt and no entry in the
Privacy list** — behaviour indistinguishable from the user having denied it. See §7.1.

Not sandboxed, deliberately: it keeps `~/Library/Application Support/NotchSnap/` data
alive across reinstalls.

---

## 4. `Scripts/release.sh` — the whole pipeline

One command: `bash Scripts/release.sh`. Version comes from the **git tag**, so tag first.

| Step | What it does | Why it exists |
|---|---|---|
| 0 | Preconditions: identity, team, notary profile, certificate present | Fails in 2s instead of 6min |
| — | Version from `git describe`, build number from `git rev-list --count HEAD` | Sparkle compares versions; a constant version means no update ever appears |
| 1 | `xcodebuild` Release | |
| 1b | Re-sign Sparkle's nested helpers **inside-out** | §7.3 |
| 2 | Verify: team, Hardened Runtime, no `get-task-allow`, **required entitlements present** | Catches §7.1 and §7.4 before Apple does |
| 3 | `notarytool submit --wait`, **abort unless `status: Accepted`** | §7.5 |
| 4 | `stapler staple` | Opens without a network round trip |
| 5 | `spctl -a -vvv -t exec` | What a downloader actually gets |
| 6–7 | Build `.dmg`, sign it, notarize it **separately** | Notarizing the app does not cover its container |
| 8 | `gh release create`/`upload` | §7.6 |
| 9 | `generate_appcast` (EdDSA-signed), copy to `appcast.xml` | |
| 10 | `curl` the feed enclosure, **fail unless HTTP 200** | An appcast that 404s is worse than none |

Still manual afterwards: `git add appcast.xml && git commit && git push`. The script
prints the command but does not run it.

---

## 5. Auto-update — Sparkle

- Sparkle 2.9.5 via SPM; `UpdateController` in `NotchSnap/App/`.
- Feed: `SUFeedURL` → `https://raw.githubusercontent.com/AlphaTedi/Screenshot_app/main/appcast.xml`
- `SUPublicEDKey` = `kcZvheYIHq5NOS3hoB4As0+TCzkyBxNRXn+BSRFJnA8=`; the matching private
  key lives in Marcello's keychain. The app **refuses any update that does not verify**,
  so a compromised host still cannot push code to users.
- `SUEnableAutomaticChecks` true — the app polls, shows an in-app prompt, downloads and
  installs. This is what "download the DMG once, then update from inside the app" means.

**The feed is served from `main`, not from the release.** Pushing `appcast.xml` is what
actually ships an update to installed copies; creating the GitHub release only makes the
file downloadable.

---

## 6. CI — `.github/workflows/build-release.yml`

Rewritten to be **verification only**: it builds the committed project and creates no
releases. It selects Xcode 26.2 explicitly and writes a stub `Config/Local.xcconfig`.

It used to create releases too, which is the single most expensive bug in this document
— see §7.7.

---

## 7. Failure modes — each one cost real time

### 7.1 Hardened Runtime without the calendar entitlement (the big one)

**Symptom:** "Calendar access was denied." on every machine. No permission prompt ever
appeared. NotchSnap never showed up in System Settings → Privacy → Calendars. Granting
Full Access, running `tccutil reset Calendar com.notchsnap.app`, deleting duplicate app
copies, and rebuilding the `EKEventStore` all changed **nothing**.

**Cause:** Hardened Runtime was enabled in v1.4.0 (it is mandatory for notarization) and
only the microphone entitlement was declared. macOS then refuses EventKit silently.

**Why it hid for five releases:** Debug builds have no Hardened Runtime, so calendar
access kept working perfectly in Xcode. It was dead in every *signed* build from v1.4.0
to v1.6.2 inclusive. Fixed in **v1.6.3**.

**The lesson that generalizes:** *"denied" and "never asked" look identical from the
user's side.* Distinguish them by checking whether the app appears in the Privacy list at
all — an app that was denied is listed with its switch off; an app that could never ask
is absent entirely. That single observation would have found this in minutes.

`release.sh` now fails the build if any required entitlement is missing from the signed
binary, so this specific class of bug cannot ship again.

### 7.2 TCC identity is the code signature

Re-signing an app changes its identity, so **every previously granted permission is
forgotten**. Launching the binary directly from a shell instead of `open`-ing the `.app`
bundle also yields a different identity and is denied. Two consequences: test permissions
from the real bundle, and expect a fresh prompt after each signing change.

### 7.3 Sparkle's nested helpers ship pre-signed

Xcode signs the app and the framework but **not** `Updater.app`, `Autoupdate`, and the
two XPC services inside `Sparkle.framework`. Apple rejected the archive with "not signed
with a valid Developer ID certificate" once per architecture.

They must be signed **inside-out**: each nested item, then the framework, then the app.
Signing an outer bundle first is undone the moment anything inside it changes.

### 7.4 `get-task-allow` is injected by Xcode and rejected by notarization

Fixed with `CODE_SIGN_INJECT_BASE_ENTITLEMENTS[config=Release] = NO`, and guarded in
release.sh.

### 7.5 `grep -q` under `set -o pipefail` fails in the dangerous direction

```bash
codesign -dv "$APP" 2>&1 | grep -q "runtime"   # WRONG
```

`grep -q` exits the instant it matches, `codesign` takes SIGPIPE and returns non-zero,
and `pipefail` turns that into a failed check. So the guard **went quiet in precisely the
case it existed to catch** — a correct build reported "Hardened Runtime is OFF", and the
`get-task-allow` check passed silently whenever the entitlement was actually present.

Three instances existed. All replaced with capture-then-`case`:

```bash
SIGINFO=$(codesign -dv --verbose=2 "$APP" 2>&1 || true)
case "$SIGINFO" in *"(runtime)"*) ;; *) exit 1 ;; esac
```

### 7.6 Producing an artifact is not releasing it

release.sh once *printed advice* about uploading instead of running `gh release create`.
Result: an appcast published pointing at a release that did not exist. Every installed
copy would have been offered an update it could not download. It now creates the release,
and verifies the enclosure returns 200 before finishing.

### 7.7 CI overwriting signed releases

The old workflow built **unsigned** and uploaded to the same tag, silently replacing the
signed, notarized binary that release.sh had just published. This is the source of the
"I downloaded it and it's still broken" mystery that ran for several rounds: the fix was
genuinely published, then overwritten minutes later by CI.

CI also used Xcode 16.4 against a project needing 26.2, hidden by a `SWIFT_VERSION=5.0`
override.

### 7.8 Duplicate keys in a Swift dictionary literal crash at launch

v1.6.0 crashed on every launch. Eight duplicate keys in the English `L10n` dictionary —
Italian `update.*` strings pasted into the English block. **Swift traps at runtime, not
compile time.** Nothing in the build output hinted at it. Verify both dictionaries
construct before shipping a localization change.

### 7.9 A stale app copy poisons the diagnosis

`~/Downloads/NotchSnap.app` — bundle id `NotchSnap`, v1.0, unsigned — created a Privacy
entry named "NotchSnap" that had nothing to do with the running app. Hours went into
toggling a switch that governed a different binary. `Scripts/diagnose-calendar.sh` now
reports the **real** bundle id from the signature.

---

## 8. Release checklist

```bash
git tag -a v1.6.4 -m "..." && git push origin v1.6.4
bash Scripts/release.sh
git add appcast.xml && git commit -m "Release 1.6.4 to the update feed" && git push
```

Then verify as a stranger would: download the DMG from the Releases page, and check
`spctl -a -vvv -t open --context context:primary-signature Otto.dmg` reports
`accepted` / `Notarized Developer ID`.

---

## 9. Open threads

- release.sh is not idempotent against partial publishes — a 422 once left v1.6.1 tagged
  but unreleased, with a feed pointing at nothing.
- `appcast.xml` commit is still manual.
- The notary credential vanished from the keychain once between v1.6.2 and v1.6.3, then
  worked again unprompted. Cause unknown. If `notarytool` reports "No Keychain password
  item found", re-running `store-credentials` is the fix.
