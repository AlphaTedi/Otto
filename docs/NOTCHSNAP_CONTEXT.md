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
3. **Creation is never implicit.** Nothing is written to the store as a side effect;
   an explicit action always commits.
4. **No permanent shortcut legends.** Hints appear contextually (focused row),
   on modifier-hold, or in an on-demand `?` overlay.
5. **Replace, don't add.** When a spec supersedes an element, delete the old one in
   the same change (this was a repeated failure mode — see §7).

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
  freeform block; steps are a separate checklist ending in an always-open empty row
  (type, `⏎`, and the caret lands on the next one — no "add step" button exists).
- **Natural-language dates** in the title ("tom" → due date), highlighted inline in the
  accent colour and stripped only on Create.
- **Inline entity chips** in titles — links (clickable, host-shortened), dates,
  `@mentions`, `` `code` `` — rendered with `NSTextAttachment` in a real wrapping text
  flow (SwiftUI `Text` concatenation cannot embed views inline).
- **Urgency**: 9 px dot for Medium/High only (Low is the silent default), with an
  immediate hover/focus tooltip reading "Medium priority"; the creation combo always
  spells out the full phrase.
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
| 08-16 | Clicking dead panel space blurs the draft as well as ending a row edit | "Stop typing" cannot mean one of the two live editors and not the other |
| 08-16 | Close policy rule 8 WITHDRAWN — a global-shortcut capture no longer closes the notch | The new row is at the top of the list where you can see it; closing over it hid the only confirmation anything happened |
| 08-16 | `WordKeycap` for named keys (Tab, Esc), separate from `Keycap` | `Keycap` draws one cap per character by design ("⌘↩" is two keys), so "tab" rendered as t·a·b and read as a three-key chord |
| 08-16 | Tab ORDER alone decides where `⌃⇧N` files; the FB8 "set as default" item is gone | Two mechanisms for one outcome, and the invisible one won — dragging Work to the front still left the shortcut on Personal with nothing on screen explaining why |
| 08-16 | Tab drag uses the indicator-only (Arc) model, like the to-do list | Live re-slotting in `dropEntered` shifts every tab sideways under the cursor, which fires the next `dropEntered` — the tabs flip-flopped for as long as the drag was held |
| 08-16 | A category tab is NOT a `Button` | A SwiftUI Button on macOS claims the mouse-down, so an `.onDrag` beside it never starts a drag session at all. This is why tabs could not be dragged while to-do rows — plain views with `.contentShape` + `.onTapGesture` + `.onDrag` — always could |
| 08-16 | The tab scroller is `.scrollDisabled` unless the tabs overflow | A horizontal ScrollView and a sideways drag want the same gesture and the ScrollView wins; while every tab is visible the scroller could only cost the drag |
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

## 8. Open threads

- **Google OAuth provider** — the structural fix for calendar sync fragility; reads
  Google's API live. Needs a Google Cloud OAuth client ID from Marcello. The
  `MeetingProvider` seam exists for it.
- **Voice capture** — complete but shelved; the microphone path is the only part never
  verified end-to-end.
- **v1.2.0 tag** — the work after `9368510` (feedback fixes, urgency/entity pass,
  default category, drag reorder, voice, calendar) is committed-pending.
- PRD open questions never closed: onboarding moment for the calendar connection;
  configurable "tentative" meetings.
