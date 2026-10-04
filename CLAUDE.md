# Otto — agent instructions

Read `docs/ARCHITECTURE.md` (where the code lives and how it fits together)
and `docs/CONTEXT.md` (product principles, platform traps, decision log)
before changing anything. Build with
`xcodebuild -project Otto.xcodeproj -scheme Otto`; verify at runtime via the
`verify` skill (`.claude/skills/verify/SKILL.md`).

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
- **New system verbs go through App Intents** (`Otto/Intents/`), thin
  wrappers over `TodoStore` — never a second logic path.
- `Otto/` is a synchronized folder: new source files need no project-file
  edit. Put each file in the feature folder it belongs to
  (`docs/ARCHITECTURE.md`); everything else under `Otto/` ships as a resource.
- The bundle id `com.notchsnap.app` is the only place the pre-Otto name may
  stay (TCC identity, preferences domain, Sparkle). Never rename it.
