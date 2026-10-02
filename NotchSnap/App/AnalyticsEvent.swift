import Foundation

// MARK: - AnalyticsEvent — the catalogue (docs/TELEMETRY.md §3.5)
//
// Every event Otto can report, as a closed enum. There is no case that takes
// a String from the user: props are enum raw values, Bools, Ints and buckets,
// so a to-do title, a note or a meeting name cannot reach `track` by
// construction. The server keeps the same list and refuses anything else
// (server/src/events.ts) — change both together.

enum AnalyticsEvent {
    enum LaunchKind: String { case cold, loginItem = "login_item", afterUpdate = "after_update" }
    enum OpenTrigger: String { case hover, click, hotkey, intent, meetingAlert = "meeting_alert", drag, onboarding, appIcon = "app_icon", other }
    enum TodoSource: String { case draft, intent, note }
    enum CompleteSource: String { case keyboard, click, intent }
    enum Permission: String { case calendar, login }
    enum PermissionResult: String { case granted, denied, on, off }
    enum FeedbackCategory: String, CaseIterable { case bug, idea, love, other }

    case appLaunched(LaunchKind)
    case appActiveDay
    case updateInstalled(from: String, to: String)

    case onboardingStarted
    case onboardingStepViewed(OnboardingStep)
    case onboardingStepCompleted(OnboardingStep, durationMs: Int)
    case onboardingDiscoverViewed(DiscoverItem)
    case onboardingStyleSelected(DisplayMode)
    case onboardingShortcutFired(attempts: Int)
    case onboardingShortcutSkipped
    case onboardingPermission(Permission, PermissionResult)
    case onboardingCompleted(totalMs: Int)
    case onboardingAbandoned(lastStep: OnboardingStep)

    case notchOpened(OpenTrigger, layout: NotchLayout)
    case todoCreated(TodoSource, hasDueDate: Bool)
    case todoCompleted(age: Bucket.Age)
    case noteCreated(meeting: Bool)

    case feedbackOpened
    case feedbackSent(FeedbackCategory, attachments: Int, diagnostics: Bool)

    var name: String {
        switch self {
        case .appLaunched: return "app_launched"
        case .appActiveDay: return "app_active_day"
        case .updateInstalled: return "update_installed"
        case .onboardingStarted: return "onboarding_started"
        case .onboardingStepViewed: return "onboarding_step_viewed"
        case .onboardingStepCompleted: return "onboarding_step_completed"
        case .onboardingDiscoverViewed: return "onboarding_discover_viewed"
        case .onboardingStyleSelected: return "onboarding_style_selected"
        case .onboardingShortcutFired: return "onboarding_shortcut_fired"
        case .onboardingShortcutSkipped: return "onboarding_shortcut_skipped"
        case .onboardingPermission: return "onboarding_permission"
        case .onboardingCompleted: return "onboarding_completed"
        case .onboardingAbandoned: return "onboarding_abandoned"
        case .notchOpened: return "notch_opened"
        case .todoCreated: return "todo_created"
        case .todoCompleted: return "todo_completed"
        case .noteCreated: return "note_created"
        case .feedbackOpened: return "feedback_opened"
        case .feedbackSent: return "feedback_sent"
        }
    }

    var props: [String: AnalyticsValue] {
        switch self {
        case .appLaunched(let kind): return ["kind": .enumCase(kind.rawValue)]
        case .appActiveDay, .onboardingStarted, .feedbackOpened: return [:]
        case .updateInstalled(let from, let to): return ["from": .version(from), "to": .version(to)]
        case .onboardingStepViewed(let step): return ["step": .enumCase(step.analyticsName)]
        case .onboardingStepCompleted(let step, let ms):
            return ["step": .enumCase(step.analyticsName), "duration_ms": .int(Bucket.ms(ms))]
        case .onboardingDiscoverViewed(let item): return ["item": .enumCase(item.analyticsName)]
        case .onboardingStyleSelected(let mode): return ["mode": .enumCase(mode.rawValue)]
        case .onboardingShortcutFired(let attempts): return ["attempts": .int(attempts)]
        case .onboardingShortcutSkipped: return ["reason": .enumCase("taken")]
        case .onboardingPermission(let perm, let result):
            return ["perm": .enumCase(perm.rawValue), "result": .enumCase(result.rawValue)]
        case .onboardingCompleted(let ms): return ["total_ms": .int(Bucket.ms(ms))]
        case .onboardingAbandoned(let step): return ["last_step": .enumCase(step.analyticsName)]
        case .notchOpened(let trigger, let layout):
            return ["trigger": .enumCase(trigger.rawValue), "layout": .enumCase(layout.rawValue)]
        case .todoCreated(let source, let due):
            return ["source": .enumCase(source.rawValue), "has_due_date": .bool(due)]
        case .todoCompleted(let age): return ["age": .enumCase(age.rawValue)]
        case .noteCreated(let meeting): return ["kind": .enumCase(meeting ? "meeting" : "note")]
        case .feedbackSent(let category, let attachments, let diagnostics):
            return ["category": .enumCase(category.rawValue), "attachments": .int(min(attachments, 5)),
                    "diagnostics": .bool(diagnostics)]
        }
    }
}

/// A prop value. The only way to make a string is from an enum case or an
/// app version — never from text someone typed.
enum AnalyticsValue: Encodable, Equatable {
    case bool(Bool)
    case int(Int)
    case string(String)

    static func enumCase(_ raw: String) -> AnalyticsValue { .string(raw) }
    static func version(_ version: String) -> AnalyticsValue {
        .string(version.filter { $0.isNumber || $0 == "." }.prefix(20).description)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        }
    }
}

/// Coarse values, so a number can never identify anyone (§3.4).
enum Bucket {
    enum Age: String { case lt1h, lt1d, lt7d, gte7d }

    static func age(since date: Date, now: Date = Date()) -> Age {
        let seconds = now.timeIntervalSince(date)
        if seconds < 3600 { return .lt1h }
        if seconds < 86_400 { return .lt1d }
        if seconds < 7 * 86_400 { return .lt7d }
        return .gte7d
    }

    /// Milliseconds rounded to 100.
    static func ms(_ value: Int) -> Int { max(0, (value + 50) / 100 * 100) }
}

extension OnboardingStep {
    var analyticsName: String {
        switch self {
        case .welcome: return "welcome"
        case .discover: return "discover"
        case .style: return "style"
        case .shortcut: return "shortcut"
        case .permissions: return "permissions"
        case .done: return "done"
        }
    }
}

extension DiscoverItem {
    var analyticsName: String {
        switch self {
        case .tasks: return "tasks"
        case .notes: return "notes"
        case .meetings: return "meetings"
        }
    }
}
