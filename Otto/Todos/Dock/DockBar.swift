import SwiftUI

// MARK: - The B3 dock's bottom bar (final flow §4.5)
//
//   (Notes)            ( ● [● Grocery] ● ● + )            (⚙)
//
// A three-column grid: Notes left, the dock centred, Settings right — all
// glass (`notchGlass`), floating over the list, which scrolls underneath.
// Meetings is gone from the notch container (final flow §2.2).
//
// The dock has ONE highlight that slides between spaces — the thing that
// makes a switch read as one motion — and the active space opens its name
// (no count anywhere, decision 2) while the one before closes on the same
// curve, so the dock's width barely moves. Its "+" grows the dock itself into
// the new-space card ("Morph", §4.7); a right-click on a dot opens the space
// menu (§4.6).

struct DockBottomBar: View {
    @ObservedObject private var store = TodoStore.shared
    @ObservedObject private var dock = DockState.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var morph

    private var inNotes: Bool { store.panelMode == .notes || store.panelMode == .calendar }
    private var creating: Bool { dock.isCreatingSpace }
    /// Insights is a page, not a space: Back where Notes was, no dock.
    private var inInsights: Bool { store.panelMode == .insights }

    var body: some View {
        if inInsights { insightsBar } else { mainBar }
    }

    private var insightsBar: some View {
        HStack(alignment: .bottom, spacing: NotchContainerMetrics.barGap) {
            DockRoundButton(label: L10n.t("dock.back"), iconColor: DSDock.settingsIcon) {
                DockIcon(.back, size: NotchContainerMetrics.roundIcon + 2)
            } action: {
                store.goBack()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DockGearButton()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .transition(.opacity)
    }

    private var mainBar: some View {
        // `1fr auto 1fr`: equal flexible sides, so the dock sits at the true
        // centre whatever the two sides hold. Bottom-aligned: the card grows
        // UP out of the dock.
        HStack(alignment: .bottom, spacing: NotchContainerMetrics.barGap) {
            DockRoundButton(label: L10n.t("filter.notes"), isOn: inNotes, onTint: DSDock.notes,
                            onIcon: DSDock.notesLight, iconColor: DSDock.notes) {
                DockIcon(.notes, size: NotchContainerMetrics.roundIcon + 2)
            } action: {
                if inNotes { NotesStore.shared.leaveSpace() } else { NotesStore.shared.chooseKind(meetings: false) }
            }
            .modifier(SideSlide(away: creating, edge: -1))
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack(alignment: .bottom) {
                if creating {
                    DockNewSpaceCard()
                        .matchedGeometryEffect(id: "dockMorph", in: morph)
                        .transition(.opacity.animation(.easeOut(duration: 0.12)))
                } else {
                    SpaceDock()
                        .matchedGeometryEffect(id: "dockMorph", in: morph)
                        .transition(.opacity.animation(.easeIn(duration: 0.18).delay(creating ? 0 : 0.12)))
                }
            }

            DockGearButton()
                .modifier(SideSlide(away: creating, edge: 1))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

/// Notes and Settings step aside (±12 pt, fading) while the card is open.
private struct SideSlide: ViewModifier {
    let away: Bool
    let edge: CGFloat
    func body(content: Content) -> some View {
        content
            .opacity(away ? 0 : 1)
            .offset(x: away ? edge * 12 : 0)
            .allowsHitTesting(!away)
            // The same smooth curve out and back: the overshoot on the way
            // back carried the buttons past their place and back, which read
            // as the whole bar jumping (Marcello, 2026-10-17).
            .animation(DockMorph.side, value: away)
    }
}

// MARK: Round buttons

/// 38-pt glass circles, the same material as the dock (final flow §4.5).
struct DockRoundButton<Icon: View>: View {
    let label: String
    var shortcut: String? = nil
    var isOn = false
    var onTint: Color = DSDock.notes
    var onIcon: Color = DSDock.notesLight
    var iconColor: Color = DSDock.settingsIcon
    @ViewBuilder let icon: Icon
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button {
            BarTipState.shared.clicked(label)
            action()
        } label: {
            icon
                .foregroundStyle(isOn ? onIcon : (hover && iconColor == DSDock.settingsIcon ? DSDock.iconHover : iconColor))
                .frame(width: NotchContainerMetrics.roundButton, height: NotchContainerMetrics.roundButton)
                .background(Circle().fill(Color.white.opacity(hover ? 0.06 : 0)))
                .notchGlass(in: Circle(), tint: isOn ? onTint : nil)
                .contentShape(Circle())
        }
        .buttonStyle(DockPressStyle())
        .onHover { hover = $0 }
        .barTip(label, label: label, shortcut: shortcut)
        .animation(.easeInOut(duration: 0.3), value: isOn)
        .animation(.easeOut(duration: 0.15), value: hover)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Pressing scales a round button to 0.93 over 150 ms.
struct DockPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// The gear opens the menu it always has — Insights, Preferences, Shortcuts,
/// the notes folder, Feedback, Quit — upwards from the foot.
private struct DockGearButton: View {
    @ObservedObject private var store = TodoStore.shared

    var body: some View {
        DockRoundButton(label: L10n.t("settings.open"), iconColor: DSDock.settingsIcon) {
            // The floating panels' own gear (SettingsGearButton), 2026-10-17.
            DockIcon(.settings, size: NotchContainerMetrics.roundIcon + 2)
        } action: {
            DockState.shared.closeMenu()
            if store.showsAvatarMenu { store.closeAvatarMenu() } else { store.openAvatarMenu() }
        }
        .menuAnchor(.gear)
    }
}

// MARK: The dock

private struct DockLabelWidthKey: PreferenceKey {
    static let defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct DockContentWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct SpaceDock: View {
    @ObservedObject private var store = TodoStore.shared
    @ObservedObject private var dock = DockState.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var highlight

    /// Each space's label at its natural width, measured off-screen.
    @State private var labelWidths: [UUID: CGFloat] = [:]
    @State private var contentWidth: CGFloat = 0
    @State private var hovered: UUID?
    @State private var draggedID: UUID?
    @State private var dropBeforeID: UUID?
    @State private var dropAtEnd = false

    /// The space whose label is open: none while Notes is up.
    private var selectedID: UUID? {
        store.panelMode == .browsing ? store.activeCollectionID : nil
    }
    /// Where the highlight sits — parked on the last space in Notes.
    private var parkedID: UUID? { store.activeCollectionID }
    private var inNotes: Bool { store.panelMode == .notes || store.panelMode == .calendar }

    private var overflows: Bool { contentWidth > NotchContainerMetrics.dockMaxWidth }

    var body: some View {
        let collections = store.visibleCollections
        let capsule = Capsule(style: .circular)
        Group {
            if overflows {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) { items(collections) }
                        .frame(width: NotchContainerMetrics.dockMaxWidth)
                        .mask(edgeFades)
                        .onChange(of: selectedID) { id in
                            guard let id else { return }
                            withAnimation(NotchDockMotion.curve(reduceMotion: reduceMotion)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                }
            } else {
                items(collections)
            }
        }
        .padding(NotchContainerMetrics.dockPadding)
        // Circular, not continuous: the continuous capsule drew a stray
        // vertical stroke just past each end at this width (2026-10-14).
        .notchGlass(in: capsule)
        .fixedSize()
        // The labels, measured once at their natural width — the widths the
        // open label animates to. Never visible.
        .background(measurer(collections).hidden())
        .onPreferenceChange(DockLabelWidthKey.self) { labelWidths = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("dock.spaces"))
    }

    private func items(_ collections: [TodoCollection]) -> some View {
        HStack(spacing: NotchContainerMetrics.dockItemGap) {
            ForEach(Array(collections.enumerated()), id: \.element.id) { index, collection in
                item(collection, index: index)
            }
            // The trailing "+": a new space. It never takes the highlight.
            plusItem
                .onDrop(of: [.ottoInternalItem], delegate: CollectionEndDropDelegate(
                    draggedID: $draggedID, dropBeforeID: $dropBeforeID, dropAtEnd: $dropAtEnd))
                .overlay(alignment: .leading) {
                    if dropAtEnd { TabDropIndicator().offset(x: -2) }
                }
        }
        // One curve for the label widths and the highlight, so they move as
        // one. Keyed on the selection: the switch itself, not the panel's
        // own content spring, drives them.
        .animation(NotchDockMotion.curve(reduceMotion: reduceMotion), value: selectedID)
        .animation(NotchDockMotion.curve(reduceMotion: reduceMotion), value: labelWidths)
        .animation(.easeInOut(duration: 0.2), value: inNotes)
        .animation(NotchAnimation.hintFade, value: dropBeforeID)
        .background(GeometryReader { geo in
            Color.clear.preference(key: DockContentWidthKey.self, value: geo.size.width)
        })
        .onPreferenceChange(DockContentWidthKey.self) { contentWidth = $0 }
    }

    private func item(_ collection: TodoCollection, index: Int) -> some View {
        let tint = DockTint(collection.spaceTint)
        let isSelected = selectedID == collection.id
        let isParked = parkedID == collection.id
        let menuOpen = dock.menuSpaceID == collection.id
        return HStack(spacing: 0) {
            Circle()
                .fill(tint.base)
                .frame(width: NotchContainerMetrics.dockDot, height: NotchContainerMetrics.dockDot)
                .brightness(hovered == collection.id && !isSelected ? 0.08 : 0)
                .modifier(DockPop(isActive: isSelected || dock.justCreatedID == collection.id))
            label(collection.name, color: tint.light)
                .frame(width: isSelected ? (labelWidths[collection.id] ?? 0) : 0, alignment: .leading)
                .clipped()
        }
        .padding(.horizontal, NotchContainerMetrics.dockItemPaddingH)
        .frame(height: NotchContainerMetrics.dockItem)
        .background {
            // THE highlight: one capsule, moved between items by matched
            // geometry. In Notes it fades out where it stands.
            if isParked {
                Capsule(style: .circular)
                    .fill(tint.highlight)
                    .matchedGeometryEffect(id: "dockHighlight", in: highlight)
                    .opacity(inNotes ? 0 : 1)
                    .animation(.easeInOut(duration: 0.3), value: tint)
            } else if menuOpen || hovered == collection.id {
                // Hover lights the dot's own slot (Marcello, 2026-10-17); the
                // item a menu came from stays lit.
                Capsule(style: .circular).fill(Color.white.opacity(menuOpen ? 0.10 : 0.08))
                    .transition(.opacity.animation(.easeOut(duration: 0.15)))
            }
        }
        .opacity(inNotes ? 0.5 : (draggedID == collection.id ? 0.4 : 1))
        .contentShape(Capsule(style: .circular))
        // Not a Button: a Button claims the mouse-down and `.onDrag` beside it
        // never starts (TodoTabRow's lesson).
        .onTapGesture {
            dock.closeMenu()
            BarTipState.shared.clicked(collection.id.uuidString)
            store.selectCollection(collection.id)
        }
        .overlay(RightClickCatcher { dock.openMenu(for: collection.id) })
        .modifier(DockMenuAnchor(active: menuOpen))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) {
                if hovering { hovered = collection.id }
                else if hovered == collection.id { hovered = nil }
            }
        }
        // The bar's one tooltip — never over the active pill, which already
        // says its name, nor while dragging.
        .barTip(collection.id.uuidString,
                isSelected || draggedID != nil ? nil : BarTip(label: collection.name, shortcut: nil))
        .id(collection.id)
        .onDrag {
            draggedID = collection.id
            return .ottoInternal(collection.id)
        } preview: {
            Circle().fill(tint.base).frame(width: 12, height: 12)
        }
        .overlay(alignment: .leading) {
            if dropBeforeID == collection.id { TabDropIndicator().offset(x: -2) }
        }
        .onDrop(of: [.ottoInternalItem], delegate: CollectionReorderDropDelegate(
            targetID: collection.id, draggedID: $draggedID,
            dropBeforeID: $dropBeforeID, dropAtEnd: $dropAtEnd))
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(collection.name)
    }

    private func label(_ name: String, color: Color) -> some View {
        Text(name)
            .font(DSDock.dockLabel)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .padding(.leading, NotchContainerMetrics.dockLabelLeading)
            .padding(.trailing, NotchContainerMetrics.dockLabelTrailing)
    }

    /// Every label at its natural width, reported by id.
    private func measurer(_ collections: [TodoCollection]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(collections) { collection in
                label(collection.name, color: .clear)
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: DockLabelWidthKey.self,
                                               value: [collection.id: ceil(geo.size.width)])
                    })
            }
        }
        .fixedSize()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var plusItem: some View {
        Button {
            dock.beginNewSpace()
            NotchController.shared.focusPanel()
        } label: {
            DockIcon(.plus, size: 15)
                .foregroundStyle(DSDock.plus)
                .frame(width: NotchContainerMetrics.dockItem, height: NotchContainerMetrics.dockItem)
                .contentShape(Capsule(style: .circular))
        }
        .buttonStyle(.plain)
        .barTip("dock.plus", label: L10n.t("todo.newCollection"), shortcut: "\u{21E7}\u{2318}N")
        .accessibilityLabel(L10n.t("todo.newCollection"))
    }

    private var edgeFades: some View {
        LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .black, location: 0.08),
            .init(color: .black, location: 0.92),
            .init(color: .clear, location: 1),
        ], startPoint: .leading, endPoint: .trailing)
    }
}

/// Reports a dock item's frame as the space menu's anchor — only for the item
/// whose menu is open.
private struct DockMenuAnchor: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active { content.menuAnchor(.dockItem) } else { content }
    }
}

/// The pop on a dot that becomes active (Rise), and on a space just created
/// (final flow §7.3: scale 0.5 → 1, 500 ms, overshoot).
private struct DockPop: ViewModifier {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onChange(of: isActive) { active in
                guard active, NotchDockMotion.current == .rise, !reduceMotion else { return }
                withAnimation(.timingCurve(0.3, 1.6, 0.5, 1, duration: 0.17)) { scale = 1.45 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) {
                    withAnimation(.timingCurve(0.3, 1.6, 0.5, 1, duration: 0.25)) { scale = 1 }
                }
            }
            .onAppear {
                // A brand-new space pops in.
                guard isActive, DockState.shared.justCreatedID != nil, !reduceMotion else { return }
                scale = 0.5
                withAnimation(.timingCurve(0.3, 1.6, 0.5, 1, duration: 0.5)) { scale = 1 }
            }
    }
}
