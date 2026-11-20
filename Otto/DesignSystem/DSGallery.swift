import SwiftUI

// MARK: - The design system, on one page
//
// Every component in DesignSystem/, drawn on both surfaces. Open this file in
// Xcode and use the canvas: it is the catalogue docs/DESIGN_SYSTEM.md points
// at. A new component is added HERE in the same change that adds it.
//
// The panels column follows the canvas' Light/Dark; the container column is
// black in both, as the real notch is.

#if DEBUG
struct DSGallery: View {
    var body: some View {
        HStack(alignment: .top, spacing: DSSpace.section) {
            DSGallerySurface(title: "Floating Panels")
                .ottoSurface(.panels)
                .padding(DSSpace.section)
                .liquidGlass(in: DSShape.squircle(DSRadius.block))

            DSGallerySurface(title: "Notch Container")
                .ottoSurface(.container)
                .darkGroundSurface()
                .padding(DSSpace.section)
                .background(DSShape.squircle(DSRadius.block).fill(Color.black))
        }
        .padding(DSSpace.section)
        .frame(width: 1060)
        .background(Color.gray.opacity(0.35))
    }
}

private struct DSGallerySurface: View {
    let title: String
    @Environment(\.dsPalette) private var palette
    @Environment(\.ottoSurface) private var surface
    @State private var checked = true

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.xxl) {
            Text(title).font(DSType.pageTitle).foregroundStyle(palette.textPrimary)

            group("Type") {
                VStack(alignment: .leading, spacing: DSSpace.xs) {
                    Text("Card title").font(DSType.cardTitle)
                    Text("Row title").font(DSType.rowTitle(surface))
                    Text("Body — running text").font(DSType.body)
                    Text("Meta · 3 more steps").font(DSType.meta).foregroundStyle(palette.textSecondary)
                    Text("Caption").font(DSType.caption).foregroundStyle(palette.textTertiary)
                }
                .foregroundStyle(palette.textPrimary)
            }

            group("Buttons") {
                VStack(alignment: .leading, spacing: DSSpace.m) {
                    HStack(spacing: DSSpace.m) {
                        PrimaryActionButton(title: "Primary") {}
                        PrimaryActionButton(title: "Secondary", variant: .secondary) {}
                        PrimaryActionButton(title: "Outline", variant: .outline) {}
                        PrimaryActionButton(title: "Ghost", variant: .ghost) {}
                        PrimaryActionButton(title: "Delete", variant: .destructive) {}
                    }
                    // The control scale, xs → xl, with the icon-only square of each.
                    ForEach(DSControlSize.allCases, id: \.self) { size in
                        HStack(spacing: DSSpace.m) {
                            PrimaryActionButton(title: "\(size)".uppercased(), shortcutHint: "\u{21A9}", size: size) {}
                            PrimaryActionButton(title: "Outline", variant: .outline, size: size) {}
                            Button {} label: { OttoIcon("mic", pointSize: size.iconSize) }
                                .buttonStyle(DSButtonStyle(variant: .ghost, size: size, square: true))
                            SpacePill(title: "Work", fill: SpaceTint.work.sectionColor, isActive: true,
                                      count: 4, size: size)
                        }
                    }
                }
                HStack(spacing: DSSpace.m) {
                    Button {} label: { OttoIcon("gearshape", pointSize: 18) }
                        .buttonStyle(DSIconButtonStyle(variant: .filled, size: DSSize.icon))
                    Button {} label: { OttoIcon("chevron.left", pointSize: 15) }
                        .buttonStyle(DSIconButtonStyle(shape: .squircle, size: 30))
                    Button {} label: { Text("B").font(.system(size: 12.5, weight: .bold)) }
                        .buttonStyle(DSIconButtonStyle(isActive: true))
                }
            }

            group("Keys") {
                HStack(spacing: DSSpace.m) {
                    Keycap(text: "\u{2318}N")
                    KeyBadge(text: "Tab", minWidth: 32, height: 19)
                    KeyBadge(text: "\u{2318}\u{21B5}", color: DSColor.rowAffordance)
                    KeyBadge(text: "esc", style: .hint)
                }
            }

            group("Selection") {
                HStack(spacing: DSSpace.l) {
                    DSCheckbox(size: .row, isChecked: checked, tint: SpaceTint.work.base.color)
                        .onTapGesture { checked.toggle() }
                    DSCheckbox(size: .row, isChecked: false, tint: SpaceTint.work.base.color)
                    DSCheckbox(size: .step, isChecked: true, tint: SpaceTint.personal.base.color)
                    DSCheckbox(size: .step, isChecked: false, tint: SpaceTint.personal.base.color, dashed: true)
                    DSCheckbox(size: .archive, isChecked: true, tint: PanelMetrics.accent)
                    SpacePill(title: "Work", fill: SpaceTint.work.sectionColor, isActive: true, count: 4)
                    SpacePill(title: "Notes", fill: SpaceTint.notes.sectionColor, isActive: false, count: 0,
                              zeroIsDone: false)
                }
            }

            group("Rows") {
                VStack(spacing: DSSpace.xs) {
                    galleryRow("Resting row", hover: false, focused: false)
                    galleryRow("Hovered row", hover: true, focused: false)
                    galleryRow("Focused row", hover: false, focused: true)
                    galleryRow("Opened row", hover: false, focused: false, expanded: true)
                    DropIndicator()
                }
            }

            group("Labels, fields, menus") {
                VStack(alignment: .leading, spacing: DSSpace.m) {
                    DSSectionLabel(text: "New section")
                    DSSectionLabel(text: "Completed · 2", style: .quiet)
                    Text("Section name")
                        .font(DSType.body)
                        .foregroundStyle(palette.placeholder)
                        .padding(.horizontal, DSSpace.xxl)
                        .padding(.vertical, DSSpace.l)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .dsFieldWell()
                    VStack(spacing: 0) {
                        DSMenuRow(label: "Preferences", icon: "gearshape", shortcut: "\u{2318},",
                                  isHighlighted: true) {}
                        DSMenuRow(label: "Meetings", isChecked: true, isEmphasized: true) {}
                        DSMenuRow(label: "Delete", destructive: true) {}
                    }
                    .padding(OttoMenuStyle.padding)
                    .frame(width: 260)
                    .ottoMenuSurface()
                }
            }
        }
        .frame(width: 460, alignment: .leading)
    }

    private func group<Content: View>(_ name: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DSSpace.s) {
            DSSectionLabel(text: name)
            content()
        }
    }

    private func galleryRow(_ text: String, hover: Bool, focused: Bool, expanded: Bool = false) -> some View {
        HStack(spacing: DSSpace.xl) {
            DSCheckbox(size: .row, isChecked: false, tint: SpaceTint.work.base.color)
            Text(text).font(DSType.rowTitle(surface)).foregroundStyle(palette.textPrimary)
            Spacer()
        }
        .padding(.horizontal, DSSpace.xl)
        .frame(minHeight: 37)
        .dsRowBackground(hover: hover, focused: focused, expanded: expanded)
    }
}

struct DSGallery_Previews: PreviewProvider {
    static var previews: some View {
        DSGallery().preferredColorScheme(.dark).previewDisplayName("Dark")
        DSGallery().preferredColorScheme(.light).previewDisplayName("Light")
    }
}
#endif
