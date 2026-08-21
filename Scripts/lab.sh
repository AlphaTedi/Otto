#!/usr/bin/env bash
# Otto Lab — build the experimental app and install it beside the real one.
#
#   bash Scripts/lab.sh          build + install to /Applications/Otto Lab.app
#   bash Scripts/lab.sh --seed   ...and first copy production data across
#   bash Scripts/lab.sh --run    ...and launch it when done
#
# What makes this safe to run while depending on the shipped Otto:
#
#   * Different bundle id      com.notchsnap.app.lab
#   * Different data folder    ~/Library/Application Support/NotchSnapLab
#   * Different keychain item  so Google sign-ins do not collide
#   * Sparkle OFF              or the lab would "update" itself into the
#                              shipped app off the production feed
#   * No DMG, no notarization, no appcast — nothing here can reach a user.
#
# Same target and same source tree as the real build, with OTTO_LAB flipped.
# See NotchSnap/App/AppBuild.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

SEED=false; RUN=false
for arg in "$@"; do
  case "$arg" in
    --seed) SEED=true ;;
    --run)  RUN=true ;;
    *) echo "unknown flag: $arg"; exit 2 ;;
  esac
done

APP_NAME="Otto Lab"
BUNDLE_ID="com.notchsnap.app.lab"
OUT="build/lab"
DEST="/Applications/${APP_NAME}.app"
SUPPORT="$HOME/Library/Application Support"

# Version is cosmetic here — nothing consumes it — but a build that says which
# commit it came from is worth having when three of these are on the desk.
VERSION="$(git describe --tags --abbrev=0 2>/dev/null || echo 0.0.0)-lab"
BUILD_NUM="$(git rev-list --count HEAD)"
SHA="$(git rev-parse --short HEAD)"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"

echo "  Otto Lab  $VERSION ($BUILD_NUM)  from $BRANCH @ $SHA"

rm -rf "$OUT"
mkdir -p "$OUT"
xcodebuild -project NotchSnap.xcodeproj -scheme NotchSnap -configuration Release \
    -derivedDataPath "$OUT/dd" CONFIGURATION_BUILD_DIR="$PWD/$OUT/Release" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUM" \
    PRODUCT_NAME="$APP_NAME" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) OTTO_LAB' \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    build > "$OUT/build.log" 2>&1 || { tail -40 "$OUT/build.log"; exit 1; }

APP="$OUT/Release/${APP_NAME}.app"
[ -d "$APP" ] || { echo "  built product missing: $APP"; exit 1; }

# Prove the two cannot be confused for each other, rather than trusting flags.
GOT_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
GOT_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$APP/Contents/Info.plist")"
[ "$GOT_ID" = "$BUNDLE_ID" ] || { echo "  bundle id is '$GOT_ID', expected '$BUNDLE_ID'"; exit 1; }
[ "$GOT_NAME" = "$APP_NAME" ] || { echo "  bundle name is '$GOT_NAME', expected '$APP_NAME'"; exit 1; }
echo "   identity: $GOT_NAME ($GOT_ID)"

# TCC identity is the code signature, so an ad-hoc signed lab would have to
# re-ask for calendar access on every rebuild. Signed properly, it asks once.
# Two traps in one line, both of which reported a perfectly signed build as
# ad-hoc:
#   * -dvv, not -dv — the Authority lines only appear at the second -v.
#   * capture first, THEN grep. `codesign | grep -q` under `set -o pipefail`
#     always fails: grep exits the moment it matches, codesign takes SIGPIPE,
#     and pipefail hands the pipeline codesign's non-zero status. The check
#     was inverted precisely when it succeeded.
SIGINFO="$(codesign -dvv "$APP" 2>&1 || true)"
if grep -q "Authority=Developer ID Application" <<<"$SIGINFO"; then
    echo "   Developer ID signed — permissions will persist across rebuilds"
else
    echo "   NOT Developer ID signed — macOS will re-prompt for permissions"
fi

if $SEED; then
    # Keyed on whether the lab has any to-dos, not on whether its folder
    # exists. Merely launching the lab creates an EMPTY store, so a
    # folder-exists test refuses to seed exactly when seeding is wanted.
    LAB_TODOS="$SUPPORT/NotchSnapLab/Todo/todos.json"
    HAS_DATA=false
    if [ -s "$LAB_TODOS" ] && grep -q '"items":\[{' "$LAB_TODOS" 2>/dev/null; then
        HAS_DATA=true
    fi
    if $HAS_DATA; then
        echo "   --seed skipped: the lab already has to-dos of its own"
    elif [ -d "$SUPPORT/NotchSnap" ]; then
        # A COPY, one way, never linked. The lab can then be scribbled on
        # freely; nothing it does travels back.
        mkdir -p "$SUPPORT/NotchSnapLab"
        cp -R "$SUPPORT/NotchSnap/." "$SUPPORT/NotchSnapLab/"
        echo "   seeded the lab from a COPY of your real data"
    fi
fi

pkill -f "$DEST" 2>/dev/null || true
sleep 1
rm -rf "$DEST"
cp -R "$APP" "$DEST"
echo "   installed  $DEST"

if $RUN; then open "$DEST"; echo "   launched"; fi

cat <<EOF

   Otto Lab is separate from Otto in every way that matters:
     data     ~/Library/Application Support/NotchSnapLab
     updates  disabled (it can never pull the production build over itself)

   Both use the same global shortcuts, so run ONE at a time —
   quit Otto before testing the lab, or they fight over Ctrl-Shift-N.
EOF
