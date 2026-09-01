# Otto (NotchSnap) — agent instructions

Read `docs/NOTCHSNAP_CONTEXT.md` before changing anything: product principles,
architecture, platform traps, and the decision log live there. Build with
xcodebuild (never SwiftPM — `Package.swift` is a decoy); verify at runtime via
the `verify` skill (`.claude/skills/verify/SKILL.md`).

Hard requirements for every change:

- **Keyboard-first** (context doc, principle 6). Every daily flow must be fully
  drivable without the mouse. A new surface or action ships WITH its keyboard
  path in the same change: Esc backs out one level from anywhere (and closes
  from plain browsing), explicit opens put the caret in the draft row, ⏎ edits
  the focused row, Space completes it. Update the `?` overlay
  (`ShortcutsOverlay`) when a binding changes.
- **The panel hugs its content** (principle 2). Never give the expanded panel a
  fixed height; caps are `maxHeight`/`min(natural, budget)`, and any measured
  height must be a measurement of natural content, not a proposal echoed back.
- **Markdown mirror** (principle 7). New user-authored data must appear in the
  storage folder via `MarkdownVault`; new persisted fields need a
  `decodeIfPresent` line in the hand-rolled decoders (`TodoItem`,
  `AppSettings`) or old files/settings are silently lost.
- **New system verbs go through App Intents** (`NotchSnap/Intents/`), thin
  wrappers over `TodoStore` — never a second logic path.
- New source files must be registered by hand in
  `NotchSnap.xcodeproj/project.pbxproj` (4 entries; copy a sibling's pattern).
