import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Shared plumbing for the to-do panel: layout preference keys, the panel
// chrome model, swap transitions, caret placement and the internal drag
// payload. Used by TodoTabView, the tab row, the list and its rows.

/// One parent row stays useful while closed without letting a long checklist
/// take over the whole section. Shared with DebugDriver so the runtime check
/// exercises the exact disclosure rule the view uses.
enum ChecklistDisclosure {
    static let collapsedLimit = 2

    static func visibleCount(total: Int, expanded: Bool) -> Int {
        expanded ? total : min(total, collapsedLimit)
    }

    static func hiddenCount(total: Int, expanded: Bool) -> Int {
        max(0, total - visibleCount(total: total, expanded: expanded))
    }
}

// MARK: - Height measurement

struct TodoContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// How far the capped to-do region has scrolled, in points from the top.
struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct FootBlurVisibleKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// Depth shared by the native Tahoe edge bar and the pre-Tahoe fallback.
/// Keeping one value makes the transition meet the section row at the same
/// point on every supported macOS release.
/// How far the blur reaches up over the list, above the pills.
///
/// 96 covered too much of the list and read as a haze over the to-dos rather
/// than as the bar's own edge (Marcello, 2026-09-20). Localised to just above
/// the pills: enough for the ramp to be gradual, not enough to be a mood.
let sectionBarFrostDepth: CGFloat = 52

/// Softens both edges of the scrolling region, where content passes under
/// the draft row and into the frosted section bar.
///
/// A capped ScrollView crops on a hard line, which reads as "the list ends
/// here". A fade says "this continues" without adding a control or a label
/// to read, and it disappears at the end so a fully-scrolled list still
/// terminates cleanly.
///
struct ScrollEdgeFade: ViewModifier {
    let scrollOffset: CGFloat
    let hasBelow: Bool

    private let topFade: CGFloat = 22
    /// Long enough to dissolve a complete row before the viewport clips it.
    /// The section-bar material extends across this same area, so the result
    /// is a frosted continuation rather than a row cut on a straight line.
    private let bottomFade: CGFloat = sectionBarFrostDepth
    /// 2pt of slack: sub-pixel offsets must not leave a permanent haze on a
    /// list that is actually at its end.
    private var hasAbove: Bool { scrollOffset > 2 }

    func body(content: Content) -> some View {
        content.mask(
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(hasAbove ? 0 : 1), .black],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: topFade)
                Color.black
                LinearGradient(colors: [.black, .black.opacity(hasBelow ? 0 : 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: bottomFade)
            }
            .animation(NotchAnimation.hintFade, value: hasAbove)
            .animation(NotchAnimation.hintFade, value: hasBelow)
        )
    }
}

/// The floating to-do list keeps its scroll content visible at the foot so
/// the material overlay can sample it. Other scroll regions retain the fade.
struct TodoScrollEdgeEffect: ViewModifier {
    let isScrollable: Bool
    let scrollOffset: CGFloat
    let hasBelow: Bool
    let isContainer: Bool
    var showsFootBlur = false

    func body(content: Content) -> some View {
        content.modifier(ScrollEdgeFade(scrollOffset: scrollOffset,
                                        hasBelow: !showsFootBlur && hasBelow))
    }
}

/// Width of the tab row's content, and of the window it sits in. The two
/// together answer the only question the scroller has: does it need to scroll
/// at all?
struct TabsContentWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct TabsViewportWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct SectionHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The panel's chrome, MEASURED.
///
/// The scroll region's ceiling is what is left of the block after everything
/// that is not the list has taken its share, so the budget has to know how
/// tall those things actually are. It used to know by arithmetic on
/// constants — and the constants drifted every time one of the pieces was
/// restyled, each time by an amount nobody noticed until the section pills
/// were hanging out of the bottom of the panel: the creation bar grew 10pt
/// when it became a recessed well, the Completed header arrived carrying 24pt
/// of padding the number for it did not include. Three overflows, one cause.
///
/// Measured, the budget cannot drift. The pieces report what they drew and
/// the list gets the remainder.
///
/// No feedback loop: none of these heights is a function of the viewport they
/// are shrinking, so a change settles in one pass.
@MainActor final class PanelChrome: ObservableObject {
    static let shared = PanelChrome()
    /// Creation bar plus the gap under it. Seeded at the old constant so the
    /// first frame is plausible before anything has been measured.
    @Published var draftBlock: CGFloat = PanelMetrics.barHeight + PanelMetrics.sectionGap
    /// The section row with both its rules and paddings.
    @Published var tabRow: CGFloat = PanelMetrics.tabsDividerPaddingV
        + PanelMetrics.tabsTopPadding + 31 + PanelMetrics.tabsBottomPadding
}

/// The draft field's real width, so its height is measured against the box it
/// is actually wrapping in.
struct DraftFieldWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct DraftBlockKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct TabRowHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The drawn height of the pinned Completed section, measured rather than
/// assumed.
///
/// It was a constant (`completedHeaderHeight`, 24), and the constant was
/// wrong twice over: the header carries 24pt of its own top padding on top of
/// its 24pt of content, and when the section is OPEN it grows to 160. A
/// budget that subtracts a guess is a budget that overflows by the size of the
/// guess — which is exactly what pushed the section pills through the bottom
/// edge of the panel (Marcello, 2026-09-06). Measured, it is right in every
/// state including the ones nobody enumerated.
struct CompletedInsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// A transparent layer that means "you clicked nothing" — it ends whatever
/// edit or selection is live.
///
/// Always used as a `.background`, deliberately: a background only receives a
/// click where nothing in front of it handled one, so rows, checkboxes,
/// buttons, the tab strip and drag-to-reorder all still get theirs first. It
/// is a fallback, never an interceptor.
struct DeselectCatcher: View {
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { TodoStore.shared.endEditing() }
    }
}

/// Opacity plus a few points of blur, in and out. SwiftUI ships no blur
/// transition, so it is a modifier pair; the radius is small enough that
/// nothing reads as an effect — the content just softens on its way out.
struct BlurModifier: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

/// Zero LAYOUT height, full drawing. The content overflows its frame (SwiftUI
/// does not clip by default), so it is still painted while it fades — it just
/// no longer has a say in how tall its parent is.
struct ZeroLayoutHeight: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content.frame(height: active ? 0 : nil, alignment: .top)
    }
}

extension AnyTransition {
    // Computed, not stored: AnyTransition isn't Sendable, so a static let
    // fails Swift 6's isolation check.
    static var crossfadeBlur: AnyTransition {
        .opacity.combined(
            with: .modifier(active: BlurModifier(radius: 4), identity: BlurModifier(radius: 0))
        )
    }

    /// The section / mode swap: crossfade in, crossfade out — and the
    /// outgoing view drops out of LAYOUT the moment it starts leaving.
    ///
    /// Both views overlap in a ZStack during the crossfade, and a ZStack is
    /// as tall as its tallest child. So Work (12 rows) → Personal (2 rows)
    /// kept the panel at twelve rows' height until the old list had fully
    /// faded, then snapped to two — outside any animation, because a
    /// transition's removal is discrete — and the tab row snapped with it
    /// (Thomas, 2026-09-01). With the outgoing view at zero layout height
    /// the ZStack is the incoming list's height from the first frame, the
    /// change happens inside the withAnimation that switched sections, and
    /// the panel, the scroll region and the tabs all ride one spring.
    /// U5 §6.2, floating panels: the list swaps with a 6-pt rise and a fade
    /// over 200 ms, and never waits for the glow. Reduce Motion drops the
    /// rise. Leaving still takes no layout height, for the reason above.
    static func spaceSwap(reduceMotion: Bool) -> AnyTransition {
        .asymmetric(
            insertion: (reduceMotion ? AnyTransition.opacity
                                     : AnyTransition.opacity.combined(with: .offset(y: 6)))
                .animation(.easeOut(duration: 0.2)),
            removal: AnyTransition.opacity.combined(with: .modifier(
                active: ZeroLayoutHeight(active: true),
                identity: ZeroLayoutHeight(active: false)))
                .animation(.easeOut(duration: 0.2))
        )
    }

    static var sectionSwap: AnyTransition {
        .asymmetric(
            insertion: crossfadeBlur,
            removal: crossfadeBlur.combined(with: .modifier(
                active: ZeroLayoutHeight(active: true),
                identity: ZeroLayoutHeight(active: false)))
        )
    }
}

/// Put the caret at the end of whatever field just took focus, instead of
/// leaving the whole contents selected.
///
/// A macOS text field selects everything when it becomes first responder.
/// That is right for ⇥ through a form — you are replacing the value — and
/// wrong for ↑/↓ walking a to-do, where the user is moving PAST fields on the
/// way to one of them. Selected, the next character typed silently wipes a
/// title or a note the user only meant to step over (Marcello, 2026-09-06).
///
/// Only the arrow-driven path calls this. A click already places the caret
/// where the user aimed, and collapsing it to the end would move it away from
/// the letter they clicked between.
enum FieldCaret {
    static func collapseToEnd(attempts: Int = 3) {
        // One hop after the focus assignment, which is itself dispatched: the
        // field editor does not exist until AppKit has made the field first
        // responder, so there is nothing to place a caret in before then.
        DispatchQueue.main.async {
            // Key window first, then any window holding a field editor. The
            // notch panel is not always key — it is a floating NSPanel and the
            // app is an accessory — so keying off `NSApp.keyWindow` alone
            // would have made this work in some situations and not others.
            let editors = NSApp.windows.compactMap { $0.firstResponder as? NSTextView }
            let editor = editors.first { $0.window?.isKeyWindow == true } ?? editors.first
            if let editor {
                let end = (editor.string as NSString).length
                editor.setSelectedRange(NSRange(location: end, length: 0))
            } else if attempts > 1 {
                collapseToEnd(attempts: attempts - 1)
            }
        }
    }
}

extension View {
    func measureHeight<K: PreferenceKey>(_ key: K.Type) -> some View where K.Value == CGFloat {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: key, value: proxy.size.height)
            }
        )
    }
}

// MARK: - Internal drag payload

extension NSItemProvider {
    /// A reorder drag that never leaves the process, carrying a type nothing
    /// else in the app (or the system) accepts — see UTType.ottoInternalItem.
    static func ottoInternal(_ id: UUID) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.ottoInternalItem.identifier,
            visibility: .ownProcess
        ) { completion in
            completion(Data(id.uuidString.utf8), nil)
            return nil
        }
        return provider
    }
}
