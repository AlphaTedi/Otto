import SwiftUI

// MARK: - The B3 dock's bottom bar (spec §3, §5.2, §5.6)
//
//   (Notes)(Meetings)        ( ● ● [● Work 5] ● + )        (⚙)
//
// A three-column grid: the round buttons left, the dock centred, the gear
// right. The dock has ONE highlight that slides between spaces — the thing
// that makes a switch read as one motion — and the active space opens a
// label whose width animates from 0 to its measured width while the one
// before closes on the same curve, so the dock's width barely moves.

struct DockBottomBar: View {
    @ObservedObject private var store = TodoStore.shared

    private var inNotes: Bool { store.panelMode == .notes }
    private var inMeetings: Bool { store.panelMode == .calendar }

    var body: some View {
        // `1fr auto 1fr`: equal flexible sides, so the dock sits at the true
        // centre whatever the two sides hold.
        HStack(spacing: NotchContainerMetrics.barGap) {
            HStack(spacing: NotchContainerMetrics.barGap) {
                DockRoundButton(label: L10n.t("filter.notes"), isOn: inNotes, onTint: DSDock.notes,
                                onIcon: DSDock.notesLight, iconColor: DSDock.notes) {
                    DocGlyph()
                } action: {
                    NotesStore.shared.chooseKind(meetings: false)
                }
                // Meetings: the second round button (decision 4, 2026-10-14).
                DockRoundButton(label: L10n.t("dock.meetings"), isOn: inMeetings,
                                onTint: SpaceTint.calendar.light.color,
                                onIcon: DockTint(.calendar).light, iconColor: DSDock.text2) {
                    OttoIcon("calendar", pointSize: NotchContainerMetrics.roundIcon - 1)
                } action: {
                    NotesStore.shared.chooseKind(meetings: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            SpaceDock()

            DockGearButton()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.top, NotchContainerMetrics.barTopGap)
    }
}

// MARK: Round buttons

/// 38-pt circles in the dock's own material, so the three read as one bar.
struct DockRoundButton<Icon: View>: View {
    let label: String
    var isOn = false
    var onTint: Color = DSDock.notes
    var onIcon: Color = DSDock.notesLight
    var iconColor: Color = DSDock.text2
    @ViewBuilder let icon: Icon
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            icon
                .foregroundStyle(isOn ? onIcon : (hover && iconColor == DSDock.text2 ? DSDock.iconHover : iconColor))
                .frame(width: NotchContainerMetrics.roundButton, height: NotchContainerMetrics.roundButton)
                .background(Circle().fill(isOn ? onTint.opacity(0.18) : DSDock.chrome))
                .overlay(Circle().strokeBorder(isOn ? onTint.opacity(0.3) : DSDock.chromeBorder, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(DockPressStyle())
        .onHover { hover = $0 }
        .animation(.easeInOut(duration: 0.3), value: isOn)
        .panelTooltip(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Pressing scales a round button to 0.93 over 150 ms (spec §8.4).
struct DockPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// The gear opens the menu it always has — Insights, Preferences, Shortcuts,
/// the notes folder, Feedback, Quit — upwards from the foot (decision 3).
private struct DockGearButton: View {
    @ObservedObject private var store = TodoStore.shared

    var body: some View {
        DockRoundButton(label: L10n.t("settings.open"), isOn: false, iconColor: DSDock.text2) {
            SlidersGlyph()
        } action: {
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var highlight

    /// Each space's label at its natural width, measured off-screen.
    @State private var labelWidths: [UUID: CGFloat] = [:]
    @State private var contentWidth: CGFloat = 0
    @State private var hovered: UUID?
    @State private var draggedID: UUID?
    @State private var dropBeforeID: UUID?
    @State private var dropAtEnd = false

    /// The space whose label is open: none while Notes or Meetings is up.
    private var selectedID: UUID? {
        store.panelMode == .browsing ? store.activeCollectionID : nil
    }
    /// Where the highlight sits — parked on the last space in Notes.
    private var parkedID: UUID? { store.activeCollectionID }
    private var inNotes: Bool { store.panelMode == .notes || store.panelMode == .calendar }

    private var overflows: Bool { contentWidth > NotchContainerMetrics.dockMaxWidth }

    var body: some View {
        let collections = store.visibleCollections
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
        // A circular-cornered capsule: the continuous one drew a stray
        // vertical stroke just past each end at this width.
        .background(Capsule(style: .circular).fill(DSDock.chrome))
        .overlay(Capsule(style: .circular).strokeBorder(DSDock.chromeBorder, lineWidth: 1))
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
        // one (spec §8). Keyed on the selection: the switch itself, not the
        // panel's own content spring, drives them.
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
        let open = store.remainingCount(for: collection) ?? 0
        return HStack(spacing: 0) {
            Circle()
                .fill(tint.base)
                .frame(width: NotchContainerMetrics.dockDot, height: NotchContainerMetrics.dockDot)
                .brightness(hovered == collection.id && !isSelected ? 0.08 : 0)
                .modifier(DockPop(isActive: isSelected))
            label(collection.name, count: open, color: tint.light)
                .frame(width: isSelected ? (labelWidths[collection.id] ?? 0) : 0, alignment: .leading)
                .clipped()
        }
        .padding(.horizontal, NotchContainerMetrics.dockItemPaddingH)
        .frame(height: NotchContainerMetrics.dockItem)
        .background {
            // THE highlight: one capsule, moved between items by matched
            // geometry. In Notes it fades out where it stands.
            if isParked {
                Capsule(style: .continuous)
                    .fill(tint.highlight)
                    .matchedGeometryEffect(id: "dockHighlight", in: highlight)
                    .opacity(inNotes ? 0 : 1)
                    .animation(.easeInOut(duration: 0.3), value: tint)
            }
        }
        .opacity(inNotes ? 0.5 : (draggedID == collection.id ? 0.4 : 1))
        .contentShape(Capsule(style: .continuous))
        // Not a Button: a Button claims the mouse-down and `.onDrag` beside it
        // never starts (TodoTabRow's lesson).
        .onTapGesture { store.selectCollection(collection.id) }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) {
                if hovering { hovered = collection.id } else if hovered == collection.id { hovered = nil }
            }
        }
        .overlay(alignment: .top) {
            // The name, over an inactive dot only (spec §5.2).
            if hovered == collection.id, !isSelected, draggedID == nil {
                Text(collection.name)
                    .font(DSDock.tooltipFont)
                    .foregroundStyle(DSDock.tooltipText)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 9)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DSDock.tooltip))
                    .fixedSize()
                    .offset(y: -(12 + 26))
                    .transition(.opacity.combined(with: .offset(y: 4)))
                    .allowsHitTesting(false)
            }
        }
        .zIndex(hovered == collection.id ? 1 : 0)
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
        .contextMenu { CollectionContextMenu(collection: collection, index: index) }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(collection.name)
        .accessibilityValue(String(format: L10n.t("dock.open"), open))
    }

    private func label(_ name: String, count: Int, color: Color) -> some View {
        HStack(spacing: NotchContainerMetrics.dockCountGap) {
            Text(name).font(DSDock.dockLabel)
            Text("\(count)").font(DSDock.dockCount).opacity(0.6)
                .contentTransition(.numericText())
        }
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
                label(collection.name, count: store.remainingCount(for: collection) ?? 0, color: .clear)
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
            store.setMode(.newCategory)
            NotchController.shared.focusPanel()
        } label: {
            OttoIcon("plus", pointSize: 12)
                .foregroundStyle(DSDock.plus)
                .frame(width: NotchContainerMetrics.dockItem, height: NotchContainerMetrics.dockItem)
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .panelTooltip(L10n.t("todo.newCollection"))
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

/// Rise's "pop" on the dot that becomes active: 1 → 1.45 → 1 over 420 ms.
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
    }
}

// MARK: Glyphs (the prototype's own strokes, 24-unit grid)

/// The Notes document: a page with a folded corner and two lines.
struct DocGlyph: View {
    var body: some View {
        DocShape()
            .stroke(style: StrokeStyle(lineWidth: 1.8 * NotchContainerMetrics.roundIcon / 24,
                                       lineCap: .round, lineJoin: .round))
            .frame(width: NotchContainerMetrics.roundIcon, height: NotchContainerMetrics.roundIcon)
    }

    private struct DocShape: Shape {
        func path(in rect: CGRect) -> Path {
            let s = rect.width / 24
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
            var path = Path()
            path.move(to: p(6, 3)); path.addLine(to: p(15, 3)); path.addLine(to: p(19, 7))
            path.addLine(to: p(19, 21)); path.addLine(to: p(6, 21)); path.closeSubpath()
            path.move(to: p(9, 12)); path.addLine(to: p(16, 12))
            path.move(to: p(9, 16)); path.addLine(to: p(14, 16))
            return path
        }
    }
}

/// Settings: two sliders.
struct SlidersGlyph: View {
    var body: some View {
        SlidersShape()
            .stroke(style: StrokeStyle(lineWidth: 1.7 * NotchContainerMetrics.roundIcon / 24, lineCap: .round))
            .frame(width: NotchContainerMetrics.roundIcon, height: NotchContainerMetrics.roundIcon)
    }

    private struct SlidersShape: Shape {
        func path(in rect: CGRect) -> Path {
            let s = rect.width / 24
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
            var path = Path()
            path.move(to: p(4, 7)); path.addLine(to: p(13, 7))
            path.move(to: p(17, 7)); path.addLine(to: p(20, 7))
            path.move(to: p(4, 17)); path.addLine(to: p(7, 17))
            path.move(to: p(11, 17)); path.addLine(to: p(20, 17))
            path.addEllipse(in: CGRect(x: rect.minX + 13 * s, y: rect.minY + 5 * s, width: 4 * s, height: 4 * s))
            path.addEllipse(in: CGRect(x: rect.minX + 7 * s, y: rect.minY + 15 * s, width: 4 * s, height: 4 * s))
            return path
        }
    }
}
