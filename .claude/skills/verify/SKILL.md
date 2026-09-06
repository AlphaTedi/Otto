---
name: verify
description: Build, launch, and headlessly drive NotchSnap to verify changes at runtime. Use whenever a change needs runtime verification in this repo.
---

# Verifying NotchSnap

## Build & launch

`Package.swift` is a decoy (empty targets) — build with xcodebuild:

```bash
xcodebuild -project NotchSnap.xcodeproj -scheme NotchSnap -configuration Debug build
```

New source files must be added to `NotchSnap.xcodeproj/project.pbxproj` by hand
(4 entries: PBXBuildFile, PBXFileReference, group child, Sources phase — copy
the pattern of a sibling file; Todo-group files use `path = ../Todo/...`).

Launch detached (a `&` background job dies with the Bash tool's shell):

The product is **Otto.app**, not NotchSnap.app — the project, scheme and target
are still called NotchSnap, only the built bundle was renamed. So the process to
kill is `Otto` too.

```bash
pkill -x Otto   # needs dangerouslyDisableSandbox; sandboxed kill is silently dropped
open "$(xcodebuild -project NotchSnap.xcodeproj -scheme NotchSnap -configuration Debug -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR/{print $3; exit}')/Otto.app"
```

If pkill leaves survivors in `SX` state, they're held by Xcode's debugserver —
kill the parent debugserver PIDs (equivalent to pressing Stop in Xcode).

## TCC reality on this machine

The agent shell has **no Screen Recording and no Accessibility** permission:
- `screencapture` produces wallpaper-only images (all windows silently omitted);
  window captures (`-l`) fail with "could not create image from window".
- Synthetic CGEvents (mouse/keyboard) are **silently dropped** — the API
  succeeds but the cursor never moves. AppleScript UI scripting is equally dead.

So: no pixels, no fake input. Don't burn time rediscovering this.

## Headless driving — DebugDriver

Debug builds install a DistributedNotificationCenter listener
([DebugDriver.swift](NotchSnap/App/DebugDriver.swift), `#if DEBUG` only).
Compile a fast poster once (swift -e has ~1s latency, too slow to observe
sub-second sequences like the 350ms completion-settle window):

```bash
cat > /tmp/poster.swift <<'EOF'
import Foundation
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.notchsnap.debug.command"),
    object: CommandLine.arguments[1], userInfo: nil, deliverImmediately: true)
EOF
swiftc -O /tmp/poster.swift -o /tmp/poster
```

Commands: `expand`, `collapse`, `add <title>`, `complete-first`,
`uncomplete-first`, `toggle-completed-section`, `switch <index>`, `dump`,
`create-mode`, `create-submit` (Return path incl. NL date stripping),
`browse-mode`, `find <query>`, `jump` (Return path in find mode),
`draft <title>`, `parse <text>` (NL date parser probe),
`notes-enter` / `notes-draft <text>` / `notes-commit` / `notes-open-first` /
`notes-select <n>` / `notes-open-selected` / `notes-close` / `notes-status`,
`notes-body` (what the note's NSTextView is actually holding vs what the store
has — the only headless way to catch a note that opens blank),
`notes-roundtrip` (markdown → attributed → markdown over 21 documents),
`expand-focused` / `collapse-row` (NC details), `note <text>` / `step <text>`
(first open item in active collection).
`dump` appends state (notch state, panel mode, active collection,
open/completed/settling counts, ring progress, find query/matches, draft,
todoContentHeight, notchExtraHeight) to `/tmp/notchsnap-debug-state.txt`.

App stdout is block-buffered when redirected — don't rely on prints; use `dump`.

## Gotchas

- The to-do content view only exists while expanded — `todoContentHeight`
  goes stale when idle and re-measures on next `expand`. Expected.
- Driving `expand` pops the panel on the **user's screen** — they may
  interact with it mid-test and mutate state under you. Check timestamps
  before calling something a bug.
- Test items land in the real store
  (`~/Library/Application Support/NotchSnap/Todo/todos.json`).
- `defaults write com.notchsnap.app <key>` + `dump` verifies settings-driven
  behavior (e.g. `showLegacyPanels`) without UI.
- Keyboard shortcuts, hover, drag-reorder, and animation feel remain
  human-verified — TCC blocks them here.
