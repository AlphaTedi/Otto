#!/bin/bash
# Why can't NotchSnap get calendar access on this Mac?
#
# Run it on the machine that is failing:
#   bash Scripts/diagnose-calendar.sh
# or, if you only have the app:
#   curl -sL https://raw.githubusercontent.com/AlphaTedi/Screenshot_app/main/Scripts/diagnose-calendar.sh | bash
#
# Reads only. Changes nothing. Prints a verdict at the end.

set -u
BUNDLE_ID="com.notchsnap.app"

echo "NotchSnap calendar diagnosis"
echo "============================"
sw_vers | sed 's/^/  /'
echo

# --- Where is the app, and is it the one that's running? -------------------
RUNNING_PATH=$(ps -Ao comm= | grep -i "NotchSnap.app/Contents/MacOS" | head -1)
APP=""
for candidate in "$RUNNING_PATH" /Applications/NotchSnap.app ~/Applications/NotchSnap.app \
                 ~/Downloads/NotchSnap.app ~/Desktop/NotchSnap.app; do
    [ -z "$candidate" ] && continue
    p="${candidate%%/Contents/MacOS*}"
    if [ -d "$p" ]; then APP="$p"; break; fi
done

if [ -z "$APP" ]; then
    echo "  Could not find NotchSnap.app. Pass its path:  bash $0 /path/to/NotchSnap.app"
    [ $# -ge 1 ] && APP="$1" || exit 1
fi
echo "1. Location"
echo "   $APP"

VERDICT=""

# --- Translocation ---------------------------------------------------------
echo
echo "2. App Translocation"
if [[ "$APP" == *"/AppTranslocation/"* ]]; then
    echo "   YES — macOS is running it from a randomized read-only copy."
    echo "   This alone prevents any permission from being granted."
    VERDICT="${VERDICT}TRANSLOCATED "
else
    echo "   No."
fi

# --- Quarantine ------------------------------------------------------------
echo
echo "3. Quarantine flag"
Q=$(xattr -p com.apple.quarantine "$APP" 2>/dev/null)
if [ -n "$Q" ]; then
    echo "   PRESENT: $Q"
    echo "   A quarantined app launched from outside /Applications gets translocated."
    VERDICT="${VERDICT}QUARANTINED "
else
    echo "   Not present."
fi

# --- Signature -------------------------------------------------------------
echo
echo "4. Code signature"
if codesign --verify --deep --strict "$APP" 2>/dev/null; then
    echo "   Valid."
else
    echo "   INVALID — TCC will not identify the app, so it can never appear"
    echo "   in System Settings. Re-sign it:  codesign --force --deep --sign - \"$APP\""
    VERDICT="${VERDICT}BADSIG "
fi
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "^Identifier=|^Signature=" | sed 's/^/   /'

REAL_ID=$(codesign -dv "$APP" 2>&1 | sed -n 's/^Identifier=//p')
if [ "$REAL_ID" != "$BUNDLE_ID" ]; then
    echo "   NOTE: bundle id is '$REAL_ID', not '$BUNDLE_ID'."
    echo "   Your tccutil reset targeted the wrong id. Use:"
    echo "     tccutil reset Calendar $REAL_ID"
    VERDICT="${VERDICT}WRONGID "
fi

# --- Usage descriptions ----------------------------------------------------
echo
echo "5. Required Info.plist keys"
for key in NSCalendarsFullAccessUsageDescription NSCalendarsUsageDescription; do
    if /usr/libexec/PlistBuddy -c "Print :$key" "$APP/Contents/Info.plist" >/dev/null 2>&1; then
        echo "   $key: present"
    else
        echo "   $key: MISSING — macOS denies without ever prompting."
        VERDICT="${VERDICT}NOPLIST "
    fi
done

# --- Does macOS Calendar even have an account? -----------------------------
echo
echo "6. Accounts in macOS Calendar"
if ls "$HOME/Library/Calendars" >/dev/null 2>&1; then
    N=$(ls "$HOME/Library/Calendars" 2>/dev/null | grep -c "caldav\|calendar" || true)
    if [ "$N" = "0" ]; then
        echo "   Empty — add your Google account in Calendar > Settings > Accounts."
    else
        echo "   $N calendar source(s) on disk."
    fi
else
    # Distinguish "no accounts" from "Terminal can't look" — reporting the
    # second as the first sends you chasing a problem you do not have.
    echo "   Cannot check: Terminal lacks Full Disk Access. Open the Calendar"
    echo "   app instead — if it shows your events, the accounts are fine."
fi

# --- Verdict ---------------------------------------------------------------
echo
echo "VERDICT"
echo "-------"
if [ -z "$VERDICT" ]; then
    echo "  Nothing structurally wrong. If access is still refused, the denial is"
    echo "  a stale TCC record. Quit NotchSnap fully, then:"
    echo "    tccutil reset Calendar ${REAL_ID:-$BUNDLE_ID}"
    echo "  and reopen it from /Applications."
else
    echo "  Problems found: $VERDICT"
    echo
    echo "  Fix, in this order:"
    [[ "$VERDICT" == *TRANSLOCATED* || "$VERDICT" == *QUARANTINED* ]] && {
        echo "    1. Quit NotchSnap."
        echo "    2. mv \"$APP\" /Applications/       # if not already there"
        echo "    3. xattr -dr com.apple.quarantine /Applications/NotchSnap.app"
        echo "       (note the -d: without it, xattr only LISTS attributes)"
    }
    [[ "$VERDICT" == *BADSIG* ]] && \
        echo "    4. codesign --force --deep --sign - /Applications/NotchSnap.app"
    echo "    5. tccutil reset Calendar ${REAL_ID:-$BUNDLE_ID}"
    echo "    6. Open NotchSnap from /Applications and press Connect."
fi
