# B3 dock — parity checklist (notch container)

The B3 colour dock (`OTTO-B3-DOCK-SPEC.md`) redesigns the **notch container**
only, as an experiment: Settings › Notch › "B3 dock (experiment)", Debug and
Otto Lab builds only. Every line below is something the container does today
(audited from the code on 2026-10-14). Each one must still work with the dock
on.

**Status:** ⬜ to do · ✅ verified in the running app · ⚠️ changed on purpose
(see the note). "Same" means the code path is untouched and only the styling
around it changes.

**Mechanism.** One flag, `usesDock`, which is true only in the container layout,
with the experiment toggle on, in a Debug or Lab build. The roughly 95 existing
`notchLayout == .container` branches stay as they are. The dock replaces only
the furniture: the top field, the tab row, the gear, and the height rule.

**List region.** With the dock on, the list takes the path the floating panels
already use: a fixed budget, a footer overlay with a fade, and Completed inside
the scroll. It does not take the container's hugging path. That path exists and
is tuned, so the dock reuses it rather than rebuilding it.

---

## 1. Opening, closing, the notch itself

| # | Today | With the dock | Status |
|---|---|---|---|
| 1.1 | Hover / click on the notch opens the panel (`NotchController`, trigger setting, hover delay) | Same | ⬜ |
| 1.2 | Global hotkeys (`HotkeyManager`): open/close, ⌃⇧N new to-do, ⌥⌘N quick entry, ⌃⇧E notes | Same; ⌃⇧N lands the caret in the first row (`focusDraft(fromGlobalShortcut:)`, default section = first tab) | ⬜ |
| 1.3 | Open/close spring, staggered entry (`notchEntry`), hand-peek, Dynamic Island notifications, `NotchPresence` countdown | Same | ⬜ |
| 1.4 | Pointer leaving closes while browsing; outside click always closes; the draft survives (KB-11) | Same | ⬜ |
| 1.5 | The panel reopens in the space it was left in; Find / New section reset (`settleForClose`) | Same | ⬜ |
| 1.6 | Container height **hugs** content (`todoContentHeight` → `notchExtraHeight`) | ⚠️ **Fixed 560 pt** (`NotchContainerMetrics.panelHeight`); the list scrolls. A deliberate exception to principle 2, dock only (Marcello, 2026-10-14) | ✅ |
| 1.7 | Width from the size preset (`notchExpandedWidth`, 620) | Same: the spec's 600 is not imposed | ✅ |
| 1.8 | Detached meeting card under the notch (`ContainerMeetingCard`) | Same | ⬜ |
| 1.9 | Image dragged onto the notch opens it; drop routed to the field (`DragCatcherPanel`, `imageDropTarget`) | Same; the router must find the first row (`FocusReportingTextView`) | ⬜ |
| 1.10 | Panel space-pinning (`SpaceAnchor`), step-down during a drag | Same | ⬜ |

## 2. The input (today `InlineDraftRow`, in the dock the first row)

| # | Today | With the dock | Status |
|---|---|---|---|
| 2.1 | A recessed well at the top with the space dot and "What…ing?" | ⚠️ The first row of the list: a dashed 18 pt box (60 %) and a grey placeholder "Add to ‹Space›…"; the box turns solid with a 12 % fill on focus or when non-empty; "↵" keycap when there is text | ✅ |
| 2.2 | ⏎ files into `draftDestination`; the caret stays (`commitDraft`) | Same; the new row drops in (spring 0.32 / 0.7) | ⬜ |
| 2.3 | ⇥ / ⇧⇥ cycle Notes → lists → Notes, keeping the text (`cycleSpace`) | Same | ⬜ |
| 2.4 | ←/→ with an empty field walk the spaces | Same | ⬜ |
| 2.5 | ↓ from the field focuses the first to-do; ↑ from the first to-do returns to the field | Same | ⬜ |
| 2.6 | Esc in the field: steps out keeping the text, and closes if the field is empty | ⚠️ Spec / floating panels behaviour: Esc **clears** the text, and the next Esc closes. Already implemented for `.panels` in `handleDraft`; extend it to `usesDock` | ⬜ |
| 2.7 | ⌘⏎ with the caret in the draft joins the next meeting, otherwise files the draft | Same | ⬜ |
| 2.8 | Natural-language date highlighted inline and stripped on commit (`NLDateParser`) | Same | ⬜ |
| 2.9 | Pasted / dropped images become chips at the caret; right-click a chip → Copy / Open / Remove | Same (the field is still `HighlightingTitleField`, now 15 pt) | ⬜ |
| 2.10 | `ChipLineLayout` keeps a chip line steady; the field height is measured | Same (re-measure at 15 pt) | ⬜ |
| 2.11 | Click on the space dot cycles the destination | ⚠️ The dot is gone. The first-row box is the target; clicking anywhere on the row focuses the field | ⬜ |

## 3. Spaces (today `TodoTabRow`, in the dock `SpaceDock`)

| # | Today | With the dock | Status |
|---|---|---|---|
| 3.1 | One pill per list with name, colour and open count; the active pill is filled | Dot per list; the active item shows "Name count" in the light tint; one shared sliding highlight at 18 % | ✅ |
| 3.2 | Click a pill to select it (180 ms) | Click a dot; Glide motion (§8.1) | ⬜ |
| 3.3 | Drag a pill to reorder (indicator model, `CollectionReorderDropDelegate`, `CollectionEndDropDelegate`) | Same delegates on the dock items | ⬜ |
| 3.4 | Context menu: New section…, Move left, Move right, Delete (not on Today) | Same menu on right-click of a dock item | ⬜ |
| 3.5 | "New section" button after the last tab; ⇧⌘N | Trailing "+" in the dock (30 × 30, `#5E5E63`); ⇧⌘N same | ✅ |
| 3.6 | ⌘1–⌘9 jump to a list | Same | ⬜ |
| 3.7 | The strip scrolls horizontally on overflow; the selected tab is kept in view | The dock scrolls inside its capsule with edge fades; the active item is kept in view | ⬜ |
| 3.8 | Tooltip on the "+" | Tooltip on every inactive dot (name), 12 pt above it, fading and rising | ⬜ |
| 3.9 | VoiceOver: each tab is a button labelled with its name | Button with name and value "N open"; `.isSelected` on the active one | ⬜ |
| 3.10 | The tab row is hidden while a note is open, in Find and in New section (`showsSpaceBar`) | Same rule for the whole bottom bar | ⬜ |

## 4. Notes, Meetings, gear (today the pill row; in the dock the round buttons)

| # | Today | With the dock | Status |
|---|---|---|---|
| 4.1 | Notes pill at the head of the bar | Round Notes button, bottom left; gold when active; the dock dims to 50 % and the highlight hides | ✅ |
| 4.2 | Meetings = the Notes · Meetings switch, ⌘1 / ⌘2 and ⌥⇥ inside Notes | Second round button next to Notes → `.calendar`; ⌘1 / ⌘2 / ⌥⇥ same | ⬜ |
| 4.3 | Gear → `AvatarMenu`: Insights, Preferences, Shortcuts, Notes folder, Feedback, Quit; keyboard ↑↓ ⏎ Esc | Round button bottom right opens the same menu, **upwards** (`anchoredMenu(opensUpward: true)` in `ContainerMenuLayer`) | ✅ |
| 4.4 | ⌘, Preferences · ⌘Q quit · ⌘I Insights · `?` shortcuts overlay | Same | ⬜ |

## 5. To-do rows (`TodoItemRow`, `StepRows`)

| # | Today | With the dock | Status |
|---|---|---|---|
| 5.1 | Checkbox completes, with sound / haptic; completed rows settle out | Same; restyled box (stroke 50 %, filled with a black ✓ when done) | ⬜ |
| 5.2 | Click a row → open details and edit the title (`activateRow`) | Same | ⬜ |
| 5.3 | Keys: ↑↓ focus, Space complete, ⏎ edit, →/← expand / collapse, ⌘⏎ complete, ⌥↑↓ reorder, ⇧⌘M move | Same | ⬜ |
| 5.4 | Drag to reorder (custom gesture, indicator, haptics) | Same | ⬜ |
| 5.5 | Context menu: Edit, Move to…, Delete | Same | ⬜ |
| 5.6 | Details: one note block, steps checklist with a trailing draft row, step keys (↑↓ walk, ⌘⏎ tick, Esc) | Same; restyled | ⬜ |
| 5.7 | Closed-row hints: note glyph, the first two steps plus "N more" | ⚠️ One meta line instead: "1 of 3 · Note · ‹due›" (§5.4); no image count, because images stay chips in the title (decision 5) | ⬜ |
| 5.8 | Due date on a row | Shown in the meta line | ⬜ |
| 5.9 | Image chips inline in the title (hover preview, ✕, click opens) | Same | ⬜ |
| 5.10 | Linked to-dos from note action items (source note / meeting) | Same | ⬜ |
| 5.11 | Hover wash on a row | Same, restyled to `#0E0E10` | ⬜ |
| 5.12 | Click on empty panel space deselects / ends editing (`DeselectCatcher`) | Same | ⬜ |

## 6. Completed (`CompletedSection`)

| # | Today | With the dock | Status |
|---|---|---|---|
| 6.1 | Pinned under the list, collapsible; ⇧⌘C toggles; per-day rows; ⇧⌘A opens / closes all days; "Show all / fewer" after seven days; sparkline; untick a live entry | Same features, **inside the scroll** below the open rows (same position in every space); restyled: text `#6E6E73`, 12 pt semibold headers | ⬜ |

## 7. Empty and special states

| # | Today | With the dock | Status |
|---|---|---|---|
| 7.1 | Empty list: peeking Otto (look, blink) + title / subtitle (`EmptyListView`) | Same, centred between the first row and the dock | ✅ |
| 7.2 | Today (system) list shows the upcoming meetings (`UpNextSection`) and no empty state | Same (Today is not in `visibleCollections`; it is reachable only through its own paths) | ⬜ |
| 7.3 | Insights page (⌘I, gear menu): week stepping, focus, Esc back | Same surface, inside the 560 panel; the bottom bar stays (as `showsSpaceBar`) | ⬜ |
| 7.4 | New section form (`CategoryFormView`), Esc back | Same, inside the 560 panel | ⬜ |
| 7.5 | Quick Find (`QuickFindView`): compiled, but nothing routes into it | Same (no entry point) | ⬜ |
| 7.6 | `?` shortcuts overlay over the panel | Same; add lines for any new binding | ⬜ |

## 8. Notes and Meetings spaces (`NotesSpaceView`, container branches)

| # | Today | With the dock | Status |
|---|---|---|---|
| 8.1 | Composer at the top ("Write a note…"), ⏎ files, ⇧⏎ line break | ⚠️ The first row reads "New note…" (§6.4) and is the composer; same keys | ✅ |
| 8.2 | Stream of notes: ↑↓ select, ⏎ open, click opens; meeting-note rows | Same; note rows restyled (§5.5: title, time, one-line preview, divider) | ✅ |
| 8.3 | Note context menu: Rename, Duplicate, Delete; ⌘⌫ deletes with a five-second undo | Same | ⬜ |
| 8.4 | Open note: title bar with back chevron, body editor, format bar (⌘B / I / U, ⌘⇧C code, ⌘⌥⇧C block, ⌘' quote, ⌘⇧7 / 8 / 9 lists), ⌥⏎ action picker, Esc / ⌘[ back | Same, inside the 560 panel; the bottom bar hides while a note is open | ⬜ |
| 8.5 | Copy a note with images (RTFD / HTML / PNG) | Same | ⬜ |
| 8.6 | Meetings view: search (⌘F), history, link picker, task focus (⌃⇥, H / L / A / C / U) | Same, reached through the Meetings round button | ⬜ |

## 9. Settings, onboarding, telemetry

| # | Today | With the dock | Status |
|---|---|---|---|
| 9.1 | Settings › Notch: layout picker, size presets, trigger | Same, plus the "B3 dock (experiment)" toggle (Debug / Lab only) | ⬜ |
| 9.2 | Onboarding style step (panels vs container) | Same (the experiment is not offered there) | ⬜ |
| 9.3 | Telemetry: `notch_opened{trigger, layout}`, `todo_created{source}`, `todo_completed`, `note_created`… | Same names. ⚠️ `space_switched` / `first_row_submitted` are deferred until the dock graduates: the event enum is closed and `server/` must change with it | ⬜ |

## 10. Floating panels (must not regress)

| # | Check | Status |
|---|---|---|
| 10.1 | With `notchLayout = panels` and the toggle on or off, everything is identical (capture header, footer pills, 556 block) | ⬜ |
| 10.2 | The container with the toggle **off** is identical to today | ✅ |

---

## Verified so far (2026-10-15, headless)

✅ marks lines checked in the running app through DebugDriver (`dock-on`,
`dock-status`, `panel-snap`): a constant 560 silhouette across Grocery, Work,
an empty list and Notes; the first row, dock, round buttons, empty state,
Notes mode and note rows as drawn; the container with the switch off identical
to before. Everything that needs a pointer or a key (hover, tooltips, drag,
⇥ / Esc, motion) is for Marcello to tick in Xcode.

Known gaps in this first pass:
- Row titles stay 14 pt (the spec says 15). EntityTitleView measures its rows
  with TextKit at `todoTitleSize`, so changing the size only for the dock
  needs that measurement threaded through; the first row is already 15.
- Pages is approximated as a slide of the incoming list from the side of
  travel, not a strip of every space laid out side by side.

## Placement decisions (for designer review)

1. The gear opens the **existing menu** (upwards), not the Settings window directly: it holds Insights, Shortcuts, Notes folder, Feedback and Quit.
2. Meetings get a **second round button** next to Notes; ⌘1 / ⌘2 / ⌥⇥ keep working.
3. Images stay **chips in the title**; the meta line carries no "N images".
4. Esc in the first row **clears** first (spec), as the floating panels already do.
5. The space dot's click-to-cycle is gone; ⇥ and the dock replace it.
6. The width follows the user's size preset (620 by default), not the prototype's 600.
7. New telemetry events are deferred to graduation.
