import SwiftUI

// MARK: - OnboardingFlowView — router, progress, footer (v3 SPEC §2, §3.4)
//
// Welcome is a single centred stack over a full-window glow. Steps 2–6 are a
// split: a 360-pt left column (progress, title, body, content, footer) and a
// 490×480 visual panel inset 10 pt from the top, right and bottom. The window
// never moves or resizes; only the content changes.

struct OnboardingFlowView: View {
    @ObservedObject var model: OnboardingModel
    /// The step's primary action — owned by the window controller, which is
    /// the one that can close the window on the last step.
    let primary: () -> Void

    var body: some View {
        withPalette { p in
            ZStack {
                p.window
                if model.step == .welcome {
                    WelcomeStepView(model: model, primary: primary)
                        .transition(.opacity.animation(.easeInOut(duration: 0.35)))
                } else {
                    split(p)
                        .transition(.opacity.animation(.easeInOut(duration: 0.35)))
                }
            }
            .frame(width: OBMetric.windowSize.width, height: OBMetric.windowSize.height)
            .clipShape(RoundedRectangle(cornerRadius: OBMetric.windowRadius, style: .continuous))
            .ignoresSafeArea()
        }
    }

    // MARK: Split layout

    private func split(_ p: OBPalette) -> some View {
        ZStack(alignment: .topLeading) {
            leftColumn(p)
                .frame(width: OBMetric.columnWidth, height: OBMetric.windowSize.height)

            progressBar(p)
                .offset(x: 32, y: 18)

            panel(p)
                .offset(x: OBMetric.columnWidth, y: 10)
        }
        .frame(width: OBMetric.windowSize.width, height: OBMetric.windowSize.height,
               alignment: .topLeading)
    }

    private func leftColumn(_ p: OBPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title → body → content slide 12 pt and fade together (§9).
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 10) {
                    OBText(text: model.step.title, size: 22, weight: 500, lineHeight: 26.4,
                           tracking: -0.22, color: p.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    OBText(text: model.step.body, size: 13, lineHeight: 19.5, color: p.textSecondary)
                    // 48 below the body on every split screen (v3 §3.4) — on
                    // top of the column's 10 of spacing, which is what the
                    // reference HTML (a 10-pt flex gap plus a 48-pt margin)
                    // and its PNGs actually draw.
                    stepContent
                        .padding(.top, 48)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(model.step)
                .transition(.asymmetric(
                    insertion: .offset(x: 12 * model.direction).combined(with: .opacity),
                    removal: .opacity
                ).animation(.easeOut(duration: 0.28)))
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(.top, 46)
        .padding(.trailing, 28)
        .padding(.bottom, 26)
        .padding(.leading, 32)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .welcome: EmptyView()
        case .discover: DiscoverStepContent(model: model)
        case .style: StyleStepContent(model: model)
        case .shortcut: ShortcutStepContent(model: model)
        case .permissions: PermissionsStepContent(model: model, permissions: model.permissions)
        case .done: DoneStepContent()
        }
    }

    private var footer: some View {
        HStack {
            OBBackButton { model.back() }
            Spacer()
            OttoButton(title: model.step.primaryTitle,
                       isEnabled: model.canAdvance,
                       shortcutDescription: "Return",
                       action: primary)
        }
    }

    // MARK: Progress (§4)

    private func progressBar(_ p: OBPalette) -> some View {
        let width = OBMetric.progressWidth
        return ZStack(alignment: .leading) {
            Capsule().fill(p.track)
            // The gradient spans all 300 pt and is masked to the fill, so the
            // early steps are violet and green only arrives at the end.
            LinearGradient(gradient: OBGradient.progress, startPoint: .leading, endPoint: .trailing)
                .frame(width: width)
                .mask(alignment: .leading) {
                    Capsule().frame(width: width * model.progress)
                }
        }
        .frame(width: width, height: 3)
        .clipShape(Capsule())
        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: model.progress)
        .accessibilityElement()
        .accessibilityLabel(String(format: L10n.t("ob.progress"),
                                   model.step.rawValue + 1, OnboardingStep.allCases.count))
    }

    // MARK: Visual panel (§4)

    private func panel(_ p: OBPalette) -> some View {
        ZStack {
            p.panel
            ZStack {
                // Its own identity, so a change of glow inside a step — the
                // amber Meetings stop, the green success — cross-fades too.
                OBGlowBackground(glows: onboardingGlows(model))
                    .id(glowIdentity)
                    .transition(.opacity.animation(.easeInOut(duration: 0.4)))
                panelContent
            }
            .id(model.step)
            .transition(.opacity.animation(.easeInOut(duration: 0.35)))
        }
        .frame(width: OBMetric.panelSize.width, height: OBMetric.panelSize.height)
        .clipShape(OBMetric.panelShape)
    }

    private var glowIdentity: String {
        "\(model.discoverItem == .meetings)-\(model.displayMode)-\(model.shortcutDetected)"
    }

    @ViewBuilder
    private var panelContent: some View {
        switch model.step {
        case .welcome: EmptyView()
        case .discover: DiscoverPanel(model: model)
        case .style: StylePanel(model: model)
        case .shortcut: ShortcutPanel(model: model)
        case .permissions: PermissionsPanel(permissions: model.permissions)
        case .done: DonePanel()
        }
    }
}
