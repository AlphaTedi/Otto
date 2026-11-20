# Otto — Design System

Read this before you write or change any view in the notch. It covers what
already exists and the rules for using it. Most "new" UI is a composition of
what is here, so don't invent new pieces.

- **Code:** `Otto/DesignSystem/` — tokens, surfaces, components.
- **Catalogue:** `Otto/DesignSystem/DSGallery.swift` (an Xcode preview of
  every component, on both surfaces, in light and dark).
- **On the web:** https://claude.ai/artifact/3dJChTxTimC3yu8rvWGMpM, a private
  claude.ai page that mirrors the tokens and components with live previews.
  The code is the source: when components change, update that page too.
- **Render without Xcode:** post `gallery-render-pid <pid> <dir>` to a Debug
  build (see the `verify` skill). It writes `gallery-light.png` and
  `gallery-dark.png`.
- **Lint:** `Scripts/design-lint.sh` (also runs as a hook after every Swift edit).

Scope: the notch, meaning the **Floating Panels** and the **Notch Container**.
Two places are deliberate exceptions and keep their own look:
- **Settings** is a native macOS form.
- **Onboarding** has its own `OB*` theme with Host Grotesk.

---

## 1. Principles

1. **Quiet by default.** Text, a row, a hairline. Colour carries meaning (a
   section's colour, the accent, red for destroy) and is never decoration.
   Nothing glows or bounces unless it is the one thing that must be seen.
2. **One of everything.** One keycap, one checkbox, one row slab, one menu
   row. If a component exists, use it as it is. If it is almost right, add a
   parameter to it rather than copying it.
3. **Roles, not values.** A view asks for `palette.textSecondary`, never for
   `Color.white.opacity(0.55)`.
4. **Replace, don't add.** A new component deletes the copies it replaces in
   the same change.
5. **Keyboard-first and hugging.** Every control has a keyboard path and
   shows its shortcut in a tooltip. Panels never get a fixed height (see
   CLAUDE.md).

## 2. Two surfaces, one vocabulary

| | Floating Panels (`.panels`) | Notch Container (`.container`) |
|---|---|---|
| Ground | Liquid Glass block (`liquidGlass`), radius 24 | the black silhouette itself |
| Appearance | follows system Light/Dark | always dark (`darkGroundSurface()`) |
| Colour values | `DSColor` (semantic, dynamic) | `DSDock` (fixed, tuned for black) |
| Row title | 14 medium | 15 regular |
| Space navigation | `SpacePill` tab row + gear | `DockBar`: dots, round glass buttons |
| Tooltips | `.ottoTooltip` | `.barTip` inside the dock bar, `.ottoTooltip` elsewhere |
| Layout metrics | `PanelMetrics` (FloatingPanelsView.swift) | `NotchContainerMetrics` (DockExperiment.swift) |

**The rule:** `NotchRootView` declares the surface once with
`.ottoSurface(...)`. Components read it from the environment.

```swift
@Environment(\.dsPalette) private var palette      // colour roles
@Environment(\.ottoSurface) private var surface    // only when a SIZE differs
Text(title).font(DSType.rowTitle(surface)).foregroundStyle(palette.textPrimary)
```

- Never branch on `notchLayout`, `isContainer` or `usesDock` to pick a colour
  or a font. Those flags are for *layout and furniture*, where the two
  surfaces really are different structures.
- Code that is not a view (store, key router) reads `DockExperiment.isOn`.

## 3. Tokens

All tokens live in `DesignTokens.swift` and `Surface.swift`.

### Colour roles: `DSPalette` (`@Environment(\.dsPalette)`)

| Role | Use for |
|---|---|
| `textPrimary` | titles, row text |
| `textSecondary` | meta, counts, supporting text |
| `textTertiary` | hints, timestamps, section caps |
| `placeholder` | empty-field placeholder |
| `textDone` | a completed title |
| `glyph` / `iconHover` | resting icon / icon under the pointer |
| `rowHover` / `rowFocus` | list row hover / keyboard focus |
| `card` / `cardBorder` | the opened to-do card |
| `hairline` | a rule inside one surface |
| `fieldWell` | a field sunk into the panel |
| `stepLine` | checklist connector |
| `controlHover` | hover fill behind a pill or small control |

Some colours are fixed in both surfaces and are not roles:
- `DSColor.primaryFill` / `primaryText` for the one filled button.
- `DSColor.destructive`.
- `DSColor.onAccentFill` for ink on a section-coloured fill.
- `PanelMetrics.accent` (cyan) for active tools.
- `SpaceTint` for section colours. Read it from the model and never hard-code it.

### Spacing: `DSSpace`

`xxs 2 · xs 4 · s 6 · m 8 · l 10 · xl 12 · xxl 16 · section 24`

Rows and stacks use `s`/`m`/`xl`. Panel insets are `xxl`. Gaps between
blocks are `section`.

### Radius: `DSRadius` (always `DSShape.squircle(r)`, always `.continuous`)

`checkbox 3 · keycap 6 · chip 7 · control 10 · menuRow 11 · row 14 · bar 16 · menu 20 · block 24 · card 32`

- **Shape rule:** a button with words is a rounded rectangle, radius
  `DSRadius.button` 10 (8 on xs/sm), as reui's shadcn button. Pills and tabs
  are capsules (`DSShape.action`). Anything that *holds* content is a
  squircle.
- Checkboxes, swatches and toggles are selection controls, so they stay
  squircles.
- Corners nest concentrically: inner radius = outer radius − inset.

### Size: `DSSize`

| What | Size |
|---|---|
| Controls (pills) | `control 28` |
| Icon buttons | `iconSmall 28` · `icon 34` · `iconLarge 38` (dock glass) |
| Checkboxes | `box 18` · `stepBox 14` · `miniBox 10` |
| Hairline | `hairline 1` |

### Control sizes: `DSControlSize`

One scale for every control with a fixed height, after reui's shadcn sizes.
Pick by where the control sits, never by height:

| Size | Height | Radius | Label | Use for |
|---|---|---|---|---|
| `.xs` | 24 | 8 | 12 medium | inside a card or a row, beside content (Join, the ↵ key, the mic) |
| `.sm` | 28 | 8 | 12.8 medium | bars and tab rows (space pills), compact forms |
| `.md` | 32 | 10 | 14 medium | the default: standalone actions |
| `.lg` | 36 | 10 | 14 medium | a form's main action |
| `.xl` | 40 | 12 | 15 medium | a hero action on an empty page |

Sized: `PrimaryActionButton` / `DSButtonStyle` (icon-only `square: true`
too, glyph at `size.iconSize`), `SpacePill`. Single-size, like reui's:
inputs (`dsFieldWell`), `Keycap`, `KeyBadge`, `DSCheckbox`.

### Type: `DSType` (SF only, roles not sizes)

| Role | Spec | Where |
|---|---|---|
| `editorTitle` | 24 bold | open note title |
| `pageTitle` | 18 medium | a page's header bar |
| `cardTitle` | 15 medium | meeting card |
| `rowTitle(surface)` | 14 medium / 15 | to-do and note rows |
| `step` | 13.5 | checklist steps, note previews |
| `body` | 13 | running text |
| `label` | 13 semibold | pills, tabs |
| `menu` | 13.5 | menu rows |
| `meta` / `quiet` | 12.5 / 12.5 semibold | meta lines / "Completed · 2" |
| `button` / `buttonSM` / `buttonXS` | 14 / 12.8 / 12 medium | buttons with words, by size |
| `caption` / `tooltip` | 11 / 11 medium | small print / tooltips |
| `micro` / `sectionCaps` | 10 / 10 medium | counts / UPPERCASE labels |

`DSFont` and the `DSDock` fonts are older aliases that point at `DSType`. New
code uses `DSType`.

### Motion: `Motion` and `DSTransition` (Notch/NotchAnimation.swift)

Always use `Motion.*`, never `NotchAnimation.*` outside `Notch/`, and never an
inline `.spring(...)` / `.easeOut(...)`. `Motion` already falls back to a
short fade under Reduce Motion.

| Token | Use for |
|---|---|
| `Motion.press` | a control answering a press |
| `Motion.hoverFade` | hover highlight |
| `Motion.hintFade` | hints, tooltips, badges |
| `Motion.appear` | a small thing appearing or changing state in place (a fade) |
| `Motion.tint` | a colour changing |
| `Motion.swap` | one thing becoming another in place |
| `Motion.menu` | a menu or popover opening |
| `Motion.complete` | ticking a to-do |
| `Motion.contentHug` | panel height, row insert/remove: the hero spring |

Transitions are `DSTransition.fade`, `.rise()`, `.pop()`, `.sectionSwap` and
`.spaceSwap(reduceMotion:)`. The notch opening uses `.notchEntry(index:)`
(staggered).

Rules:
- **No animation on keyboard paths** (selection moving under ↑/↓, focus).
- **Tab and mode switches crossfade**, never slide.
- Bounce stays at 0.2 or below.
- Colour changes use a curve, physical movement uses a spring.
- Panel height, row insert/remove and the Completed section all move on
  `contentHug`, so container and content move together.

## 4. Components: what to reach for

| You need… | Use | File |
|---|---|---|
| A button with words (Join, Save, Snooze) | `PrimaryActionButton(title:shortcutHint:variant:size:fillsWidth:action:)`, modelled on reui.io's shadcn button. Variants `.primary` (ONE per view), `.secondary`, `.outline`, `.ghost`, `.destructive`. Sizes: the `DSControlSize` scale (`.xs` 24 → `.xl` 40). Colours: `DSButtonColor`. For a custom label, `.buttonStyle(DSButtonStyle(...))`; `square: true` for an icon-only button in the same family (the ↵ key, the mic). | DSButtons.swift |
| An icon button | `Button { } label: { OttoIcon(...) }.buttonStyle(DSIconButtonStyle(variant:shape:size:isActive:))` (see the variants below) | DSButtons.swift |
| The container dock's 38-pt glass circle | `DockRoundButton` | Todos/Dock/DockBar.swift |
| A press scale on a standalone control | `.buttonStyle(DSPressStyle())`. Menu rows never scale. | DSButtons.swift |
| An icon | `OttoIcon("sf.name", pointSize:)` (Lucide). `DockIcon` only for its own glyph enum. Never `Image(systemName:)`. | OttoIcon.swift |
| A shortcut ON a control | `Keycap(text:tone:size:)`, filled | DesignComponents.swift |
| A shortcut hint beside words | `KeyBadge(text:style:)`, outlined: `.row` or `.hint` | DesignComponents.swift |
| A tooltip | `.ottoTooltip("Label", shortcut: "⌘K")` | PanelTooltip.swift |
| A checkbox | `DSCheckbox(size: .row/.step/.archive, isChecked:, tint:)`. `dashed: true` for an empty slot. | DSCheckbox.swift |
| A list row's hover/focus/opened slab | `.dsRowBackground(hover:focused:expanded:)` | Surface.swift |
| A space tab | `SpacePill(title:fill:isActive:count:size:)`, `.sm` in the tab row | DesignComponents.swift |
| A heading for a group | `DSSectionLabel(text:style: .caps / .quiet)` | DesignComponents.swift |
| A text field | `.dsFieldWell()` plus your own padding | DesignComponents.swift |
| A menu | rows of `DSMenuRow(...)` in a `VStack`, `.padding(OttoMenuStyle.padding)`, `.ottoMenuSurface()`, placed with `.menuAnchor` / `.anchoredMenu` | DSMenu.swift |
| A drag drop marker | `DropIndicator(axis: .horizontal / .vertical)` | DesignComponents.swift |
| An empty list | `EmptyListView(...)` | Todos/EmptyListView.swift |
| An inline link/date/@/code chip | `DSEntityChip` colours via `EntityTitleView` | DesignComponents.swift |
| A page header one level in | `ContextBar(parentTitle:title:onBack:)` | Todos/SpaceChrome.swift |
| A meeting | `PanelMeetingCard` (standalone card) or `MeetingCard` (inside the Today list) | Notch/FloatingPanelsView.swift, Calendar/UpNextSection.swift |
| A surface | panels: `.liquidGlass(in:)`. Over the notch: `.notchGlass(in:)`. Floating chrome: `.floatingGlass(in:)` | LiquidGlass.swift |

`DSIconButtonStyle` variants:
- `.filled`: the gear and export (34, circle, hairline).
- `.quiet` + `.squircle`: Back, Sweep.
- `.quiet` + `isActive`: format tools.

### Anatomy

- **Row:** `[DSCheckbox 18] ⟷ 12–13 ⟷ [title DSType.rowTitle] … [trailing hints in a fixed-width gutter]`.
  - Min height 37 (panels) / 38 (container).
  - `.dsRowBackground` is the full-width slab. Hover must never resize the row.
  - ⏎ edits, Space completes, ⌘⏎ is shown as a `KeyBadge` on focus.
- **Space (panels):**
  - Header: `CaptureHeader` / `ContextBar`, 60 pt, hairline under it.
  - Then the list, which hugs its content.
  - Then the footer: `SpacePill` row + gear, floating over `ProgressiveBlur`.
- **Space (container):**
  - The first row is the input.
  - Then the list.
  - Then the dock bar: dots, round buttons.
- **Menu:**
  - Surface radius 20, padding 10, rows radius 11.
  - Highlight = keyboard selection.
  - ↑/↓ move, ⏎ performs, Esc closes.
  - The current item shows a check or medium weight, never a fill.
- **Empty state:** the Otto peek logo, title, subtitle. It is never silent:
  say "No more meetings today" rather than drawing nothing.

## 5. Do / Don't

| Don't | Do |
|---|---|
| `.font(.system(size: 13, weight: .semibold))` | `.font(DSType.label)` |
| `Color.white.opacity(0.55)`, `Color(hex:)` in a view | `palette.textSecondary`, or a new role/token |
| `RoundedRectangle(cornerRadius: 12)` | `DSShape.squircle(DSRadius.control)` |
| `.padding(.horizontal, 11)` | `.padding(.horizontal, DSSpace.xl)` |
| `withAnimation(.spring(response: 0.3, dampingFraction: 0.8))` | `withAnimation(Motion.swap)` |
| `if usesDock { DSDock.text } else { DSColor.textPrimary }` | `palette.textPrimary` |
| a private `struct MyKeycap` / `MyCheckbox` / `MyMenuRow` | the shared component, with a parameter added if truly needed |
| `.help("…")` | `.ottoTooltip("…", shortcut:)` (`.help` opens behind the notch) |
| `Image(systemName:)` | `OttoIcon(...)` |
| SwiftUI `Menu` | an Otto menu (`DSMenuRow` + `.ottoMenuSurface()`) |

If you truly need a literal (an optical nudge, a value fixed by a spec), add
`// ds-allow: <why>` on that line. The lint accepts it, and reviewers read
the reason.

## 6. Adding a new component

Only when nothing in §4 fits, even with a parameter. Then, in the same change:

1. Put it in `Otto/DesignSystem/`, built only from tokens and palette roles.
2. Make it work on BOTH surfaces through the environment, never through
   layout flags.
3. Give it its keyboard path, and its shortcut through `.ottoTooltip`.
4. Add it to `DSGallery.swift` and to the table in §4 of this file.
5. Delete any copy it replaces.

## 7. Known divergences (left on purpose)

- `MeetingCard` (in-list) and `PanelMeetingCard` (standalone) are two
  components for two contexts. They are not copies.
- The Notes composer wells change depth with state. They keep their own
  fills instead of using `dsFieldWell`.
- `SaveButton` and `DockReturnKey`: the white "Save ↵" key, a spec'd
  one-off.
- `AvatarMenuRowView` (gear menu): it uses `DSMenuRow`'s metrics but adds a
  sparkline and per-key caps.
- The dock furniture (`DockBar`, `DockSpaceMenu`, `DockNewSpaceCard`) uses
  `DSDock` directly. It exists only on the container.
