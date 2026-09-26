# NotchSnap — Project Context

A single portable dump of everything a new reader (human or tool) needs to reason about
this codebase: what it is, how it's organised, every decision that was made and why,
the platform constraints that shaped it, and the traps that cost real time.

Written 2026-07-25, updated 2026-08-05 (v1.6.3). Entities are named explicitly so this
can be graphed or indexed.

**Companion document:** `docs/DISTRIBUTION.md` covers signing, notarization, the release
pipeline, Sparkle auto-updates, and the distribution failure modes. This file covers the
product, its architecture, and its design decisions.

---

## 1. What the product is

**NotchSnap** is a macOS menu-bar app (`LSUIElement`, no Dock icon) that renders an
interactive panel in/below the MacBook notch. It began as a screenshot utility and
**pivoted to a focused to-do app** that lives in the notch.

- Bundle id: `com.notchsnap.app`
- Repo: `github.com/AlphaTedi/Otto`, branch `main`
- Latest tag: **v1.6.3** (2026-08-05) — signed with Developer ID, notarized, distributed
  as a `.dmg` on GitHub Releases with in-app Sparkle updates
- Team ID `5N7QPZ6H87`; Hardened Runtime on in Release
- Build: `xcodebuild -project NotchSnap.xcodeproj -scheme NotchSnap` —
  **`Package.swift` is a decoy with empty targets; never build with SwiftPM**
- Deployment target macOS 13.0; built with Xcode 26.2 / macOS 26.2 SDK
- **Not sandboxed** (`com.apple.security.app-sandbox = false`)

### Product principles (stable across every PRD)
1. **Everything lives in the notch.** The only sanctioned exception is Settings
   (rare, one-time configuration). No floating windows for daily flows.
2. **Fixed width, variable height.** The panel *hugs* its content; height is a
   measured, animated function of what's inside — never a fixed scroll box.
   (Re-affirmed 2026-09-01 after the panels export pinned the block at 556pt;
   the hug is back and the tab row riding with the content is the accepted cost.)
3. **Creation is never implicit.** Nothing is written to the store as a side effect;
   an explicit action always commits.
4. **No permanent shortcut legends.** Hints appear contextually (focused row),
   on modifier-hold, or in an on-demand `?` overlay.
5. **Replace, don't add.** When a spec supersedes an element, delete the old one in
   the same change (this was a repeated failure mode — see §7).
6. **Keyboard-first.** (Thomas, 2026-09-01.) Every daily flow — create, edit,
   complete, navigate, close — must be fully drivable without the mouse, and a
   feature is not done until its keyboard path exists in the same change. The
   concrete contract: opening the notch by any *explicit* act (click, hotkey,
   intent) puts the caret in the draft row immediately; Esc always backs out one
   level and, from plain browsing, closes the notch — there is no state Esc
   cannot leave, and a click outside the drawn content means the same thing;
   the draft field is row zero of the list (↓ walks into the list, ↑ from the
   first row returns to the field); ⏎ on a focused row edits it, Space
   completes it. Hover-opens
   are the one exception to focus-taking: a pointer passing the notch must
   never steal typing from another app.
7. **Files over silos.** (Thomas, 2026-09-01.) Everything the user writes is
   also on disk as plain Markdown in a folder they choose (Settings › Storage,
   default `~/Documents/Otto`) — findable, greppable, Obsidian-openable without
   this app. todos.json stays the machine's source of truth; the Markdown is
   the human's copy and is never the only copy of live data (the append-only
   Archive of old completions is the deliberate exception). See MarkdownVault.

---

## 2. Architecture

```
NotchSnap/
├── App/          AppState, SettingsView, Localization (EN+IT), DebugDriver, hotkeys glue,
│                 UpdateController (Sparkle), LaunchIntegrity
├── Notch/        NotchController (panel + state machine), NotchShapeView (the shape),
│                 NotchAnimation (all springs), NotchExpandedView (legacy gallery)
├── Todo/         The product: TodoStore, TodoBrowsingView, TodoPanelForms,
│                 DesignSystem, EntityParser/EntityTitleView, NLDateParser
├── Calendar/     CalendarStore, EventKitCalendarProvider, UpNextSection,
│                 MeetingAlertView, CalendarSettingsView,
│                 GoogleOAuth + LoopbackListener + GoogleCalendarProvider + KeychainStore
├── Voice/        SHELVED behind VoiceFeatureFlag — transcriber, parser, review UI
├── Capture/ Editor/ Notes/ Shelf/   Legacy screenshot/clipboard/notes stack
└── Resources/    Info.plist (usage descriptions), sounds
```

### Key singletons
| Type | Owns |
|---|---|
| `AppState` | app-wide state; `todoContentHeight` (hugging height), `notchExtraHeight` math |
| `NotchController` | the `NSPanel`, notch state machine (idle/hovering/expanded/notification), expand/collapse policy |
| `TodoStore` | collections + items, panel modes, persistence |
| `CalendarStore` | connection, meetings, two-stage alert schedule |
| `VoiceCaptureController` | voice phase machine (shelved) |
| `DesignSystem` (`DSColor`/`DSSpacing`/`DSRadius`/`DSFont`) | **all** styling |

### The hugging-height mechanism (most load-bearing design)
`TodoTabView` measures its natural height via a `PreferenceKey` → publishes to
`AppState.todoContentHeight` → `AppState.notchExtraHeight` converts it to a delta
against the gallery baseline → `NotchShapeView` animates the silhouette, the content
window, and the clip mask on **one shared spring** so container and content move together.

### Animation
One spring for content/height: `NotchAnimation.contentHug` = `response 0.45,
dampingFraction 0.60`. Secondary `hintFade` (fast, light) for hints/badges only.
The self-opening meeting alert deliberately routes through the *same* `triggerExpand()`
as a click, so it can't feel like a different kind of motion.

---

## 3. Feature inventory

### To-do system (shipped, v1.1.0)
- Categories as tabs; **Today** is a smart cross-collection aggregation (high urgency +
  due today/overdue), never a membership bucket.
- Per-category **Completed** section, collapsible; two-phase completion — checkbox fill
  and strike-through land instantly while the row *holds its slot* (~350 ms), then the
  row exit and panel shrink fire together.
- **In-panel modes** (`TodoPanelMode`): `browsing`, `newCategory`, `find`, `voice`.
  No floating windows.
- **Inline creation** (there is no `create` mode any more): a draft row is ALWAYS at the
  top of the list — it is the only visible way to make a to-do. `⌃⇧N` / `⌘N` put the
  caret in it, `⇥` switches section (caret or not), `⏎` files it and hands the caret
  back. Only the CARET pins the panel open; the row merely existing must not stop the
  notch auto-collapsing. `blurDraft()` resigns first responder for real — `draftFocused`
  is reported BY the text view, not obeyed by it, so lowering the flag alone leaves a
  caret blinking in a field the app thinks is unfocused.
  The row lives OUTSIDE the `.id(collection.id)` subtree in `TodoBrowsingView` — that
  placement is the feature, since everything inside is rebuilt on a tab switch and a
  draft in there would lose its caret on the very keystroke meant to leave it alone.
- **Quick Find**: typing any letter in browsing mode starts a cross-category search
  (the field is monitor-fed, not a focused `TextField` — a real field would select-all
  and eat the seeding keystroke).
- **Notes + checklists** per to-do, expanded via click or →. Notes are one wrapping
  freeform block. A closed to-do previews at most two checklist steps plus an exact
  “N more steps” disclosure; opening it reveals the full checklist and its trailing
  empty row (type, `⏎`, and the caret lands on the next one — no "add step" button
  exists). Opening another to-do therefore compacts the previous checklist instead
  of leaving every sub-step in the main list.
- **Natural-language dates** in the title ("tom" → due date), highlighted inline in the
  accent colour and stripped only on Create.
- **Inline entity chips** in titles — links (clickable, host-shortened), dates,
  `@mentions`, `` `code` `` — rendered with `NSTextAttachment` in a real wrapping text
  flow (SwiftUI `Text` concatenation cannot embed views inline).
- **Urgency/priority: REMOVED 2026-09-14** (Marcello). The 9 px dot, its tooltip,
  the row context-menu section, `TodoStore.setUrgency`, the `TodoItem.urgency`
  field, the ⏫/🔼 Markdown markers and the Today high-urgency rule are all gone.
  `TodoItem` decoders ignore the stale `urgency` key in old todos.json files;
  old `.md` vault files keep their markers (write-only mirror, never re-read).
  Do not reintroduce without a new decision entry.
- **Tab indicators**: remaining-count number (✓ when all done). This *replaced* a
  circular progress ring, which was unreadable at 14 pt.
- **Drag to reorder** both to-do rows (six-dot grip on hover) and category tabs.
- **Explicit default category** for new to-dos, set from a tab's context menu.

### Calendar awareness (built 2026-07-25)
- `MeetingProvider` protocol; `EventKitCalendarProvider` is the v1 implementation.
- Two-stage alerts: ambient amber dot on the collapsed pill (default 15 min) →
  notch **opens itself** (default 2 min) with Join/Snooze; auto-collapses ~2 min
  after start if untouched.
- "Up next" section in Today above the to-dos, next event accented; dashed nudge card
  when not connected, deep-linking to Settings → Calendar.
- Per-calendar toggles, sync-staleness warning, event-level diagnostics.

### Voice brain-dump (built, then SHELVED)
Fully implemented — on-device `SFSpeechRecognizer` transcription, `BrainDumpParser`
(Foundation Models when available, deterministic clause parser otherwise), review-before-
commit UI. **Disabled via `VoiceFeature.isEnabled = false`** on 2026-07-25 to
prioritise other work. Re-enable with one line or
`defaults write com.notchsnap.app voiceCaptureEnabled -bool true`.

---

## 4. Decisions and their rationale

| Date | Decision | Why |
|---|---|---|
| 07-12 | Legacy Shelf/Clipboard/Notes hidden behind a Settings toggle, not deleted | Real foundation, may be revisited |
| 07-12 | Today stays a smart aggregation | Already built and correct |
| 07-13 | **Single black background** — no inner `#111` panel | User call; overrides the `#111` panel in the design PRD's §1 markup |
| 07-14 | `DesignSystem.swift` is the styling source of truth | Two rounds of visual drift came from re-deriving styling from prose |
| 07-15 | `⌃⇥` (not `⌘⇥`) cycles in creation | `⌘⇥` is the system app switcher; macOS consumes it first |
| 07-15 | `⌥⌘N` global creation hotkey (not `⌥Space`) | Raycast/Alfred claim `⌥Space` by default |
| 07-15 | Close policy: outside click **always** closes; Esc backs out one level; modal surfaces never auto-collapse | There must always be a guaranteed exit |
| 07-23 | Progress ring → remaining count | The 14 pt arc couldn't answer "how much is left?" |
| 07-23 | `⌃⇧N` opens creation directly | It was the dead Notes hotkey, falling through to the last-browsed category |
| 07-25 | Voice: layered engines (Apple Intelligence when present, rules otherwise) | Marcello's Mac can never run Foundation Models; a PRD-exact build would be untestable for him |
| 07-25 | Voice trigger: toggle, panel-only | Chosen over hold-to-talk / global |
| 07-25 | Calendar: **EventKit, not Google OAuth** | OAuth needs a Google Cloud client ID only Marcello can create; EventKit reaches the same events with zero setup. Protocol seam left in place for OAuth later |
| 07-25 | Meeting alerts fire for **all accepted meetings**, Join only when a link is detected | You can miss an in-person meeting just as easily |
| 08-16 | Creation card deleted; to-dos are typed into a draft row in the list | One less layer for the app's most common action; the card was also detached from the section it filed into |
| 08-16 | Draft row is permanent, not summoned by `⌃⇧N` | Opening the notch showed no way at all to create a to-do; same reasoning as the always-open trailing step row, one level up |
| 08-16 | `⇥` switches section always, Today included | With the row always present, "re-aim the draft" and "switch tabs" are the same act; `draftDestination` redirects Today to the default section and the row wears that section's colour so it is visible |
| 08-16 | New to-dos land at the TOP of their section | Appended below a long list they were off-screen, which reads as nothing having happened |
| 08-16 | Esc in the draft steps out and KEEPS the text | Esc backs out one level everywhere else; a second Esc closes the notch, and a half-written to-do survives both |
| 08-16 | `⏎` releases the caret instead of holding it for the next to-do | Writing one to-do then closing the notch cost two Escapes, one just to leave a finished field |
| 09-01 | **REVERSED:** `⏎` keeps the caret in the draft field | Esc in an empty field now closes the notch outright, so the two-Escape cost is gone; a burst of to-dos is type-⏎-type-⏎-Esc (Thomas) |
| 09-14 | Meeting notes moved to a permanent Calendar pill beside Notes | The local All/Meeting selector inside Notes broke the space hierarchy; Calendar is now reachable by click and the same arrow/Tab ring as every other daily space. |
| 08-16 | Clicking dead panel space blurs the draft as well as ending a row edit | "Stop typing" cannot mean one of the two live editors and not the other |
| 08-16 | Close policy rule 8 WITHDRAWN — a global-shortcut capture no longer closes the notch | The new row is at the top of the list where you can see it; closing over it hid the only confirmation anything happened |
| 08-16 | `WordKeycap` for named keys (Tab, Esc), separate from `Keycap` | `Keycap` draws one cap per character by design ("⌘↩" is two keys), so "tab" rendered as t·a·b and read as a three-key chord |
| 08-16 | Tab ORDER alone decides where `⌃⇧N` files; the FB8 "set as default" item is gone | Two mechanisms for one outcome, and the invisible one won — dragging Work to the front still left the shortcut on Personal with nothing on screen explaining why |
| 08-16 | Tab drag uses the indicator-only (Arc) model, like the to-do list | Live re-slotting in `dropEntered` shifts every tab sideways under the cursor, which fires the next `dropEntered` — the tabs flip-flopped for as long as the drag was held |
| 08-16 | A category tab is NOT a `Button` | A SwiftUI Button on macOS claims the mouse-down, so an `.onDrag` beside it never starts a drag session at all. This is why tabs could not be dragged while to-do rows — plain views with `.contentShape` + `.onTapGesture` + `.onDrag` — always could |
| 08-16 | The tab scroller is `.scrollDisabled` unless the tabs overflow | A horizontal ScrollView and a sideways drag want the same gesture and the ScrollView wins; while every tab is visible the scroller could only cost the drag |
| 08-17 | Presence indicator built INSIDE `NotchShape`, not as two overlapping rects | `filletRadius` is already a concave top corner — the exact "flare out of the bezel" the two-rect trick approximates, with no seam to hide and one path to animate |
| 08-17 | No full-width black bezel strip across the screen top | On a MacBook the bezel the shape flares from is the physical notch; painting our own would cover the menu bar edge to edge to simulate hardware this Mac already has |
| 08-17 | Presence dot is time-based only, never category | It is the only accent in an element with no label, so a second meaning has nothing to disambiguate against |
| 08-17 | Platform glyphs are SF Symbols in a brand tint, not the real marks | Shipping Meet/Zoom/Teams artwork means bundling trademarked assets under their brand terms — a deliberate decision, not an incidental one |
| 08-16 | Tab-row "+" moved to the end and de-emphasised; it now means "new section" | With creation inline there is no to-do surface for it to open; "•••" went too, since every item on it is already on each tab's context menu |
| 08-16 | Priority dropped from creation (still settable afterwards) | It was a second decision demanded before the first one was written down |

---

## 5. Platform constraints (hard-won, non-obvious)

### Hardware: this Mac can't run Apple Intelligence — ever
MacBookPro15,1 (2018), **Intel Core i7-8750H**, macOS 15.7.4, Xcode 26.2 / SDK 26.2.
Foundation Models requires Apple silicon and macOS 26 dropped this model. Frameworks
from the newer SDK link **weak** when used behind `#if canImport` + `@available`, so the
app still launches on macOS 15 — verify with `otool -L | grep weak`, don't assume.
`SFSpeechRecognizer.supportsOnDeviceRecognition == true` here, so on-device speech
*is* possible without Apple Intelligence.

### Persistence survives reinstall
Not sandboxed ⇒ data lives at
`~/Library/Application Support/NotchSnap/Todo/todos.json`, which survives deleting and
reinstalling the `.app`. `TodoStore` writes `.atomic`, keeps `todos.backup.json`
(last-known-good promoted before each overwrite), and restores from it on a corrupt read.
**Never move this into a sandbox container** or the guarantee breaks.

### Calendar: EventKit only sees what Calendar.app has synced
**On this Mac, macOS silently stopped syncing the Google accounts around 2026-05-12.**
EventKit still listed 8 calendars and 9 events, so everything *looked* connected, while
nothing created after May ever arrived. Diagnose by dumping `creationDate`/
`lastModifiedDate` per event and taking the max — that's when the Mac last received data.
`refreshSourcesIfNecessary()`, opening Calendar.app, and waiting do **not** fix a dead
account token; the fix is Internet Accounts → toggle Calendars / re-add the account.
macOS calendar permission is **all-or-nothing per app** — per-account scoping is
impossible, hence per-calendar toggles instead.

### Concurrency: audio callbacks are not the main actor
A `static func` inside a `@MainActor` class **inherits main-actor isolation**. Calling
one from an `AVAudioEngine` tap (a real-time thread) trips libdispatch:
`BUG IN CLIENT OF LIBDISPATCH … Block was expected to execute on queue [main]` → `ud2`
→ `EXC_BAD_INSTRUCTION`. Mark such helpers `nonisolated`. Building with
`SWIFT_STRICT_CONCURRENCY=complete` catches this whole class of bug.

### Permissions are separate grants
Microphone (`AVCaptureDevice.requestAccess(for: .audio)`) and Speech Recognition are
**two different prompts**; requesting only speech leaves the audio input format invalid
and CoreAudio fails with `-10877`.

### SwiftUI/AppKit traps
- An `NSViewRepresentable`'s `sizeThatFits` is **not** re-invoked on a pure content
  change. Drive height from the SwiftUI layer (measure the string, `.frame(height:)`)
  — that's why the auto-growing creation field wouldn't grow.
- Two views alive during a transition are **VStack siblings** and stack vertically →
  the whole panel visibly jumps. Wrap mode/category swaps in a `ZStack` so they overlap.
- Measured-scroll layouts lag one layout pass; on tab switches that made the incoming
  list start short and visibly expand. Small lists render inline at natural height.
- SwiftUI `Menu` cannot present from a non-activating panel — use inline expanding
  pickers instead.
- `aspectRatio(.fit)` with nothing proposing a size collapses a view to a few points.

---

## 6. Verification methodology

TCC blocks screenshots and synthetic input for the agent shell, so the app is driven
headlessly through **`DebugDriver`** (`#if DEBUG` only): a
`DistributedNotificationCenter` listener on `com.notchsnap.debug.command`, with state
appended to `/tmp/notchsnap-debug-state.txt`.

Commands: `expand`, `collapse`, `dump`, `add <title>`, `switch <n>`, `movecat <±n>`,
`collections`, `create-mode`, `create-submit`, `find <q>`, `jump`, `braindump <text>`,
`entities <text>`, `parse <text>`, `note`/`step`, `meeting <minutes>`, `cal-connect`,
`cal-status`, `cal-debug`, `cal-probe`, `cal-refresh`, `cal-snooze`, `cal-dismiss`,
`voice-status`.

**Gotchas:** launch via `open` on the `.app` bundle — running the binary directly from a
shell gives it a different TCC identity and calendar access is denied. A running Xcode
debug session holds the app and blocks relaunch; `pkill` alone won't free it (kill the
debugserver parent). For pure logic, compile the real source files into a standalone
`swiftc` harness — that's how the entity parser, NL dates, and brain-dump parser were
verified without the app.

Repo skill: `.claude/skills/verify/SKILL.md`.

---

## 7. Failure patterns worth remembering

1. **Adding instead of replacing.** A "New to-do ⌘N" footer row was added alongside the
   "+" tab that was meant to supersede it; a folder icon appeared on tabs that were
   specified as label-only. When a spec replaces something, delete the old thing.
2. **Reverting to a generic default** instead of reading the real data model (a fixed
   gold pill instead of each category's own colour).
3. **Silent empty states.** A working calendar connection with zero events rendered
   *nothing*, which read as "broken". Say "no more meetings today" instead.
4. **Unverifiable status claims.** "Connected" was true but meaningless; listing the
   actual calendars and their freshness is what makes it trustworthy.
5. **Guessing before measuring.** Hours went into calendar theories (Google not synced,
   RSVP pending, past events) when one timestamp dump — newest record = May 12 —
   answered it immediately.
6. **Misreading permission-denied as data.** `ls ~/Library/Calendars` returned empty
   because of TCC, and that was reported as "no accounts configured". It was wrong.

---

## 8. The 2026-09-01 fundamentals pass

One change ("app refactoring fundamentals", Thomas) that set four foundations:

- **Markdown storage (`Todo/MarkdownVault.swift`).** One `.md` per section plus
  `Notes.md` in a user-chosen folder (Settings › Storage; default
  `~/Documents/Otto`, lab builds use `Otto Lab`). Obsidian Tasks conventions
  (📅 due, ⏫/🔼 priority, ✅ done). Write-only mirror, debounced with the JSON
  save; a `.otto-vault.json` manifest lets renames/deletes clean up without
  ever touching user-authored files. **Ticking off a to-do writes it to
  `Archive/<completion-day>.md` immediately** (`recordCompletion`, keyed by
  the task line — title, section, minute; un-ticking removes the block
  again). After a day the completed item leaves the live store (`archive`
  confirms the entry is on disk before pruning) — sweep runs at launch and
  once per day on collapse, never while the panel is open. `AppSettings` decode is now `decodeIfPresent` per
  field (adding a settings field used to reset ALL settings), and every store
  flushes synchronously in `applicationWillTerminate` (the 500 ms debounce
  used to drop the last edit on quit).
- **The hug restored.** The panels export had pinned the to-do block at a fixed
  556 (`LabMetrics.todoBlockMaxHeight` as a *fixed* frame + `viewport = budget`),
  which also fed the revived container layout a constant measurement. Now
  `viewport = min(natural, budget)`, the block frame is a `maxHeight`, and the
  slack-absorbing Spacer is gone — it was what closed the container's
  measurement loop (content stretched to the proposal, so the "measured" height
  was the proposal echoed back). Switching layouts resets BOTH stale
  measurements (`labColumnHeight` and `todoContentHeight`).
- **Keyboard-first mechanics** (principle 6). Esc-to-close routes through
  `forceCollapse()` — `resignKey()` alone never gives key status up, so the
  unforced collapse was vetoed by the engagement Esc itself created. Explicit
  opens (click, ⌃⇧T, intents) call `makeKeyForTyping()`. ⏎ edits the focused
  row via `TodoStore.requestTitleEdit` (same path as clicking); Space
  completes. The key router is scoped to `NotchPanel` windows (it was eating
  the Move picker's Esc) and announces `.todoEditorEscape` so title/step
  editors can DISCARD on Esc even though the monitor must consume the key.
- **App Intents (`Intents/TodoIntents.swift`).** AddTodo (NL dates via the same
  parser as the draft row), CompleteTodo, GetOpenTodos, OpenTodos + App
  Shortcuts — the seam Shortcuts/Spotlight/Siri and Apple's AI surfaces route
  through. Thin by design: parameter resolution here, one TodoStore call, done.
  Gotcha: App Shortcut phrases may only interpolate AppEntity/AppEnum — a
  `\(\.$text)` String parameter in a phrase fails the build at metadata
  extraction, not compile.

## 9. The 2026-09-14 Otto boundary

Otto no longer owns screenshot capture, clipboard monitoring, the screenshot shelf,
or their notification UI. The legacy source remains temporarily for data migration,
but it has no launch path, no Carbon shortcut, no Settings route, and no Screen
Recording usage description. In particular, ⌃⇧2/3/4/5 and ⌃⇧Space are not registered
by Otto, and copying to the system pasteboard must not expand the notch.

The notch panel uses AppKit's `.canJoinAllSpaces`, `.stationary`, and
`.fullScreenAuxiliary` collection behavior. Do not recalculate its frame from
`activeSpaceDidChangeNotification`: that runs during the horizontal Spaces gesture and
makes a stationary panel visibly move with the desktop. Reposition only on real display
parameter changes.

The Notes bottom bar is floating chrome, not a container divider. Keep its controls
inside the lower inset and use `floatingGlass(in:)` for both the formatting capsule and
the Markdown export control. This preserves the outer silhouette's corner geometry and
uses real Liquid Glass on macOS 26 with the project material fallback on older systems.

## 10. Open threads

- **Google OAuth provider** — the structural fix for calendar sync fragility; reads
  Google's API live. Needs a Google Cloud OAuth client ID from Marcello. The
  `MeetingProvider` seam exists for it.
- **Voice capture** — complete but shelved; the microphone path is the only part never
  verified end-to-end.
- **v1.2.0 tag** — the work after `9368510` (feedback fixes, urgency/entity pass,
  default category, drag reorder, voice, calendar) is committed-pending.
- PRD open questions never closed: onboarding moment for the calendar connection;
  configurable "tentative" meetings.

### 2026-09-15 scroll chrome correction

On macOS 26 a capped scrolling list declares a transparent 64pt bottom
`safeAreaBar` and requests the public `.soft` scroll-edge style. The bar is the
geometry SwiftUI needs to progressively blur and dissolve content underneath a
custom control region; applying the style without a bar does not establish
that overlap. Earlier macOS releases use a matched 64pt opacity ramp plus a
masked within-window `NSVisualEffectView`. No private variable-blur selector or
Core Image background filter is used. Pill styling remains the earlier design:
list pills restore v1.47.0 with no resting fill and the full section color when
active; Notes and Calendar restore v1.48.0 with their low-opacity active/hover tint
plus their distinct dashed or solid strokes.

Short lists do not reserve the edge bar, preserving their natural content height.

### 2026-09-15 interrupted presentation hotfix

Content visibility is derived from `state == .expanded`, not separately stored.
The previous collapse task hid every `notchEntry` child before its 80ms delay;
interrupted transitions depended on a cancelled task restoring visibility and
could let stale cancellation cleanup clear a newer task. Opening now executes
synchronously on MainActor. Cancelled collapse tasks return without touching
presentation or task ownership, and content stays visible until actual closure.
`verify-presentation` exercises 30 rapid/cancelled presentation cycles without
creating or deleting user data.

### 2026-09-21 compact checklist follow-up

A closed to-do shows two checklist steps and an exact hidden-step count; only
the opened to-do shows the complete checklist and its draft row. The checklist
connector is centred on the parent checkbox while preserving the child indent,
and an opened card adds the title's text inset below its draft row so its visual
top and bottom padding match. Focus no longer calls `scrollTo` unconditionally:
an already-visible row keeps the current viewport, while a row that is above or
below it scrolls to the nearest edge. After expansion, one delayed geometry
check reveals the new overflow only if the complete opened row no longer fits.

### 2026-09-24 onboarding Direction B

The onboarding was rebuilt from Marcello's handoff (`otto-onboarding` SPEC.md +
PNGs + reference HTML): an 860×460 window, six steps (welcome, focus, notch,
shortcut, permissions, done) in `NotchSnap/App/Onboarding*.swift`. Host Grotesk
is bundled (OFL) and registered per process on first use. The old flow
(`OnboardingView.swift`, `OnboardingDesign.swift`) is gone; the two glass views
other screens still used live in `SharedGlass.swift`.

Deliberate departures from the spec: no Accessibility row (⌃⇧N is a Carbon
hotkey and needs no Accessibility grant, so asking for it would be a false
request), and with it the bolt chip in the orbit visual. No traffic lights and
no ⌘W (Marcello, same day, after Dia's onboarding): the only ways out are
"Open Otto" or quitting, and a quit mid-flow resumes at that step next launch. The calendar alert
lead default moved from 2 to 5 minutes, as the spec's closed decision 4 says
and as the permissions caption reads from that setting.

Traps met on the way, worth keeping:
- SwiftUI `Text` avoids a one-word last line, so it breaks lines differently
  from CSS — `OBText` draws and measures with NSStringDrawing instead.
- Any `.kern` attribute, even 0, turns pair kerning off; use `.tracking`.
- An `NSHostingView` that IS a titled window's content view keeps growing the
  window by the titlebar height; host it inside a plain container view.
- CSS in the reference is content-box: a bordered 16-pt box renders 18–19 pt.

Verification: `onboarding-snap <dir> [steps]` (DEBUG) writes every step, dark
and light, as PNGs via `cacheDisplay` — no Screen Recording needed — for
side-by-side comparison with the handoff's PNGs.

### 2026-09-24 the notch reopens where it was closed

`forceCollapse` — outside click, Esc from the lists, another app taking focus —
used to reset the panel to the lists, so stepping out to copy something for a
note always came back on Work. It now calls `TodoStore.settleForClose()`: the
lists, Notes (with its open note), Calendar and Insights are places and are
kept; Find, New section and voice are passing states and still reset. The
click-to-open caret follows the space on screen
(`requestCaretForCurrentSpace()`): note body, Notes composer, meeting search,
or the to-do draft row. ⌃⇧N still jumps to the default section on purpose.
Verified with the DEBUG `place-test` command (opens an existing note, writes
nothing).

### 2026-09-25 U5 main panel iteration

From the `otto-u5` handoff. Scope decided by Marcello: the FLOATING PANELS get
all of it; the NOTCH CONTAINER gets everything except its text input field,
which stays exactly as it was (its pills stay at the top, too).

- Space tints (`SpaceTint.swift`): base / light / neighbour per space, stored on
  the list as `TodoCollection.tint` (optional, assigned once on load: Grocery,
  Work, Personal by name, then the palette). Colour is ambient only —
  checkboxes and titles are untouched.
- `SpaceChrome.swift`: the ambient glow (two radial layers, `α·(1−t)^2.2`,
  under the selected pill, OKLCH hue crossfade 350 ms, drift paused while
  hidden, none under Reduce Motion), the floating rim, the floating capture
  header (dot, 18 pt text, "Switch space ⇥" ↔ "Save to <Space> ↵", 60 pt,
  hairline), and the gear that replaced the avatar (it opens the same menu, so
  Insights / Shortcuts / Quit stay reachable).
- Floating grid: list inset 10, row gap 13 → checkbox at 22, text at 53 under
  the field's text. Esc in the floating field clears the text first.
- Pills (both layouts): 28 tall, 13/600, selected = light fill + dark text;
  Notes dashed amber, Calendar solid teal.
- Floating panel radius 40 → 32 (Marcello, same day).

Kept deliberately: the floating panel stays glass (the spec's gradient is
described as "the current look"), 657 wide and 556 tall; row vertical rhythm
unchanged. Trap: a stroked `Capsule` at 28 pt rendered a flat tick at each end —
use `RoundedRectangle(cornerRadius: 14, style: .circular)`.

Verification: DEBUG `u5-snap <dir>` renders every state off screen (the live
glass cannot be captured). Launch the Debug binary with `-notchLayout container`
to render the container without touching the user's saved setting.

### 2026-09-25 top navigation and one section colour

From `docs/TOP_NAVIGATION_ARCHITECTURE_PROMPT.md` (Marcello).

- ONE section colour: `TodoCollection.color` now returns
  `spaceTint.sectionColor` (light tone on dark, the hue deepened to OKLCH
  L ≤ 0.52 on light). Pill fill, checkboxes, capture circle, caret, selection
  and "just added" all read it; `colorHex` survives only for old files. The New
  section swatches are the tints themselves.
- U5's ambient glow and tinted rim are REMOVED: the spec keeps material,
  surface and border neutral in every section.
- Path model: `TodoStore.panelPath` (root space, then any page: an open note,
  Insights, New section) is DERIVED from panelMode + NotesStore.openNoteID —
  never stored — and `goBack()` walks it through the existing verbs.
- Floating panels: inside a page the top bar is `ContextBar` — Back + title on
  the capture header's exact geometry. The note page's old well-shaped title
  bar is not drawn there; Insights and New section use it too. ⇥ switches
  space at the root only (inert in Insights now).
- Floating panels: the meeting card is hidden while a page is open, and the
  to-do panel is centred in the screen's visible area (never nearer the notch
  than the old 72; the meeting card sits above it without moving it).
- The notch container keeps its own field and page headers.

DEBUG render: `GlassDebug.forceOpaque` switches glass to its opaque fallback
while `u5-snap` renders, because real Liquid Glass cannot be bitmap-cached
(it rendered the note page solid white). Stroked capsules show flat ticks at
their ends in those renders only — they are clean on screen.

### 2026-09-25 notes audit, corner geometry

Notes audit (Marcello's notes.json, round-trip tested in a standalone harness):
- The serializer wrapped every styled RUN in markers, spaces included
  ("mercoledi.*** ***rimandano", "ciao** mondo **fine"), and split one bold
  word into "**a****b**". Re-parsed and edited, that left orphan "***" inside
  words. Now: runs merged by style, markers around the words only, and a
  typed `*` is written `\*` (the parser unescapes it).
- Linked to-dos were found with a plain substring search, so "co: chiamare…"
  matched inside "trasloco: chiamare…"; the underline began mid-word and the
  linked checkbox — drawn 22 pt BEFORE the phrase, relying on the line-start
  inset — landed on the letters in front. Now `NoteRepair.phraseRange` matches
  whole words, a mid-word-only link is widened and re-stored on open
  (`TodoStore.relinkNotePhrase`, title follows if never edited), mid-line
  phrases get layout-only kerning for their checkbox, and a selection made
  into a to-do is snapped to whole words.
- Retroactive: `NotesStore.repairStoredNotesIfNeeded` runs `NoteRepair` once
  per `NoteRepair.version` over every stored note (orphan markers stripped,
  blank-line runs collapsed to one), after copying the file to
  `notes.pre-repair-<n>.json`. TRAP met on the way: a second, older build
  running at the same time saved its in-memory notes over the repair — the
  flag had already been written, so it had to be reset.

Corner geometry (floating panels): window radius 24 (was 32); everything in a
corner sits 16 from both edges (`SpaceChrome.cornerInset`) with radius
24 − 16 = 8 — the Back key, the gear, the note toolbar and Download. The
leading slot is 30 wide so the dot / Back centre stays on the checkbox column
and text still starts at 53. The first to-do sits 22 below the bar, as it
sits 22 from the left edge. Pill glow removed (the scroller clipped it).
The DEBUG render command is `panel-render` now: a running older Debug build
also answered the old name.

### 2026-09-25 Notes polish and code formatting

From `docs/NOTES_UI_POLISH_AND_CODE_FORMATTING_PROMPT.md`.

- Code in notes: inline code is a structural attribute (`.noteCode`, written
  `` `…` ``); a code block is a NoteBlock (`.code`, written as a ``` fence
  around the run of code lines, verbatim inside). Code never takes bold,
  italic or underline, and backslashes inside it are the user's. The block's
  full-width ground is drawn by `ActionTextView.drawBackground`. Toolbar `</>`:
  click = inline, hold or right-click = block; ⌘⇧C / ⌘⌥⇧C in an open note.
  The monospace face exists for code only — dates, counts and the "1." glyph
  are the system face.
- Calendar is no longer a global space: the bottom bar holds Notes and the
  lists; Notes carries a Notes · Meetings switch (⌥⇥), in the floating header
  and, in the container, under the space bar. ⇥ no longer stops on Calendar.
  The floating meeting-search header lost its calendar-picker icon.
- One list column (`SpaceChrome.columnInset` 10, content at 22) for to-do and
  note rows; one row radius (`LabMetrics.rowRadius` 8) for rows, the opened
  card and note highlights. A note page's body, meeting metadata and session
  to-dos sit on the title's column (`SpaceChrome.textColumn` 53) in the
  floating panels; toolbar, count and Download on the 16 corner inset.
- Download .md: `NSSavePanel` via `begin`, pinned into the notch's own space
  (SpaceAnchor) one level above the panel, with the app activated and the
  panel held open (`isPresentingDialog`); focus returns to the note after.
- DEBUG: `panel-render-pid <pid> <dir>` — only that process renders.

### 2026-09-26 Notes · Meetings as a dropdown accessory

From `otto-notes-mode-dropdown-prd.md` (Raycast-style accessory).

- The segmented Notes · Meetings pill is gone: `NotesKindMenu` ("Notes ⌄")
  trails the capture field; in the container it sits right-aligned under the
  space bar (the container's field itself untouched). Its menu is a custom
  overlay (220 pt, check + label + shortcut), not a SwiftUI `Menu`, for the
  styling. While open it owns ↑↓ ⏎ Esc; ⇥ closes it and still changes space;
  a click outside closes it. ⌘1 Notes / ⌘2 Meetings on the stream, open or
  closed; ⌥⇥ still flips. All go through `NotesStore.chooseKind`.
- "Switch space ⇥" is no longer shown in any capture header; ⇥ is unchanged.
- The Meetings field keeps "Search meeting notes": it searches, so the PRD's
  "Start meeting notes…" placeholder would have described a different action.
