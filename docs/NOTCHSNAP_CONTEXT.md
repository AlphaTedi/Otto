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

### 2026-09-27 image attachments as inline chips

Images in notes and to-dos (feedback batch, point 7; Marcello chose chips
over full-width images). `Attachments.swift`: files are copied into the
vault's `Attachments/` folder, referenced as `![name](Attachments/file)` —
ordinary markdown, so Notes.md and section files show them in Obsidian
(principle 7). Notes: the token lives in the note's markdown and is drawn as
an `ImageChipAttachment` (thumbnail + name; click opens); paste, drop,
the toolbar's image button and ⌘⇧I insert one. `NoteMarkdown` parses tokens
before emphasis and writes them back verbatim — the round-trip test covers
them (36/36). To-dos: `TodoItem.attachments` (decodeIfPresent), chips under
the title with Open/Remove; images are pasted or dropped into the floating
capture field (or ⌘⇧I) and wait as chips beside the text until ⏎. The
container's own field is untouched (standing rule), so there images come
through ⌘⇧I on a focused to-do. Removing a chip leaves the file in
Attachments/ (no garbage collection yet).

Same day, second pass (Marcello, like Conductor): images go IN the text at the
caret, not beside it. A to-do's title now carries the `![…](…)` token where it
was placed; the capture field (rich only to hold chips, plain paste) shows it
as a chip, and so does the row (`EntityTitleView`). `ImageChipInteraction` is
shared by the note editor, the field and the row: hover lights the chip, swaps
its thumbnail for ✕ and floats `ImagePreviewPanel` (non-activating) above it;
✕ removes, a click elsewhere opens. `TodoItem.attachments` stays only for the
few to-dos made in the first pass.

### 2026-09-27 one icon family: Lucide

Every icon that was an SF Symbol is now a Lucide icon (lucide.dev, ISC —
Resources/LUCIDE-LICENSE.txt): 73 template SVGs in Assets.xcassets/Lucide,
drawn through `OttoIcon(symbol, pointSize:)` (SwiftUI) and
`Icons.nsImage(_:pointSize:)` (AppKit). Call sites still pass SF Symbol names;
`Icons.lucide` maps them, so enums and menus that carry a symbol name did not
change. `pointSize` is the font size the old `.font(.system(size:))` gave the
symbol (frame = size × 1.15, same optical size). New icon: add the SVG
(currentColor → #000000) as a template imageset and one line in the map. Do
not reintroduce `Image(systemName:)`; an unmapped name logs
"[OttoIcon] no Lucide mapping" in DEBUG. Hand-drawn shapes (onboarding icons,
note toolbar glyphs, checkboxes) were already drawn on the same 24-pt stroke
grid and stay.

### 2026-09-27 calendar: the Mac's Calendar only

Google as a calendar source is switched off (`CalendarStore.Source.available`
returns only `.macOS`; an install that had chosen Google reads the Mac's
Calendar). Google accounts added in Internet Accounts still carry Meet links
in the event notes, which `VideoCallDetector` already finds. The OAuth code
stays for later — a direct sign-in needs Google's app verification (sensitive
scope) and ideally a domain. Otto already re-reads every 10 s, calls
`refreshSourcesIfNecessary()` and reacts to `EKEventStoreChanged`; the real
lag is Calendar.app's per-account "Refresh Calendars" interval, so Settings ›
Calendar now tells people to set it to Every minute.

### 2026-09-27 onboarding polish

- ~~The window is drawn 10% larger than the design~~ **REVERTED 2026-09-29.**
  It scaled the hosting view's bounds (860×500) inside a 946×550 frame, and
  SwiftUI does not map mouse events through a bounds scale: clicks and hover
  landed ~10% right/down of the pointer, so no button worked (only ⏎) and a
  click on Notes hit Meetings. Back to 860×500 with bounds == frame. A larger
  onboarding must scale the design's values (`OBMetric`, fonts), never the
  hosting view's bounds.
- Permission chips sit ON the rings (`PermissionsPanel.onRing`); a third chip
  (bolt) shows the usage-data toggle, which is back on the permissions step,
  on by default, recorded at finish.
- Confetti falls from above under gravity and fades out; nothing stays.

### 2026-09-27 opt-in telemetry and feedback

See `docs/TELEMETRY.md`. Anonymous usage counts go to a Cloudflare Worker + D1
(EU) in `server/`, only with consent (asked once, on the onboarding's last
step, checked by default — Marcello's call, knowing a pre-ticked box is weak
consent under EU law; no prompt after updates); events are a
closed enum and the server refuses any string that is not enum-shaped, so no
user content can be stored. The Sparkle feed stays on raw GitHub for now (no
domain). Feedback is a Raycast-style window from the gear menu; Send relays it
through the Worker to ottoapp.feedback@gmail.com by email (Resend) — nothing
is stored, and no mail app is involved (Marcello chose this over mailto). Two
explicit exceptions, chosen by Marcello: the feedback window is a separate
window (principle 1), and a sent feedback is not mirrored into the vault
(principle 7) — it is a message, not the user's data.

### 2026-09-27 panel menus: one placement, neutral states

The gear menu and the Notes · Meetings dropdown are both drawn by TodoTabView,
placed against the control that opened them (`menuAnchor` / `anchoredMenu`):
trailing edges flush, `OttoMenuStyle.anchorGap` (8) away, above or below.
The dropdown moved up from its header because rows inside it never received
clicks there; now a real-click test (`kind-click-pid`, NSWindow.sendEvent)
confirms the Meetings row switches the view. Highlight is the neutral
`SpaceInk.a(0.08)` wash on hover/keyboard only, never cyan and never lit on
open (Insights used to carry a standing tint); "current" is a check or weight.

### 2026-09-26 onboarding v3

From Marcello's `otto-onboarding-v3` handoff (SPEC.md + PNGs + reference HTML),
over Direction B. Window 860×500, panel 490×480. Steps keep their raw values
(`welcome, discover, style, shortcut, permissions, done`), so a B flow
interrupted on focus/notch resumes on discover/style without migration;
`onboarding.focus` is deleted on sight.

- Discover: a three-stop tour (Tasks, Notes, Meetings) with a stepper and page
  dots; Next/Back walk the stops, nothing is saved. Previews and confetti live
  in `OnboardingPreviews.swift`; the Google Meet mark is the `GoogleMeet`
  imageset.
- Style: "In the notch" = `NotchLayout.container`, "Floating panel" =
  `.panels` — the same `notchLayout` key Settings shows, written through
  `AppState.setNotchLayout`, now the only path that switches layouts (Settings
  uses it too). Default notch unless a layout was already set. "Open Otto"
  writes the shown mode, then expands it.
- Shortcut: Continue is disabled until `.quickEntryFired`; the panel crossfades
  to green. The keycaps' ⌃ and ⇧ are not in Host Grotesk: ⌃ is the system face
  small and heavy, ⇧ is Arial Unicode MS — the two that match the PNGs.
- Content sits 48 pt under the body PLUS the column's 10 of spacing: the spec
  says 48, but its HTML (10-pt gap + 48-pt margin) and PNGs draw 58, and the
  PNGs win on visuals.

Deliberate departures, as in B: still no Accessibility row or bolt chip (the
Carbon hotkey needs no grant), so `G` grants Calendar, the first row with a
Grant button. The spec's "grant Accessibility" escape hatch on step 4 becomes
"Shortcut taken by another app? Continue anyway" (⌘→), shown only when
registering ⌃⇧N failed (`HotkeyManager.quickEntryRegistered`), with a local
monitor counting the press meanwhile. Preview copy is localised (EN/IT); the
design's "Roos" became "Simon" (generic names only).

DEBUG: `onboarding-snap <dir>` writes every v3 screen/state (dark and light)
named after its PNG; `onboarding-flow-test` walks the keyboard flow through
the real key handler and logs each step. Both open the onboarding window on
screen and reset `onboarding.lastStep` / `notchLayout` afterwards.

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
  L ≤ 0.52 on light). Pill fill, checkboxes, capture circle, caret, and selection
  all read it; `colorHex` survives only for old files. The New
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
  full-width ground is drawn by `ActionTextView.drawBackground`. ⌘⇧C / ⌘⌥⇧C
  in an open note. (Toolbar superseded 2026-09-26, see below.)
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
- Follow-up the same day: menu rows were unclickable — the note rows' AppKit
  click catchers outrank SwiftUI, so the click opened the note under the
  menu. While the menu is open the stream is hit-test-disabled, the catchers
  return nil, and outside clicks close it through a SwiftUI layer (an AppKit
  MenuDismissCatcher there would outrank the menu too). DEBUG `kind-hit-pid`.
- One menu look (`OttoMenuStyle` / `ottoMenuSurface`, AvatarMenu.swift): gear
  menu, Notes · Meetings and the Aa block menu share radius, ground, rows and
  the cyan current/hover fill. The Aa menu keeps its system popover chrome.
- Scroll foot: `ProgressiveBlur` (private `CABackdropLayer` + `variableBlur`,
  looked up by name, draws nothing if absent) over the list's gradient fade —
  radius ramps to 8 at the pills. The Notes stream now uses the lists' edge
  effect and budget (it subtracted a container-only 36 and hard-clipped).
  2026-09-26 (Figma): the blur is the BAR's, not the list's — a background of
  the floating `TodoTabRow`, from the block's bottom edge to 40pt above the
  pills (657×90). At the list's foot it sat above Completed and read as a haze
  mid-panel. The list keeps only its fade.

### 2026-09-26 floating footer blur correction

The bar-background blur above compiled but sampled empty space: the scrolling
region ended before the pills. In floating browsing, the 95pt footer now overlays
the scroll view, and the list (including Completed) runs underneath it. A 95pt
end spacer lets the last row scroll clear of the pills. The footer is
`ProgressiveBlur`: a private `CABackdropLayer` + `variableBlur` whose RADIUS
ramps (t², 0 → 14pt) to the window edge, plus a faint ground-colour tint. A
`.withinWindow` `NSVisualEffectView` with an alpha mask was tried first and
rejected: its radius is constant, so a half-transparent material over sharp
rows reads as a fade, not a blur ("c'è solo una sfumatura"). It remains only
as the fallback if the private classes disappear. The AppKit host and the
whole block clip to the same 24pt lower corners. It appears as soon as the list reaches the footer, before it exceeds
the panel's full height; the prior full-height check left rows visible through
the pills on lists that were one footer-height short of the cap. Container
browsing and the Notes stream retain their prior height and edge handling.
Follow-up the same day: the blur reaches 64pt above the pills
(`floatingFooterBlurDepth` = 95 + 24; 40 sat too close), and the Notes/Meetings
stream gets the same floating footer — its floating budget no longer subtracts
the space bar, it runs under the pills with a 95pt end spacer (outside its
height measurement) and reports `FootBlurVisibleKey` like a list.

### 2026-09-26 Notes rich text: Code, Block quote, Code block

From `NOTES_RICH_TEXT_FORMATTING_SPEC.md` (Slack's three formatting verbs, Notes
only — no other surface shares `NoteEditorController`).

- The model stays the note's markdown string: inline code `` `…` ``, a code
  block is a ``` fence, and the new `NoteBlock.quote` is `> ` per line (an
  empty quote line is a bare `>`). No schema change, no migration: old notes
  have none of these markers and load as before, and Notes.md mirrors them.
- Typed literals stay literal: a backtick outside code is written `` \` ``
  and a body line starting with `>` is written `\>`, so neither can come
  back as code or a quote.
- Toolbar: `</>` inline code, a rule glyph for Block quote, a boxed `</>` for
  Code block — three buttons, replacing the click/hold/right-click `</>`.
  Also in the Aa menu. Keys: ⌘⇧C, ⌘' (Apple Notes' quote), ⌘⌥⇧C.
- Rules: toggling off only when the whole selection/every touched paragraph
  already has the format, otherwise it applies to all. Inline code covers
  exactly the selection per line (never a list marker or line break) and
  clears B/I/U; B/I/U over a selection skip code; B/I/U and inline code are
  disabled in a code block. Quote ↔ code converts in place. ⏎ on an empty
  quote line, or an empty LAST code line, leaves the block; ⌫ at a quote
  line's start (or a code block's first line) takes the block off. `> ` and
  ```` ``` ```` + space convert as you type.
- Rendering (all drawn, none stored): inline code is a bordered chip in
  `NoteType.codeInk` (orange, deepened on light for 4.5:1); the old stored
  `.backgroundColor` read as a stuck selection. Quote: a 3pt leading rule.
  Code block: ground + hairline, long lines wrap.
- Copy/paste inside notes writes the selection's markdown under
  `com.notchsnap.note-markdown`; a paste into an empty line keeps blocks, a
  paste mid-line joins that line's type, a paste into code is literal.
- Fixed on the way: a blank line inside a code block closed the fence and
  split the block (the serializer read an empty line as body).
- TRAP: `NSLayoutManager` temporary `.kern` does not move glyphs in TextKit 1.
  Chip padding is real `.kern` in the storage, rebuilt after every edit by
  `ActionTextView.applyCodeSpacing` (the serializer ignores `.kern`). The
  detection code's temporary kerning (linked checkbox room) has the same
  limitation and was left alone.

DEBUG: `notes-format-snap <dir>` renders a sample note dark and light;
`notes-roundtrip` and `notes-editor-tests` cover the formats.

### 2026-09-26 Floating panel outside clicks

The floating cards now publish their actual frames in the hosting view's
coordinate space. Outside-click and hit testing use those separate frames,
including the meeting card when present. The empty area above the to-do/notes
card, the gap between cards, and the shadow margin close the panel on one click.
Clicks delivered to another app or another Otto window close it regardless of
screen coordinates; the note's own Save dialog remains attached. The Debug
driver's `panel-hit-regions` command reports the measured screen rectangles.

### 2026-09-26 Empty state B, "the list is napping"

From `Empty state B — spec per Claude Code.md` (Marcello). `EmptyListView`
(`Todo/EmptyListView.swift`) replaces the top-left "Nothing here yet." in every
user list and the old "No notes yet" in the Notes stream: a sleeping page drawn
from the approved SVG (stroke = the section colour; Notes uses its amber), the
title "This list is napping" and one line. Floating panels 120×96; the notch
container 80×64, subtitle dropped under 180pt of budget. z's rise and the page
breathes on a TimelineView; nothing moves under Reduce Motion. In on the
project spring (fade + 0.96 scale), out in 150ms when the first row lands.
One VoiceOver element; not hit-testable, so the caret never leaves the field.

Deliberate departures: the spec's `maxHeight: .infinity` centring is NOT used —
it would break the hug (principle 2). The block's natural height plus 32pt
padding is the area between field and bar, which centres it by construction.
Follow-up the same day (Marcello): in the FLOATING panels the block is a fixed
556 with the pills pushed down by a Spacer, so the hugging page sat high with
all the slack under it. There it takes `minHeight` = the list budget (not a
proposal, so no loop; natural == budget, so nothing scrolls) plus a 5pt nudge
down (8 would be the geometric centre of the real gap; 5 is the optical one).
The container still hugs, with 29 above and 59 below the block.
Today keeps saying nothing when empty (07-26 decision), and Meetings keeps its
own empty state (out of scope). Strings live in `L10n` (EN+IT) — the project has
no Localizable.strings. Empty section `.md` files now read "*This list is
napping.*".

DEBUG: `panel-render` also snaps `space-empty` (first user list with nothing
open). `open -n Otto.app --args -debugCommand "<command>"` runs a driver command
3s after launch, for shells whose distributed notifications never arrive.

### 2026-09-28 crash on open: the panel's frame is pinned

v1.67.0 aborted the moment the notch opened on Marcello's M4 MacBook Pro
(macOS 26.6.2): `NSHostingView.windowDidLayout -> updateAnimatedWindowSize ->
NSWindow setFrame -> NSScrollView setNeedsLayout -> _postWindowNeedsLayout`
throws, uncaught, `abort()`. The same loop as the 2026-08-22 crash, which
`sizingOptions = []` had fixed on 26.6.1 — on 26.6.2 SwiftUI still resizes
the window from inside the display cycle. Two guards now, each sufficient:
`NotchHostingView` lives inside `NotchContainerView` (a plain, click-through
container) instead of being the panel's contentView, and `NotchPanel`
drops every frame request that is not `pinnedFrame` — the frame
`NotchController` computed, updated only in `repositionForCurrentScreen`.
Rule: nothing but the controller sizes the notch panel; if the panel ever
needs a new frame, set `pinnedFrame` first.

### 2026-09-29 text is never black; ← always reaches the bar

- **Notes.** A run with no `.foregroundColor` draws in fixed black, whatever
  the appearance — invisible on the dark notch. Typing after a pasted image
  chip produced one (the caret sat after an attachment character). The note
  view (`ActionTextView`) now keeps the invariant itself: typing attributes
  always carry a colour and never an attachment, `didChangeText` gives any
  colourless run the body ink, and rich text pasted from other apps takes the
  ink of the line it lands in (plain text already does). Rule: every colour in
  a note is one of ours and follows the appearance — black only in light mode.
- **Lists.** ←/→ walk the space bar unless the caret is in a field with
  VISIBLE text. A whitespace-only draft (Esc keeps the text, so it survives
  reopens) used to hold the arrows on that Mac for good; a text control still
  first responder after its space went away (timing-dependent, hence "some
  Macs") counted as editing; ← on a focused, closed row did nothing. All three
  fixed in `TodoBrowsingKeyHandler` (`isEditingText` ignores read-only and
  off-screen editors).

### 2026-09-29 the logo's eyes move (onboarding)

`App/OttoEyesLogo.swift` is the otto-eyes-animation handoff's drop-in view:
the wordmark drawn in a `Canvas`, the holes of the two "O"s moving as eyes
under a `TimelineView` — saccades (11 s), drift (3.7 s), single blinks
(7.3 s, lid from the top), periods deliberately co-prime-ish. Motion values
are the handoff's `otto-eyes-motion.json`, untouched; `preview.html` in the
handoff is the reference to compare against. Static and open with Reduce
Motion. It replaces the static `OttoLogo` on the welcome screen (190 wide)
and the done panel (170 wide), in the palette's `logo` colour; the
permissions tile keeps the static mark (68 wide — below ~40 pt the saccades
stop reading, and a tile icon should not look around). Changes from the
handoff file: `public` and `#Preview` removed, `tPath` marked
`nonisolated(unsafe)` for Swift 6 mode.

### 2026-09-30 feedback batch ("Otto feedback.md")

- **Open animation.** Time Profiler on open/close cycles: a quarter of the
  main thread was `EntityTitleView` rebuilding every title (entity parse with
  a data detector, chip images) and measuring it on each of several layout
  passes per frame. Titles and their sizes are now cached on (text,
  brightness, appearance); `updateNSView` skips an unchanged title.
- **Row width.** Tried a first-line-only gutter (text under the hints on
  later lines); REVERTED 2026-10-01 — see below.
- **No scrollbars** anywhere in the panel (lists, Notes stream, note body,
  meeting pickers); the soft foot says there is more.
- **Completed** clears the whole blur band at the end of a long list (travel
  = blur depth + 16, was one footer).
- **Sections.** "New section" is a dashed pill after the last tab. The bar is
  built in two places (column / over the list's foot), so a fresh bar now
  scrolls the selected section into view on appear.
- **⌘↩ joins.** The draft field swallowed ⌘↩ (caret is there on every open);
  it now joins first when there is a meeting, else files the draft. While a
  joinable alert is up (it opens without the keyboard), ⌘↩ is a Carbon hot
  key, unregistered when the alert goes.
- **Presence** shows the Meet / Zoom / Teams mark, like the meeting card.
- **Drag over the notch** no longer opens it — that opened the retired tray.
- **Hover haptic** is back (slow pointer inside the notch only, ≥ 0.6 s
  apart); "feedback opt-in" in the report was dictation for "aptico".
- **Steps.** ⏎ on a step of a CLOSED to-do opens it first, so the next step
  (or the draft slot) exists to take the caret.
- **Desktop swipe.** Re-pins now go through `pinToOwnSpace()`, which drops
  `.canJoinAllSpaces` on success — before, only the launch pin did, so a pin
  that failed at login and succeeded later still had AppKit carrying the
  notch along the swipe. One retry 3 s after launch. Not verifiable here
  (no synthetic input); confirm on the M4.

### 2026-10-01 row geometry: one gutter, equal insets

From Marcello's mock-up (red bands on both sides). The hint gutter
(`rowActionsWidth`, ⌘↵ / grip / note glyph in one slot) is reserved on EVERY
line — no text ever runs under it — and the hints are centred in the row like
the checkbox. The checkbox's inset from the slab equals the hints' inset
(12 each side), and the capture field's trailing control now ends on the same
vertical (`SpaceChrome.rowTrailingInset` = column inset + row padding = 22),
as does Completed's sparkline. Plain rows carry 6pt top and bottom, so a
single line is still its 37pt floor and a wrapped row keeps air above its
first line and below its last. ↓ onto a row under the floating pills now
scrolls it ABOVE them (`revealRowIfNeeded(footer:)`); the last to-do scrolls
to the very end. DEBUG `panel-render` snaps `row-focused-last` (the longest
list walked down to its last row).

### 2026-10-01 Settings redesign (Direction A, glass-first)

From `SETTINGS_REDESIGN_SPEC.md` (Marcello). Sidebar = `List(.sidebar)` with
three Sections (Otto · Connections · System), nine pages, each a 22pt
gradient tile; pages are grouped `Form`s with a 28pt tile + `.title2.bold()`
header in a top safe-area inset (an empty header-only Section made the next
section's header render as a footer). New pages: Opening (trigger, hover
delay, auto-close, Restore Defaults), Permissions (calendar access + the
stale-sync warning moved from Calendar; the sidebar shows a warning glyph
when access was refused or sync is stale — never-asked is not a warning),
Privacy (moved from General). Updates, onboarding replay and Send feedback
live in About. `VisualPicker` (Buttons, `.isSelected`, ←/→) draws Layout and
Theme thumbnails from system colours. Accent = `SettingsAccent` colour asset
(#2BB3A6 light / #4FD1C5 dark) via `.tint`. Calendar diagnostics are
DEBUG-only. Deviations from the spec, deliberate: icons are Lucide through
OttoIcon (one icon family app-wide), and the Shortcuts list follows
HotkeyManager, which the spec's table misread (⌃⇧N is New to-do, ⌥⌘N toggles
the field, ⌃⇧E opens Notes). All storage keys unchanged. DEBUG
`settings-snap-pid <pid> <dir>` renders every page and the sidebar in light
and dark (pages alone: a split view does not draw into cacheDisplay).

Second pass, same day (Marcello, against System Settings): the system accent
(the SettingsAccent teal is gone); no header inside the page — the title sits
in the toolbar beside ← → history buttons; a "Search settings" field heads
the sidebar (title + keyword match); every control is centred on its row via
`SettingRow` (Form's label slot aligned controls to the label's first line).
The hover slider rounds to 25 ms itself instead of `step:`, which drew ticks.
Third pass (2026-10-01): sidebar groups have no titles (gaps only);
shortcuts are one keycap per key; settings changes apply without animation
(the Hover delay row cross-faded over Auto-close); the layout/theme pickers
take focus as a whole (no square focus ring per thumbnail). The image-chip
preview now also closes whenever the notch leaves `.expanded`.

### 2026-10-02 small polish batch

Settings ← → use SF Symbols (System Settings' own arrows — a deliberate
exception to Lucide). Row hints lose their separator; the gutter is 52 (was
60), so titles get 8pt more. Entity chips have light-mode pairs
(`DSEntityChip`, resolved per appearance into the cached chip image; DEBUG
`entity-chip-snap-pid`). The Notes pill is a pill like the rest (no dashed
edge). The Notes/lists divider is a dynamic overlay, visible in light. The
Notes · Meetings dropdown sits 15pt from the right edge — the same as from
the top.

### 2026-10-02 "the app doesn't open" on a colleague's Mac

Diagnosis from her troubleshooting log: Otto WAS running (notarized, alive,
EventKit traffic, no crash) — twice — and showed nothing. Causes and fixes:
- **Leftover preferences.** She had tried pre-Otto NotchSnap months earlier
  and deleted it; ~/Library/Preferences/com.notchsnap.app.plist survived
  with `onboardingVersion = 1`, so Otto skipped the onboarding and, having no
  window or Dock icon, drew nothing. `AppDelegate.needsOnboarding()` now also
  runs it when that flag is set but the usage question was never answered
  and not one to-do or note exists.
- **A launch that shows nothing.** Opening Otto by hand (not as a login
  item — read from the launch Apple event in willFinishLaunching) now opens
  the notch on the to-dos; so does clicking the app while it runs
  (`applicationShouldHandleReopen`).
- **Two copies.** Release builds are single-instance: a second launch (from
  the mounted DMG, or the binary run from Terminal) posts `ottoShowRequest`
  to the running copy and quits. Debug builds are exempt so Xcode runs beside
  the installed app.

### 2026-10-02 container fixes, chip spacing

- Container menus: see 2026-10-03 (the height-growing fix was replaced).
- Container draft field accepts pasted/dropped images (`allowsImages`), and
  measures its height from the chipped string.
- Note body: a 28pt fade above the toolbar replaces `.clipped()`; the text
  view's inset is 14 top and bottom so the last line can scroll clear.
- Image chips carry no margin; `AttachmentStore.spaceChips` kerns 6pt only
  where text touches a chip (to-do rows, both fields, notes), so a wrapped
  chip sits on the text column. Titles holding a chip get 4pt line spacing.

### 2026-10-03 Meeting Lab

Settings › System › Meeting Lab (Debug builds always; Release only with
`defaults write com.notchsnap.app ottoDeveloperTools -bool true`, then
reopen Settings). Schedules fake meetings in memory — never a calendar
write — that go through the real path: merged into `meetings` on every
refresh (sorted with the real ones; notes only see real ones), evaluated
every 2 s by a lab ticker, so the ambient dot, the self-opening alert, Join,
Snooze and auto-snooze all run as for a real invite. Quick tests are timed
against the alert lead ("Alert in 1 minute" starts at lead + 1). Replaces
the old DEBUG-only `injectTestMeeting` (the `meeting <min>` driver command
now goes through the lab). Verified: `meeting 6` with a 5-min lead shows the
ambient dot at once and the alert 60 s later.

### 2026-10-03 meeting alert keys and a silent-alert bug

- Alerts were skipped for good whenever the notch had been closed on an open
  note (the notch reopens where it was closed, so `openNoteID` stayed set);
  the "don't interrupt a note" guard now applies only while the notch is
  expanded. Found with the Meeting Lab.
- While an alert is up, the panel's key handler owns ⌘↩ (Join) and plain S
  (Snooze, unless a field is taking the letter) — S was never wired, and ⌘↩
  fell to the list (completing a focused to-do). The Carbon ⌘↩ hot key
  still covers Otto in the background; `cal-status` reports its
  registration (it fails silently if another app already owns ⌘↩). Plain S
  is deliberately NOT a global hot key: it would eat the letter from
  whatever the user is typing in.
- Auto-snooze fill: a straight-edged rectangle clipped by the capsule.

### 2026-10-03 presence glyph placement, Zoom/Teams marks

The collapsed notch's meeting glyph sits 10pt from the silhouette's outer
edge (it was centred in the wing, ~20pt in) — the same distance the
countdown keeps on the other side — and the dot sits on the label's
baseline, centred on the x-height. Zoom and Teams use real marks:
`platform-zoom` (drawn as SVG) and `platform-teams` (the official SVG Marcello
supplied); MeetingPlatformIcon already preferred a bundled asset. DEBUG
`presence-snap-pid` renders every platform's indicator and the card icons.

### 2026-10-03 container menus hang past the notch, glass look

The notch keeps its height; the container's gear and Notes · Meetings menus
are drawn by `ContainerMenuLayer` at NotchRootView level (above the
silhouette's clip), placed from anchors TodoTabView publishes in the root's
space (`NotchController.containerMenuAnchors`). The menu's screen frame
(`overflowMenuRect`) counts as the panel: hit-tested, inside for outside
clicks, and the pointer-left close ignores it. EXPERIMENT: those menus use
`ottoMenuGlass` — real glass with a black tint, a lit gradient hairline,
brighter hover rows and one keycap per key (Raycast as the reference). The
floating panels' menus are unchanged. `menu-status` reports the overflow
rect. Verified: a 212pt notch stays 212 with the menu open, and the menu
reaches ~220pt below the silhouette.

### 2026-10-03 container: one side line

`listInset` and `tabsInset` now equal `barOuterInset` (16): the field, the
section bar's Notes pill and gear, every to-do slab and the notes stream
share the field's edge. Row content keeps the field's inner 20 (to-dos) /
22 (notes), so checkboxes and text did not move. `barRadius` 24 → 16.

### 2026-10-04 empty state "Peekaboo"

From the otto-empty-state handoff. `EmptyListView` (lists and the Notes
stream, both layouts) now draws `OttoPeekLogo`: the mint logo rising from an
invisible edge, looking around, blinking once and sinking, on the handoff's
own TimelineView + Canvas keyframes (unchanged). Copy: "All clear in here" /
"Otto is peeking for your next to-do." (notes: "…next note."), IT
translated; the Markdown placeholder follows. Floating: 200pt logo, 26/16
type; container: 150pt logo, 22/14 type. The old hugging / budget-centring
rules are kept (principle 2), not the handoff's `maxHeight: .infinity`.
Animates only while the notch is expanded; static under Reduce Motion.
Departure: on the floating panels' glass the pupils are erased with
`.destinationOut` inside the Canvas (no flat colour behind to fill them
with); the container fills them black as the handoff does. The sleeping-page
drawing is gone. DEBUG `empty-snap-pid` renders both variants over the loop.

### 2026-10-04 container: a detached meeting card under the notch

The container had no upcoming-meeting surface: a meeting appeared only as
the alert that took over the whole panel (MeetingAlertView, now deleted).
`ContainerMeetingCard` (NotchRootView) hangs a black card 12pt under the
silhouette, the notch's width, with the floating panels' `LabMeetingCard`
inside — same rule (root level only; the active alert, else the next meeting
today), Join / Snooze / auto-snooze included. The alert no longer replaces
the to-do panel in the container. The card's screen rect
(`containerCardRect`) joins the overflow menu in `isInExtraPanelArea`: hit
testing, outside clicks and the pointer-left close all treat it as panel.
The panel window is 190pt taller to leave room for it. `menu-status` reports
the card rect. Verified: 621 wide, 12pt under a 253pt silhouette.

### 2026-10-04 copy keeps images; an image drag opens the notch

- **Copy out of a note** (`ActionTextView.writeSelection`): RTFD embeds each
  chip's image file (Notes, Mail, Pages, TextEdit), HTML inlines it as a
  data URL (Docs, Notion, Gmail), plain text keeps the words only. Colours
  are stripped on the way out — labelColor written out was white. Note-to-note
  paste still reads the private markdown type first. Probe: `notes-copy-test`.
  Chat boxes (ChatGPT, Claude) read neither RTFD nor inline HTML images, so
  the FIRST image also goes as `public.png` on the same item (one item: no
  app pastes it twice). Right-click on any chip → Copia immagine.
- **Drag an image onto the notch** opens it on the page it was left on, held
  300 ms; only an image (a browser tab crossing the top never opens it). Two
  dead ends first: the shared `.drag` pasteboard stays EMPTY through a Finder
  drag (the session has its own — the old tray code read the wrong one), and
  the global monitor hears no events mid-drag. What works: after a press
  elsewhere, once the pointer travels with the button down,
  `DragCatcherPanel` — an invisible drop target over the notch — goes up
  until release. Being a drop target is the only way to see what a drag
  carries. It accepts images only, opens the notch, and steps aside so the
  drop lands in the note or the to-do draft field.
