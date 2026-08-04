#!/bin/bash
# Build, sign, notarize and staple NotchSnap for distribution.
#
#   bash Scripts/release.sh
#
# Produces build/dist/NotchSnap.zip — the thing you put on a website. Someone
# downloads it, double-clicks, and it opens: no Terminal, no xattr, no
# Gatekeeper warning.
#
# Requires Config/Local.xcconfig to define CODE_SIGN_IDENTITY, DEVELOPMENT_TEAM
# and NOTARY_PROFILE (see Local.xcconfig.example). Without them this stops
# early and tells you what is missing rather than shipping something that
# fails on the user's Mac — which is exactly how the ad-hoc builds went wrong.

set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="Config/Local.xcconfig"
# Scoped to its own directory: `build/` already holds artifacts from earlier
# work, and this script deletes its output directory on every run.
OUT="build/dist"
APP="$OUT/Release/NotchSnap.app"

read_setting() {   # read_setting KEY -> value, ignoring commented-out lines
    [ -f "$CONFIG" ] || return 0
    grep -E "^[[:space:]]*$1[[:space:]]*=" "$CONFIG" 2>/dev/null \
        | tail -1 | sed "s/^[^=]*=//" | xargs 2>/dev/null || true
}

IDENTITY=$(read_setting CODE_SIGN_IDENTITY)
TEAM=$(read_setting DEVELOPMENT_TEAM)
PROFILE=$(read_setting NOTARY_PROFILE)

echo "NotchSnap release build"
echo "======================="

# --- Preconditions ---------------------------------------------------------
MISSING=0
if [ -z "$IDENTITY" ] || [ "$IDENTITY" = "-" ]; then
    echo "  CODE_SIGN_IDENTITY is not set in $CONFIG"
    echo "     Needs the Apple Developer Program. Find yours with:"
    echo "       security find-identity -v -p codesigning"
    MISSING=1
fi
if [ -z "$TEAM" ]; then
    echo "  DEVELOPMENT_TEAM is not set in $CONFIG (the 10-character team id)"
    MISSING=1
fi
if [ -z "$PROFILE" ]; then
    echo "  NOTARY_PROFILE is not set in $CONFIG. Create it once with:"
    echo "       xcrun notarytool store-credentials \"NotchSnap\" \\"
    echo "         --apple-id you@example.com --team-id TEAMID --password APP-SPECIFIC-PW"
    MISSING=1
fi
if [ "$MISSING" = "1" ]; then
    echo
    echo "Nothing was built. Fill those in and run this again."
    exit 1
fi

IDENTITIES=$(security find-identity -v -p codesigning 2>&1 || true)
case "$IDENTITIES" in
    *"$IDENTITY"*) ;;
    *)
    echo "  No certificate matching '$IDENTITY' is installed in your keychain."
    echo "  Download it from developer.apple.com > Certificates, or let Xcode"
    echo "  create one: Settings > Accounts > Manage Certificates > +"
    exit 1 ;;
esac

# --- Build -----------------------------------------------------------------
echo
echo "1. Building Release"
rm -rf "$OUT"
mkdir -p "$OUT"
xcodebuild -project NotchSnap.xcodeproj -scheme NotchSnap -configuration Release \
    -derivedDataPath "$OUT/dd" CONFIGURATION_BUILD_DIR="$PWD/$OUT/Release" \
    build > "$OUT/build.log" 2>&1 || { tail -30 "$OUT/build.log"; exit 1; }
echo "   $APP"

# --- Verify the signature BEFORE spending minutes on notarization ----------
echo
echo "2. Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/   /'

# Capture once, then match against the string. NOT `codesign | grep -q`:
# grep -q exits the moment it matches, codesign takes SIGPIPE and returns
# non-zero, and `set -o pipefail` turns that into a failed check — so a
# CORRECT build reported "Hardened Runtime is OFF" and refused to continue.
SIGINFO=$(codesign -dv --verbose=2 "$APP" 2>&1 || true)

case "$SIGINFO" in
    *"TeamIdentifier=$TEAM"*) ;;
    *) echo "   Signed, but not with team $TEAM. Check CODE_SIGN_IDENTITY."
       echo "$SIGINFO" | grep -E "^Authority|^TeamIdentifier" | sed 's/^/     /'
       exit 1 ;;
esac

# Hardened Runtime is non-negotiable for notarization; catch it here rather
# than after a round trip to Apple.
case "$SIGINFO" in
    *"(runtime)"*|*",runtime)"*) ;;
    *) echo "   Hardened Runtime is OFF. Notarization will be rejected."
       echo "   Add to $CONFIG:  ENABLE_HARDENED_RUNTIME[config=Release] = YES"
       exit 1 ;;
esac

# get-task-allow is injected by Xcode and rejected by notarization.
#
# Captured, not piped into grep -q. Piping was worse here than in the checks
# above: when the entitlement IS present, grep matches, codesign takes SIGPIPE,
# pipefail makes the pipeline non-zero, and the `if` reads false — so the guard
# went quiet in precisely the case it exists to catch.
ENTS=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)
case "$ENTS" in
    *get-task-allow*)
        echo "   get-task-allow is embedded. Notarization will be rejected."
        echo "   Add to $CONFIG:  CODE_SIGN_INJECT_BASE_ENTITLEMENTS[config=Release] = NO"
        exit 1 ;;
esac
echo "   Developer ID + Hardened Runtime confirmed, no debug entitlements."

# --- Notarize --------------------------------------------------------------
echo
echo "3. Notarizing (Apple scans it; usually 1-5 minutes)"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/notarize.zip"
xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "$PROFILE" --wait \
    2>&1 | sed 's/^/   /'

# --- Staple ----------------------------------------------------------------
# Embeds the ticket so the app validates without a network round trip on the
# user's Mac — the difference between "opens" and "opens once you're online".
echo
echo "4. Stapling the ticket"
xcrun stapler staple "$APP" 2>&1 | sed 's/^/   /'
xcrun stapler validate "$APP" 2>&1 | sed 's/^/   /'

# --- Final check, as a user's Mac would see it -----------------------------
echo
echo "5. Gatekeeper assessment (what a downloader gets)"
spctl -a -vvv -t exec "$APP" 2>&1 | sed 's/^/   /'

ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/NotchSnap.zip"
rm -f "$OUT/notarize.zip"

# --- Disk image ------------------------------------------------------------
# The .dmg is what people expect to download: it opens to a window with the app
# beside a shortcut to /Applications, so installing is one drag. It has to be
# signed and notarized in its own right — notarizing the app inside does not
# cover the container it arrives in.
echo
echo "6. Building the disk image"
STAGE="$OUT/dmg-stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$OUT/NotchSnap.dmg"
hdiutil create -volname "NotchSnap" -srcfolder "$STAGE" -ov -format UDZO \
    "$OUT/NotchSnap.dmg" > /dev/null
codesign --force --sign "$IDENTITY" --timestamp "$OUT/NotchSnap.dmg"
rm -rf "$STAGE"

echo "7. Notarizing the disk image"
xcrun notarytool submit "$OUT/NotchSnap.dmg" --keychain-profile "$PROFILE" --wait \
    2>&1 | tail -4 | sed 's/^/   /'
xcrun stapler staple "$OUT/NotchSnap.dmg" 2>&1 | tail -1 | sed 's/^/   /'

# --- Publish ---------------------------------------------------------------
# Uploading is part of releasing. Producing an artifact and stopping is how a
# stale, unsigned build sat on the Releases page while a working one existed
# only on this Mac (Marcello, 2026-08-04).
# From the git tag, NOT CFBundleShortVersionString. The plist has said 1.0.0
# since the beginning while the tags are at v1.5.x, so deriving the tag from it
# would publish to a release that does not exist.
TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
echo
echo "8. Publishing to GitHub"
if ! command -v gh > /dev/null; then
    echo "   gh not installed — upload $OUT/NotchSnap.dmg manually."
elif [ -z "$TAG" ]; then
    echo "   No git tag found; tag the commit first, or upload manually."
elif gh release view "$TAG" > /dev/null 2>&1; then
    gh release upload "$TAG" "$OUT/NotchSnap.dmg" "$OUT/NotchSnap.zip" --clobber
    echo "   Updated $TAG"
else
    echo "   No release $TAG yet. Create it, then re-run, or:"
    echo "     gh release create $TAG $OUT/NotchSnap.dmg $OUT/NotchSnap.zip"
fi

echo
echo "Done:"
echo "  $OUT/NotchSnap.dmg   <- the download link"
echo "  $OUT/NotchSnap.zip"
