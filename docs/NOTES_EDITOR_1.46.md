# Notes editing — 1.46.0

The editor remains AppKit NSTextView / TextKit with Markdown persistence.
Apple's public Notes guide is the behavioral reference, not a claim that its
private editor implementation is available:
https://support.apple.com/en-gb/guide/notes/apd93c815aa0/mac
https://support.apple.com/en-asia/guide/notes/apd1955d3b21/mac

## Changes

- Suggestions draw temporary TextKit underline/strike/color attributes instead
  of writing presentation into editable rich text. Checklist strike-through and
  user underline remain intact. Detection metadata is removed from the serializer's
  copy so it cannot split bold/italic markup into adjacent fragments.
- Selecting text exposes a + action; Option-Return opens the same section picker.
  Existing linked tasks have persistent completion controls and Option-Return
  toggles their completion. Numbers 1–3 select the first sections; arrows and Return
  reach all sections; Escape cancels. Editing retains normal mouse selection.
- The action controls use a reserved trailing gutter, and the picker sits below
  the editor with a phrase preview. These deliberately adapt the supplied inline
  mockup to the narrow, scrolling notch: no embedded characters, obscured words,
  or hover-induced reflow. They are not a pixel-for-pixel recreation of variant 16c.
- Duplicate creation is idempotent; edited-away phrases lose their source link;
  deleting a linked task refreshes the note. Manually selected phrases remain linked
  even when they do not match the automatic detector's vocabulary.
- Empty trailing paragraphs format independently of the preceding paragraph.
  Return continues lists; a second Return exits; Backspace at a marker exits.
  Headings return to body. Shift-Return uses a soft line separator within the paragraph.
- Block changes register real undo/redo, preserve selection positions, and stop
  heading weight leaking into body text. UTF-16 caret positions support emoji.
- Note opening no longer replays the rename publisher's initial value. Coordinator
  bindings refresh on note changes and delayed detection is cancelled on teardown.
- Note viewport height follows measured natural text height, capped by panel budget.

## Verification

DebugDriver `notes-editor-tests` exercises the actual NSTextView and controller in
an isolated, undisplayed window, without editing personal notes. It covers list
continuation/exit/body typing, headings, trailing paragraphs, Unicode, temporary
mark preservation, soft returns, Backspace, undo/redo and numbering from 9 to 10.
`notes-roundtrip` covers 21 existing Markdown examples.

Automatic detection remains conservative local Italian/English rules. This change
is not a complete clone of Apple Notes (tables, attachments, collaboration and
collapsible headings are outside this editor's current format model). Pointer feel
and visual alignment still need interactive assessment in the user's normal panel.
