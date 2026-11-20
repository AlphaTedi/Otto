---
name: otto-design
description: Otto's design system — use BEFORE writing or changing any SwiftUI view, component, colour, font, spacing, icon, menu, tooltip or animation in the notch (Floating Panels or Notch Container). Also when asked to build a new feature with UI, restyle something, or when a result "looks off", "doesn't match Otto", or needs to be "consistent".
---

# Building UI in Otto

Otto already has a look. A new feature is a COMPOSITION of what exists, not a
new design. The full reference is `docs/DESIGN_SYSTEM.md` — read §2 (surfaces),
§3 (tokens) and §4 (component table) before writing a view.

## The workflow

1. **Find the nearest existing screen** that does something similar (a list,
   a page with a ContextBar, a menu) and mirror its structure.
2. **Pick components from the table in DESIGN_SYSTEM.md §4.** Buttons are
   `PrimaryActionButton` / `DSIconButtonStyle`; checkboxes `DSCheckbox`; rows
   `.dsRowBackground`; menus `DSMenuRow` + `.ottoMenuSurface()`; keys
   `Keycap` / `KeyBadge`; tooltips `.ottoTooltip`; icons `OttoIcon`.
3. **Style only with tokens:** `@Environment(\.dsPalette)` for colour roles,
   `DSType` for fonts, `DSSpace` for padding/spacing, `DSRadius` +
   `DSShape.squircle` for corners, `DSSize` for control sizes, `Motion.*` and
   `DSTransition` for animation.
4. **Never branch on the layout for styling.** The surface (`.panels` /
   `.container`) arrives through the environment; the palette resolves it.
   `isContainer`/`usesDock` are only for structurally different furniture.
5. **Keyboard path + tooltip** in the same change (CLAUDE.md).
6. **Check:** `Scripts/design-lint.sh` must be clean (the PostToolUse hook
   also runs it on every Swift edit and reports back — fix what it says, or
   justify the line with `// ds-allow: <why>`). Build, then render with the
   `verify` skill (`panel-render-pid`, `gallery-render-pid`) and LOOK at the
   PNGs in both layouts.

## When nothing fits

Extend an existing component with a parameter first. Only if that would
distort it, add a new one following DESIGN_SYSTEM.md §6: in
`Otto/DesignSystem/`, tokens only, works on both surfaces, added to
`DSGallery.swift` and to the §4 table, duplicates deleted in the same change.

For genuinely new MOTION (a morph, a gesture-driven spring) also read the
`fluid-animations` skill — then express the result as a `Motion` token.

## Never

- `.font(.system(size:))`, `Color(hex:)`, `.white.opacity(…)`, literal
  `cornerRadius:` or off-scale padding in a view.
- Inline `.spring(...)`/`.easeOut(...)`, or `NotchAnimation.*` outside Notch/.
- `Image(systemName:)`, `.help()`, SwiftUI `Menu`.
- A private copy of a keycap, checkbox, button, menu row or pill.
