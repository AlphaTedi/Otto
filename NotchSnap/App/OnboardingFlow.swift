import SwiftUI

// MARK: - OnboardingFlowView — router, progress, footer (SPEC §4, §9)
//
// Welcome is a single centred stack over a full-window glow. Steps 2–6 are a
// split: a 360-pt left column (progress, title, body, content, footer) and a
// 490×440 visual panel inset 10 pt from the top, right and bottom. The window
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
                    stepContent
                        .padding(.top, 10)
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
        case .focus: FocusStepContent(model: model)
        case .notch: NotchStepContent(model: model)
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
                       pulse: model.continuePulse,
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
                OBGlowBackground(glows: model.step.glows)
                panelContent
            }
            .id(model.step)
            .transition(.opacity.animation(.easeInOut(duration: 0.35)))
        }
        .frame(width: OBMetric.panelSize.width, height: OBMetric.panelSize.height)
        .clipShape(OBMetric.panelShape)
    }

    @ViewBuilder
    private var panelContent: some View {
        switch model.step {
        case .welcome: EmptyView()
        case .focus: FocusPanel(model: model)
        case .notch: NotchDemoPanel(model: model)
        case .shortcut: ShortcutPanel(model: model)
        case .permissions: PermissionsPanel(permissions: model.permissions)
        case .done: DonePanel()
        }
    }
}
