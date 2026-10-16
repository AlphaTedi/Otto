import SwiftUI

// MARK: - DockPanelView — the notch container, B3 dock edition
//
//   ┌──────────── fixed 560 ────────────┐
//   │  (50 pt notch zone, pure black)   │
//   │  [⬚] Add to Work…            (↵) │  ← the first row, pinned
//   │  [ ] …                            │
//   │  [ ] …                            │  ← the list, scrolling
//   │  ░░░░░ 40 pt fade to black ░░░░░  │
//   │ (📝)(📅)   ( ● ● [● Work 5] + )   (⚙) │
//   └───────────────────────────────────┘
//
// Drawn by TodoTabView in place of its furniture when the experiment is on;
// everything the panel does — the key router, the deselect catcher, the menus
// — still lives there and still applies.

struct DockPanelView: View {
    @ObservedObject private var store = TodoStore.shared
    @ObservedObject private var notes = NotesStore.shared
    @ObservedObject private var controller = NotchController.shared

    /// The content frame starts `notch + 4` from the top of the silhouette
    /// (NotchShapeView); the rest of the 50 pt notch zone is left black here.
    private var notchZoneGap: CGFloat {
        max(0, NotchContainerMetrics.notchZone - controller.notchSize.height - 4)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: notchZoneGap)

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
                    // Notes draws its own first row ("New note…") inside the
                    // stream, where its composer and keys already live.
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if store.showsSpaceBar {
                DockBottomBar()
                    .padding(.horizontal, NotchContainerMetrics.sideInset - 16)
                    .notchEntry(index: 1)
                    .transition(.opacity)
            }
        }
        // 18 from the silhouette's foot; the content frame already ends 4
        // above it.
        .padding(.bottom, NotchContainerMetrics.bottomInset - 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(NotchAnimation.hintFade, value: store.showsSpaceBar)
    }
}
