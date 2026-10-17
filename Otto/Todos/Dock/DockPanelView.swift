import SwiftUI

// MARK: - DockPanelView — the notch container, B3 dock edition (final flow)
//
//   ┌──────────── fixed 470 ────────────┐
//   │  (44 pt notch zone, pure black)   │
//   │  [⬚] Add to Grocery…              │  ← the first row, pinned
//   │  [ ] …                            │
//   │  [ ] …                            │  ← the list, scrolling UNDER the bar
//   │  ░░ progressive blur + to black ░░ │
//   │ (📝)     ( ● [● Grocery] ● + )  (⚙) │  ← glass, floating
//   └───────────────────────────────────┘
//
// Drawn by TodoTabView in place of its furniture when the experiment is on;
// everything the panel does — the key router, the deselect catcher, the menus
// — still lives there and still applies. Inside NotchShapeView's content
// frame, which starts 16 in from each side of the silhouette and ends 4 above
// its foot (NotchContainerMetrics.frameInset / frameFootGap).

struct DockPanelView: View {
    @ObservedObject private var store = TodoStore.shared
    @ObservedObject private var notes = NotesStore.shared
    @ObservedObject private var dock = DockState.shared
    @ObservedObject private var controller = NotchController.shared

    /// The content frame starts `notch + 4` from the top of the silhouette
    /// (NotchShapeView); the rest of the 44 pt notch zone is left black here.
    private var notchZoneGap: CGFloat {
        max(0, NotchContainerMetrics.notchZone - controller.notchSize.height - 4)
    }

    /// A note is open: the editor brings its own bar (back · tools · export).
    private var editingNote: Bool {
        (store.panelMode == .notes || store.panelMode == .calendar) && notes.openNoteID != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: notchZoneGap)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // Nothing underneath answers while the new-space card is up.
                .allowsHitTesting(!dock.isCreatingSpace)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // OVERLAYS, not ZStack siblings. Both reach past the content frame to
        // the silhouette's edges with negative padding; as siblings they made
        // the stack itself larger, and when the veil came in the whole list
        // was re-centred and slid across — the jump behind the new-space
        // card (Marcello, 2026-10-17). An overlay never sizes its host.
        //
        // Rows dissolve into the bar instead of being cut (final flow 4.4):
        // a progressive blur, then a gradient to black over it.
        .overlay(alignment: .bottom) { footZone }
        // The new-space card is a modal: a veil over the whole silhouette
        // sets it apart from the list, and a click on it closes the card, as
        // Esc does. The card itself lives in DockBarLayer, above this.
        .overlay {
            if dock.isCreatingSpace {
                Color.black.opacity(0.45)
                    .overlay(MenuDismissCatcher { dock.cancelNewSpace() })
                    .padding(.top, -(controller.notchSize.height + 4))
                    .padding(.horizontal, -NotchContainerMetrics.frameInset)
                    .padding(.bottom, -NotchContainerMetrics.frameFootGap)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
        // The bar itself is drawn at the notch's root (DockBarLayer):
        // inside this masked content its glass could not see through.
        .animation(NotchAnimation.hintFade, value: store.showsSpaceBar)
        .animation(NotchAnimation.hintFade, value: editingNote)
        .animation(.easeOut(duration: 0.2), value: dock.isCreatingSpace)
    }

    @ViewBuilder
    private var content: some View {
        ZStack(alignment: .topLeading) {
            switch store.panelMode {
            case .browsing:
                VStack(alignment: .leading, spacing: 0) {
                    DockTodoFirstRow()
                        .notchEntry(index: 0)
                    TodoBrowsingView()
                }
                .transition(.sectionSwap)
            case .notes, .calendar:
                // Notes draws its own first row ("Title of a new note…")
                // inside the stream, where its composer and keys already live.
                NotesSpaceView()
                    .transition(.sectionSwap)
            case .insights:
                InsightsView()
                    .transition(.sectionSwap)
            case .newCategory:
                CategoryFormView()
                    .transition(.sectionSwap)
            case .find:
                QuickFindView()
                    .transition(.sectionSwap)
            }
        }
    }

    private var footZone: some View {
        return ZStack {
            ProgressiveBlur(cornerRadius: 0, maxRadius: 12)
            // Clear for the 40 pt above the bar, then deepening behind it.
            LinearGradient(stops: [
                .init(color: .black.opacity(0), location: 0),
                .init(color: .black.opacity(0.6), location: 0.45),
                .init(color: .black.opacity(0.92), location: 0.8),
                .init(color: .black, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        .frame(height: NotchContainerMetrics.footZone)
        // The silhouette's full width and down to its foot, not just the
        // content frame (16 in at the sides, 4 short of the bottom).
        .padding(.horizontal, -NotchContainerMetrics.frameInset)
        .offset(y: NotchContainerMetrics.frameFootGap)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
