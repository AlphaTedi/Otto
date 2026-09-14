# Meeting notes — 1.48.0

Implements the meeting-notes PRD supplied on 13 September 2026 on top of
QuickNote, NotesStore, TodoStore and the existing TextKit editor.

## Behavior

- Every meeting-card variant offers Notes, including meetings without a call URL.
- Opening an event starts a contextual draft, with no persisted note until writing.
  Task drafts retain their note/event context in a versioned local envelope.
- Meeting notes are searchable in the permanent Calendar space beside Notes and
  remain available offline. The former All/Meeting row inside Notes was removed.
- Tasks are real list items. Their durable `meetingNoteID` is independent of an
  editable source phrase. Session tasks, previous open actions, and archived
  completions are projections, not duplicate task records.
- Previous sessions and manual conversation linking live in the existing Notes
  space. Linking moves only the selected note and can be undone. Duplication
  produces a regular note. Deleting a note leaves its tasks intact.
- Notes JSON has validated backups and visible failures. Neither a failed JSON
  recovery nor an export failure erases the previous readable Markdown mirror.
- Completions carry UUID and meeting provenance in optional v1 comments. Legacy
  archives remain readable; equal titles completed in one minute remain distinct.
- Entering from an alert cancels its timers without collapsing. New alerts do not
  replace an open note; ambient notification continues.

## Identity and EventKit boundary

Google identity is qualified by account and calendar. Recurrences use the series
ID and originalStartTime, never the displayed start or meeting title.
Reference: https://developers.google.com/workspace/calendar/api/guides/recurringevents

The installed EventKit SDK confirms occurrenceDate is the original scheduled
instant and survives detachment, but eventIdentifier may change on calendar moves
or sync. Automatic EventKit series matching is therefore deliberately disabled:
real resync/move/account-recreation fixtures were not available for validation.
Single events match qualified local event IDs while those IDs remain stable.
Unresolved events can be written independently and manually linked to a conversation;
the app never guesses by title, participants, or call URL. Such notes remain in
Notes even if the provider cannot find them again. A session-local lookup avoids
repeated opens creating duplicates while the event remains available.

## Keyboard

The Calendar pill opens the meeting-note stream; its calendar-plus button opens
the meeting selector. Arrows/Return select and Escape backs out.
Control-Tab / Control-Shift-Tab cycle body, task draft, task rows, contextual controls.
In the draft, Tab cycles the real destination list and Return submits. On task rows,
Space toggles completion and Return edits. In contextual controls, H opens history,
L links conversations, A expands previous actions, C expands completions, U undoes
linking. Command-F in the Calendar stream searches meeting notes. Existing Option-Return
conversion and rich-text shortcuts remain available in the note body.

## Verification

- Debug and Release builds with xcodebuild.
- `meeting-notes-tests`: 33 checks, zero failures. Qualified identity, moved Google
  instances, ambiguity, old decoders, first-edit materialization, reload, validated
  backup, corrupt-primary/backup preservation, write failure, archive UUID collisions,
  renamed-task uncompletion, legacy archive and failed archival retention.
- Existing editor: 19/19; Markdown round trips: 21/21.
- Runtime: blank contextual note remained unpersisted, body was first responder,
  a second injected alert left the editor intact. Container measured 326pt; panels
  retained their existing 556pt shell budget. Original layout restored afterwards.
- Screen capture is unavailable in this environment; pointer feel and VoiceOver
  have not been visually certified. No calendar events were modified by tests.
