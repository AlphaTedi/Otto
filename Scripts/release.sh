#!/bin/bash
# Build, sign, notarize and staple NotchSnap for distribution.
#
#   bash Scripts/release.sh
#
# Produces build/dist/Otto.zip — the thing you put on a website. Someone
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
APP="$OUT/Release/Otto.app"

read_setting() {   # read_setting KEY -> value, ignoring commented-out lines
    [ -f "$CONFIG" ] || return 0
    grep -E "^[[:space:]]*$1[[:space:]]*=" "$CONFIG" 2>/dev/null \
        | tail -1 | sed "s/^[^=]*=//" | xargs 2>/dev/null || true
}

IDENTITY=$(read_setting CODE_SIGN_IDENTITY)
TEAM=$(read_setting DEVELOPMENT_TEAM)
PROFILE=$(read_setting NOTARY_PROFILE)

echo "Otto release build"
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

# --- Version ---------------------------------------------------------------
# Sparkle decides whether an update exists by COMPARING VERSIONS. If every build
# reports the same number, installed copies conclude they are current and no
# update ever appears — so this is not cosmetic.
TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
if [ -z "$TAG" ]; then
    echo "  No git tag found. Tag the release first:  git tag -a v1.6.0 -m '...'"
    exit 1
fi
VERSION="${TAG#v}"
# Monotonic build number: total commits. Sparkle needs this to always increase.
BUILD=$(git rev-list --count HEAD)
echo "  Version $VERSION (build $BUILD) from tag $TAG"

# --- Build -----------------------------------------------------------------
echo
echo "1. Building Release"
rm -rf "$OUT"
mkdir -p "$OUT"
# ARCHS is pinned to BOTH architectures, and ONLY_ACTIVE_ARCH forced off.
#
# Without this the build inherits the host architecture. Every release up to
# v1.7.1 was built on Marcello's 2018 Intel Mac and shipped x86_64-only, so
# every Apple Silicon user was told to install Rosetta before Otto would open
# at all — "this does not happen with normal Apps", and they were right
# (Marcello's testers, 2026-08-06). Cross-compiling arm64 from Intel is fine;
# the toolchain ships both.
xcodebuild -project NotchSnap.xcodeproj -scheme NotchSnap -configuration Release \
    -derivedDataPath "$OUT/dd" CONFIGURATION_BUILD_DIR="$PWD/$OUT/Release" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    build > "$OUT/build.log" 2>&1 || { tail -30 "$OUT/build.log"; exit 1; }
echo "   $APP"

# Prove it, rather than trusting the flags. A silently thin binary is exactly
# the kind of defect that only shows up on someone else's machine.
SLICES=$(lipo -archs "$APP/Contents/MacOS/Otto" 2>/dev/null || echo "")
case "$SLICES" in
    *arm64*x86_64*|*x86_64*arm64*)
        echo "   universal: $SLICES" ;;
    *)  echo "   NOT UNIVERSAL — built only: ${SLICES:-unknown}"
        echo "   Apple Silicon users would be prompted to install Rosetta."
        exit 1 ;;
esac

# --- Re-sign Sparkle's nested helpers --------------------------------------
# Xcode signs the app and the framework, but NOT the executables nested inside
# Sparkle.framework — Updater.app, Autoupdate, and the two XPC services. They
# ship pre-signed by the Sparkle project, and Apple rejected the whole archive:
# "The binary is not signed with a valid Developer ID certificate" plus "the
# signature does not include a secure timestamp", once per architecture.
#
# They have to be signed inside-out: each nested item first, then the framework
# that contains them, then the app — signing an outer bundle first is undone the
# moment anything inside it changes.
if [ -d "$APP/Contents/Frameworks/Sparkle.framework" ]; then
    echo
    echo "1b. Signing Sparkle's nested helpers"
    SPK="$APP/Contents/Frameworks/Sparkle.framework"
    VER=$(readlink "$SPK/Versions/Current" || echo "Current")
    for nested in \
        "$SPK/Versions/$VER/XPCServices/Downloader.xpc" \
        "$SPK/Versions/$VER/XPCServices/Installer.xpc" \
        "$SPK/Versions/$VER/Updater.app" \
        "$SPK/Versions/$VER/Autoupdate"
    do
        [ -e "$nested" ] || continue
        codesign --force --options runtime --timestamp --sign "$IDENTITY" "$nested" 2>&1 \
            | sed 's/^/   /'
    done
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$SPK" 2>&1 | sed 's/^/   /'
    # The app's own signature is invalidated by the above, so redo it last.
    codesign --force --options runtime --timestamp \
        --entitlements NotchSnap/Resources/NotchSnap.entitlements \
        --sign "$IDENTITY" "$APP" 2>&1 | sed 's/^/   /'
    echo "   nested helpers signed"
fi

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
# Hardened Runtime gates access to calendars, contacts, mic and camera behind
# entitlements. Without them macOS refuses the resource with NO prompt and NO
# entry in the Privacy list — indistinguishable from the user denying it. That
# shipped for five releases: calendar access worked in Debug (no hardened
# runtime) and was silently dead in every signed build (Marcello, 2026-08-05).
for required in \
    "com.apple.security.personal-information.calendars" \
    "com.apple.security.personal-information.addressbook" \
    "com.apple.security.device.audio-input"
do
    case "$ENTS" in
        *"$required"*) ;;
        *) echo "   MISSING entitlement: $required"
           echo "   Hardened Runtime will deny that resource silently at runtime."
           echo "   Add it to NotchSnap/Resources/NotchSnap.entitlements"
           exit 1 ;;
    esac
done
echo "   Developer ID + Hardened Runtime confirmed, entitlements present."

# --- Notarize --------------------------------------------------------------
echo
echo "3. Notarizing (Apple scans it; usually 1-5 minutes)"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/notarize.zip"
NOTARY_OUT=$(xcrun notarytool submit "$OUT/notarize.zip" \
    --keychain-profile "$PROFILE" --wait 2>&1 || true)
echo "$NOTARY_OUT" | sed 's/^/   /'
# Do NOT continue on rejection. The script previously walked on to stapling,
# which then failed with an opaque "Record not found" instead of showing why.
case "$NOTARY_OUT" in
    *"status: Accepted"*) ;;
    *)  SUBID=$(echo "$NOTARY_OUT" | sed -n 's/.*id: \([0-9a-f-]\{36\}\).*/\1/p' | head -1)
        echo
        echo "   Notarization FAILED. Apple's reasons:"
        [ -n "$SUBID" ] && xcrun notarytool log "$SUBID" --keychain-profile "$PROFILE" 2>/dev/null \
            | grep -E '"(message|path)"' | sed 's/^/   /' | head -20
        exit 1 ;;
esac

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

ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/Otto.zip"
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
DMG="$OUT/Otto-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Otto" -srcfolder "$STAGE" -ov -format UDZO \
    "$DMG" > /dev/null
codesign --force --sign "$IDENTITY" --timestamp "$DMG"
rm -rf "$STAGE"

echo "7. Notarizing the disk image"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait \
    2>&1 | tail -4 | sed 's/^/   /'
xcrun stapler staple "$DMG" 2>&1 | tail -1 | sed 's/^/   /'

# --- Publish ---------------------------------------------------------------
# Uploading is part of releasing. Producing an artifact and stopping is how a
# stale, unsigned build sat on the Releases page while a working one existed
# only on this Mac (Marcello, 2026-08-04).
echo
echo "8. Publishing to GitHub"
if ! command -v gh > /dev/null; then
    echo "   gh not installed — upload $DMG manually."
elif [ -z "$TAG" ]; then
    echo "   No git tag found; tag the commit first, or upload manually."
elif gh release view "$TAG" > /dev/null 2>&1; then
    gh release upload "$TAG" "$DMG" "$OUT/Otto.zip" --clobber
    echo "   Updated $TAG"
else
    # CREATE it, do not print advice. Printing advice is how an appcast got
    # published pointing at a release that did not exist — every installed copy
    # would have been offered an update it could not download
    # (Marcello, 2026-08-04).
    gh release create "$TAG" "$DMG" "$OUT/Otto.zip" \
        --title "Otto ${TAG#v}" --generate-notes
    echo "   Created $TAG"
fi

# --- Appcast ---------------------------------------------------------------
# The feed installed copies poll. generate_appcast signs each update with the
# EdDSA private key from the keychain; the app carries the matching public key
# and refuses anything that does not verify — so a compromised host still
# cannot push code to users.
echo
echo "9. Generating the update feed"
SPARKLE_BIN=$(find ~/Library/Developer/Xcode/DerivedData -path "*artifacts/sparkle/Sparkle/bin" -type d 2>/dev/null | head -1)
if [ -z "$SPARKLE_BIN" ]; then
    echo "   Sparkle tools not found. Run: xcodebuild -resolvePackageDependencies"
else
    FEEDDIR="$OUT/feed"
    rm -rf "$FEEDDIR"; mkdir -p "$FEEDDIR"
    cp "$OUT/Otto.zip" "$FEEDDIR/"
    # generate_appcast reads every archive in the folder and emits appcast.xml.
    "$SPARKLE_BIN/generate_appcast" \
        --download-url-prefix "https://github.com/AlphaTedi/Screenshot_app/releases/download/$TAG/" \
        "$FEEDDIR" 2>&1 | sed 's/^/   /'
    if [ -f "$FEEDDIR/appcast.xml" ]; then
        cp "$FEEDDIR/appcast.xml" appcast.xml
        echo "   appcast.xml updated"
    fi
fi

# --- Prove the feed points at something real -------------------------------
# An appcast whose enclosure 404s is worse than no appcast: the app offers an
# update, then fails to fetch it.
if [ -f appcast.xml ]; then
    FEED_URL=$(grep -o 'url="[^"]*Otto.zip"' appcast.xml | head -1 | sed 's/url="//;s/"//')
    if [ -n "$FEED_URL" ]; then
        CODE=$(curl -sIL --max-time 30 -o /dev/null -w "%{http_code}" "$FEED_URL" || echo "000")
        if [ "$CODE" = "200" ]; then
            echo "   feed enclosure resolves (HTTP 200)"
        else
            echo "   WARNING: the appcast points at $FEED_URL which returns $CODE."
            echo "   Installed copies would offer an update they cannot download."
            exit 1
        fi
    fi
fi

echo
echo "Done:"
echo "  $DMG   <- the download link"
echo "  $OUT/Otto.zip"
echo
echo "Commit and push appcast.xml — that is what installed copies read:"
echo "  git add appcast.xml && git commit -m \"Release $TAG\" && git push"
