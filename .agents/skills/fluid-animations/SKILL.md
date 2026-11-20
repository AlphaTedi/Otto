---
name: fluid-animations
description: Guidance for building genuinely fluid, physics-based SwiftUI/macOS animations — the Dynamic Island / Siri-blob quality of motion, not default SwiftUI easing. Use this whenever the user asks to add, improve, or review any animation, transition, gesture-driven motion, morphing shape, spring, or micro-interaction in this app (panel open/close, hover states, drag interactions, badge/state-change effects, blob or shape morphing). Also trigger if the user says something feels "janky," "stiff," "not smooth enough," or asks how to make motion feel more "native," "premium," or "alive" — these are symptoms this skill addresses even without the word "animation."
---

# Fluid Animations (Dynamic Island / Siri-grade motion)

## Why default SwiftUI animations don't feel like Apple's system UI

`.easeInOut`, `.linear`, and even bare `.animation(.default)` all animate toward a
fixed endpoint on a fixed timeline. Apple's system motion (Dynamic Island,
Siri's blob, notch morphing) never does that — it's:

1. **Real spring physics**, not eased curves — motion has mass, stiffness, and
   damping, so it decelerates naturally instead of hitting an invisible wall.
2. **Interruptible with velocity preservation** — if a spring animation is
   still running and gets re-targeted (user taps again mid-animation, drags
   away from a rest state), the new animation inherits the *current velocity*
   instead of snapping to zero and restarting. This is the single biggest
   reason system animations feel "alive."
3. **Phase-based, not one-shot** — a Siri blob morph or Dynamic Island
   expansion is a chain of overlapping stages (anticipation → main motion →
   settle), not one animation curve from A to B.
4. **Geometry-interpolated shape morphing** — the blob/pill shape changes by
   interpolating the actual path geometry frame-by-frame, never a crossfade
   between two static shapes.

Treat any animation task as "which of these four am I missing?" rather than
"which curve should I pick."

## Tool selection

Prefer native SwiftUI first — it covers most of this today. Reach for a
library only when native tools genuinely fall short of what's needed.

| Need | Use |
|---|---|
| Button/badge/state-change micro-interaction (bounce, shake, jiggle) | **[Pow](https://github.com/EmergeTools/Pow)** — `.changeEffect()`, `.conditionEffect()`. SwiftUI-native modifiers, physics-correct out of the box, least code for the most common case. |
| Custom continuous motion driven by a live gesture (drag-to-dismiss, rubber-banding, decay after release) | **[Wave](https://github.com/jtrivedi/Wave)** — lower-level interruptible/velocity-preserving spring engine, built by a former Apple engineer for exactly this. Use only when Pow's canned effects don't cover a custom drag/decay curve. |
| A designer needs to author complex blob/morph motion visually and hand off a reusable interactive asset | **[Rive](https://rive.app)** — real-time vector animation with state machines. Only worth the integration cost if visual (non-code) iteration is actually needed; otherwise it's overhead. |
| Everything else: panel transitions, expand/collapse, shared-element morphs, multi-stage sequences | **Native SwiftUI**, see below — usually sufficient and keeps the dependency graph small. |

### Native SwiftUI toolkit (macOS 14+/Sonoma+, which this project targets)

- `.spring(response:dampingFraction:)` or the semantic presets `.smooth`,
  `.snappy`, `.bouncy` — these ARE proper spring physics, not eased curves.
  Default to these over `.easeInOut` for anything meant to feel physical.
- `PhaseAnimator` — for multi-stage sequences (the "Siri blob has 3 phases"
  case). Define an enum of phases and let SwiftUI drive the transitions;
  don't hand-roll `DispatchQueue.asyncAfter` chains.
- `KeyframeAnimator` — when different properties need independent timing
  within one animation (e.g., scale peaks before opacity settles).
- `matchedGeometryEffect` / `matchedTransitionSource` — for shared-element
  morphs between two views (expanding a control into a panel, etc.).
- `Canvas` + `TimelineView` — when you need true per-frame custom geometry
  (blob/metaball math), because standard `Shape` interpolation can't express
  it.

## Shape morphing (Dynamic-Island / blob-style effects)

If the task involves a shape that changes form (not just size/position):

- Model the shape as a **superellipse/squircle** (or metaball function for
  organic blobs), not a fixed-corner rectangle or circle — Apple's pill/island
  shapes are continuous superellipses, which is why the corners look "soft"
  rather than mechanically rounded.
- Interpolate the **path's control points/parameters** frame-by-frame (via
  `Canvas`/`TimelineView` or a custom `Shape` with an animatable data pack),
  not two static shapes crossfaded with opacity. A crossfade reads as a fade,
  not a morph — this is usually the tell that gives away a "fake" version of
  this effect.

## Concrete spring parameters

Use these as starting points, not gospel — tune by feel, but they're the
right neighborhood:

- **UI chrome (panels, cards, control expansion):** `dampingFraction` 0.7–0.85,
  `response` 0.3–0.5s. High enough damping that it settles cleanly without
  overshoot reading as "bouncy" when the context is a serious/utilitarian UI.
- **Playful/expressive (badges, reactions, delightful moments):**
  `dampingFraction` 0.5–0.6. Lower damping = visible overshoot/bounce, which
  reads as fun rather than sloppy *only* when the content is a fun accent, not
  primary navigation.
- **Never use `.linear` or `.easeInOut` for anything meant to feel physical**
  (a card that expands, a panel that slides) — reserve eased curves for pure
  opacity/color fades where there's no implied physical object.
- **On gesture release, seed the spring's initial velocity from the drag's
  actual velocity** (`DragGesture`'s `.predictedEndLocation` / velocity, or
  track delta over time yourself). A spring that starts at zero velocity after
  a fast drag is the most common way a "physics" animation still feels fake.
- **Overlap phases slightly rather than chaining them sequentially** — start
  phase 2 slightly before phase 1 fully completes (e.g., a small percentage
  overlap window). Fully sequential phases read as a slideshow of animations;
  overlapping them is what makes multi-stage motion read as one continuous
  gesture.

## Pre-ship checklist

Before calling an animation "done," check:

- [ ] **Interruption**: if I trigger the animation again (or the underlying
      state changes) while it's mid-flight, does it retarget smoothly from
      current position/velocity, or does it snap/restart?
- [ ] **Gesture handoff**: if this is gesture-driven, does releasing the drag
      carry the gesture's velocity into the settling animation, rather than
      starting the spring from rest?
- [ ] **Phasing**: if this is a multi-step effect, is it modeled as explicit
      phases (`PhaseAnimator`/`KeyframeAnimator`) with slight overlap, rather
      than one flat animation or a manual `asyncAfter` chain?
- [ ] **Curve type**: is the timing curve a spring (or semantic
      `.smooth`/`.snappy`/`.bouncy`), not `.linear`/`.easeInOut`, for anything
      representing a physical object moving?
- [ ] **Shape morphing**: if a shape changes form, is it interpolating actual
      path geometry (superellipse/metaball parameters), not crossfading
      between two static shapes?

If any box is unchecked, that's specifically the gap between "looks like a
SwiftUI animation" and "looks like a system animation."
