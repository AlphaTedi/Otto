# Otto — Architecture

How the code is organised and how the pieces connect. Read this before adding
code; read `docs/CONTEXT.md` for *why* things are the way they are (product
principles, platform traps, decision log).

## The repository

```
Otto.xcodeproj      one target, one scheme: Otto. Sparkle is the only package.
Otto/               all app source and resources (a synchronized folder, below)
Config/             Info.plist, Otto.entitlements, Local.xcconfig(.example)
Scripts/            release.sh (sign, notarize, DMG), lab.sh (Otto Lab build),
                    diagnose-calendar.sh (run on a Mac where calendar fails)
server/             Cloudflare Worker: opt-in telemetry + feedback relay (TypeScript)
docs/               this file, CONTEXT.md, DISTRIBUTION.md, TELEMETRY.md,
                    and the GitHub Pages site (index.html, privacy.html)
appcast.xml         the Sparkle update feed that installed copies poll
```

`Otto/` is a **synchronized folder**: Xcode compiles every `.swift` file in it
and bundles everything else as a resource. A new file needs no project edit —
put it in the folder it belongs to. Keep scratch files and generated output
(graphify-out, notes) outside `Otto/`, or they ship inside the app.

## `Otto/` — one folder per feature

| Folder | What lives there |
|---|---|
| `App/` | Entry point and app-wide plumbing: `OttoApp` (`@main`), `AppDelegate` (launch sequence), `AppState` (settings + measured panel heights), `AppSettings` (persisted settings), `AppBuild` (Otto vs Otto Lab, the data folder), `AppNotifications` (every `Notification.Name`), `HotkeyManager` (global shortcuts), `UpdateController` (Sparkle), `LaunchIntegrity`, `Localization` (EN + IT strings) |
| `Notch/` | The notch window and its two layouts: `NotchController` (the panel, the idle → hovering → expanded state machine, mouse/keyboard monitors, open/close policy), `NotchPanel` (the `NSPanel` + hosting view, hit-testing), `NotchRootView`, `NotchShapeView` (the silhouette), `FloatingPanelsView` (the default layout: meeting card + to-do panel hanging below the notch), `NotchPresence` (the countdown in the collapsed notch), `NotchAnimation` (every spring), `SpaceAnchor` |
| `Todos/` | The to-do product. `TodoStore` + `TodoModels` (data, persistence, panel modes), `TodoTabView` (the whole panel), `TodoTabRow` (section tabs), `TodoBrowsingView` (the list), `InlineDraftRow`, `TodoItemRow`, `StepRows`, `CompletedSection`, `TodoPanelForms` (new section, Quick Find), `TodoBrowsingKeyHandler` (all panel keyboard routing), `ShortcutsOverlay` (the `?` sheet), `InsightsView`, `AvatarMenu` (gear menu), `SpaceChrome`/`SpaceTint` (panel furniture and colour), `EntityParser`/`EntityTitleView` (inline chips), `NLDateParser`, `CompletedArchive`/`CompletionStats`, `TodoPanelSupport` (shared preference keys and transitions) |
| `Notes/` | The Notes space: `NotesStore` (notes.json), `NotesSpaceView`, the editor (`NoteEditor`, `NoteBodyView`, `NoteFormatBar`, `NoteMarkdown`), `MeetingNotes`, `ActionItemDetector`, `NoteTitler`, `NoteRepair` |
| `Calendar/` | Meetings: `CalendarStore` (connection, today's meetings, alert schedule, Meeting Lab), `EventKitCalendarProvider` (the only source: the Mac's Calendar), `CalendarModels`, `UpNextSection`, `AttendeeAvatars` + `AttendeePhotoStore` (faces from Contacts) |
| `Onboarding/` | The first-run window: model, steps, previews, theme, components, `OttoEyesLogo` |
| `Settings/` | The Settings window: `SettingsView` (every page), `CalendarSettingsView`, `SettingsWindowController` |
| `Storage/` | What lands on disk for humans: `MarkdownVault` (the Markdown mirror of to-dos and notes) and `Attachments` (images pasted into notes and to-dos) |
| `Telemetry/` | Opt-in usage counts (`Analytics`, `AnalyticsEvent`) and the feedback window — both talk to `server/` |
| `DesignSystem/` | `DesignTokens` (DSColor, DSSpacing, DSRadius, DSFont — the only source of styling), `DesignComponents`, `OttoIcon` (Lucide icons), `LiquidGlass`, `SharedGlass`, `ProgressiveBlur`, `HapticManager`, `SoundManager` |
| `Intents/` | App Intents (Shortcuts, Spotlight, Siri): thin wrappers over `TodoStore` |
| `Debug/` | `DebugDriver` (DEBUG-only headless test side door) and `MeetingNotesVerification` |
| `Resources/` | Assets (app icon, Lucide icons, meeting platform marks), the Host Grotesk font, sounds, licences |

## Launch

1. `OttoApp` starts `AppDelegate`. It has no visible scene: Otto is an
   accessory app (`LSUIElement`).
2. `applicationDidFinishLaunching` (Release only) hands over to an Otto that is
   already running and quits. Then it applies the theme, shows the onboarding
   window if it has never finished, starts `HotkeyManager`, installs
   `DebugDriver` (DEBUG), records the launch for analytics, and calls
   `NotchController.shared.setup()`.
3. `setup()` creates the `NotchPanel` — a transparent, non-activating window
   over the notch, on every Space — hosting `NotchRootView`, and installs the
   mouse and keyboard monitors.

## The notch, open

`NotchRootView` draws one of two layouts (`NotchLayout`, Settings › Notch):

- **Panels** (default): the silhouette stays small. `FloatingPanelsView` hangs
  separate glass cards below it: the next meeting, then the to-do panel.
- **Container**: the silhouette itself grows and `TodoTabView` is drawn inside it.

Either way the content is `TodoTabView`. Its `TodoPanelMode` picks what fills
the panel: the list (`browsing`), a form (`newCategory`, `find`), the Notes
space (`notes`, `calendar`), or `insights`.

**Height hugs content** (product principle 2). The panel measures its natural
height through preference keys and publishes it to
`AppState.todoContentHeight` (container) or `panelColumnHeight` (panels).
`AppState.notchExtraHeight` turns that into the silhouette and window size,
and everything animates on one spring (`NotchAnimation.contentHug`).

**Keyboard.** `NotchController` owns Esc-to-close. Every other key goes through
`TodoBrowsingKeyHandler`, which routes by panel mode. A new action ships with
its key in the same change, plus a line in `ShortcutsOverlay`.

## Data

| Store | File | Notes |
|---|---|---|
| `TodoStore` | `Todo/todos.json` (+ `todos.backup.json`) | Debounced atomic writes; restores from the backup on a bad read |
| `NotesStore` | `Notes/notes.json` | Same pattern |
| `AppSettings` | `UserDefaults` key `otto.settings` | Hand-rolled `decodeIfPresent` decoder: a new field needs one line there |
| `MarkdownVault` | `Vault/` (or a folder the user picks) | Write-only Markdown mirror, plus the completion `Archive/` and `Attachments/` |
| `Analytics`, feedback outbox | small queue files | Sent only with consent |

All of these paths live under `AppBuild.supportDirectory` =
`~/Library/Application Support/Otto` (`Otto Lab` for the lab build). An
upgraded install moves its pre-Otto folder there on the first launch that runs
alone. The app is not sandboxed, so this data survives reinstalling.

Calendar data is never stored: `CalendarStore` re-reads EventKit every few
seconds and on `EKEventStoreChanged`.

## Where new code goes

- A new to-do behaviour: put the logic in `TodoStore`, the view under `Todos/`,
  the key in `TodoBrowsingKeyHandler`, and the line in `ShortcutsOverlay`.
- A new system verb (Shortcuts, Siri): `Intents/`, calling `TodoStore`. Never a
  second logic path.
- New persisted user data: a `decodeIfPresent` line in its decoder, and a
  Markdown mirror via `MarkdownVault`.
- A colour, spacing, radius or font: `DesignTokens.swift`, never inline.
- A user-visible string: `Localization.swift`, in both English and Italian.
- A new `Notification.Name`: `AppNotifications.swift`.

## Build and verify

```bash
xcodebuild -project Otto.xcodeproj -scheme Otto -configuration Debug build
```

Runtime checks go through the `verify` skill (`.claude/skills/verify/`): a
Debug build listens for `otto.debug.command` distributed notifications and
writes its state to `/tmp/otto-debug-state.txt`. The bundle id
`com.notchsnap.app` is the one place the app's pre-Otto name remains, on
purpose (it is the TCC identity, the preferences domain and Sparkle's update
identity).
