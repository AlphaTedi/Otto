import AppKit
import SwiftUI
import Foundation

// MARK: - Analytics — anonymous, opt-in usage counts (docs/TELEMETRY.md)
//
// `Analytics.track(.something)` is the whole API. It does nothing at all —
// no file, no network — unless the user said yes (`analyticsConsent ==
// .granted`), the build is not the lab, and a service URL is configured.
//
// One exception, and only in memory: before the question has been answered
// (`consent == nil`), events wait in a small buffer. The onboarding asks on
// its permissions step, and without the buffer its own funnel — the first
// thing worth knowing — could never be seen. A yes flushes the buffer into
// the queue; a no, or quitting, throws it away unsent.
//
// The queue is a JSON-lines file in Application Support ("Show what is sent"
// in Settings opens it), flushed every 60 s, at 20 events, and on quit.

enum AnalyticsConsent: String, Codable {
    case granted, denied
}

@MainActor
enum Analytics {
    // MARK: Configuration

    /// `https://$(OTTO_SERVICE_HOST)` from Info.plist, via Local.xcconfig.
    static let serviceURL: URL? = {
        guard let host = Bundle.main.object(forInfoDictionaryKey: "OttoServiceHost") as? String,
              !host.isEmpty, !host.contains("$(") else { return nil }
        return URL(string: "https://\(host)")
    }()

    static let serviceKey: String = Bundle.main.object(forInfoDictionaryKey: "OttoServiceKey") as? String ?? ""

    static var consent: AnalyticsConsent? { AppState.shared.settings.analyticsConsent }

    /// Everything that must be true before a single byte leaves the Mac.
    static var isSending: Bool {
        AppBuild.analyticsEnabled && consent == .granted && serviceURL != nil
    }

    // MARK: Identity

    private static let installIDKey = "otto.analytics.installID"
    private static let activeDayKey = "otto.analytics.activeDay"

    /// Random, made on first send, tied to nothing — not the hardware, not
    /// an account. "Reset ID" in Settings replaces it.
    static var installID: String {
        if let id = UserDefaults.standard.string(forKey: installIDKey) { return id }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: installIDKey)
        return id
    }

    static let sessionID = UUID().uuidString.lowercased()

    // MARK: API

    private static var pending: [QueuedEvent] = []

    static func track(_ event: AnalyticsEvent) {
        guard AppBuild.analyticsEnabled else { return }
        let queued = QueuedEvent(name: event.name, ts: Date(), props: event.props)
        switch consent {
        case .denied?:
            return
        case nil:
            // Not asked yet: memory only, dropped on a no or at quit.
            if pending.count < 200 { pending.append(queued) }
        case .granted?:
            markActiveDay()
            AnalyticsQueue.shared.append(queued)
        }
    }

    /// The user's answer, from the onboarding, the panel card or Settings.
    static func setConsent(_ granted: Bool) {
        AppState.shared.updateSettings { $0.analyticsConsent = granted ? .granted : .denied }
        if granted {
            markActiveDay()
            for event in pending { AnalyticsQueue.shared.append(event) }
            pending.removeAll()
            AnalyticsQueue.shared.start()
            AnalyticsQueue.shared.flushSoon()
        } else {
            pending.removeAll()
            AnalyticsQueue.shared.clear()
        }
    }

    /// A new random ID and an empty queue: nothing sent so far can be tied
    /// to what is sent next.
    static func resetID() {
        UserDefaults.standard.removeObject(forKey: installIDKey)
        UserDefaults.standard.removeObject(forKey: activeDayKey)
        AnalyticsQueue.shared.clear()
    }

    static func flush() { AnalyticsQueue.shared.flushNow() }

    /// Launch-time bookkeeping: the launch itself, an update, an onboarding
    /// that was left mid-way.
    static func appDidLaunch() {
        let defaults = UserDefaults.standard
        let version = appVersion
        let previous = defaults.string(forKey: "otto.analytics.lastVersion")
        defaults.set(version, forKey: "otto.analytics.lastVersion")
        if let previous, previous != version {
            track(.appLaunched(.afterUpdate))
            track(.updateInstalled(from: previous, to: version))
        } else {
            track(.appLaunched(.cold))
        }
        // A quit mid-flow leaves `onboarding.lastStep` past the start; the
        // flow resumes, and this is the one record that it was left.
        let lastStep = defaults.integer(forKey: OnboardingModel.Keys.lastStep)
        if lastStep > 0, let step = OnboardingStep(rawValue: lastStep), step != .done,
           defaults.integer(forKey: "onboardingVersion") < 1 {
            track(.onboardingAbandoned(lastStep: step))
        }
        if isSending { AnalyticsQueue.shared.start() }
        FeedbackOutbox.shared.retryPending()
    }

    private static func markActiveDay() {
        let today = ISO8601DateFormatter.day.string(from: Date())
        guard UserDefaults.standard.string(forKey: activeDayKey) != today else { return }
        UserDefaults.standard.set(today, forKey: activeDayKey)
        AnalyticsQueue.shared.append(QueuedEvent(name: AnalyticsEvent.appActiveDay.name, ts: Date(), props: [:]))
    }

    // MARK: Context sent with every batch — never content

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static func context() -> [String: AnalyticsValue] {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let build = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        #if DEBUG
        let env = "dev"
        #else
        let env = "prod"
        #endif
        return [
            "app_version": .version(appVersion),
            "build": .int(build),
            "os": .version("\(os.majorVersion).\(os.minorVersion)"),
            "lang": .string(lang.lowercased().filter { $0.isLetter }.prefix(3).description),
            "layout": .string(AppState.shared.notchLayout.rawValue),
            "has_notch": .bool(NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }),
            "calendar": .string(CalendarStore.shared.source == .google ? "google" : "eventkit"),
            "env": .string(env),
        ]
    }

    /// The file behind "Show what is sent".
    static var queueFileURL: URL { AnalyticsQueue.fileURL }
}

struct QueuedEvent: Codable {
    let name: String
    let ts: Date
    let props: [String: AnalyticsValue]
}

extension AnalyticsValue: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else { self = .string(try c.decode(String.self)) }
    }
}

extension ISO8601DateFormatter {
    @MainActor static let day: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = .current
        return f
    }()
}

// MARK: - AnalyticsQueue — on disk, batched, patient

@MainActor
final class AnalyticsQueue {
    static let shared = AnalyticsQueue()

    static var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppBuild.supportRoot, isDirectory: true)
        return support.appendingPathComponent("analytics-queue.jsonl")
    }

    private static let maxEvents = 2000
    private static let maxAge: TimeInterval = 7 * 86_400
    private static let batchSize = 100

    private var events: [QueuedEvent] = []
    private var loaded = false
    private var timer: Timer?
    private var sending = false
    private var failures = 0
    private var nextAttempt = Date.distantPast

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func start() {
        load()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { AnalyticsQueue.shared.flushSoon() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func append(_ event: QueuedEvent) {
        load()
        events.append(event)
        prune()
        persist()
        if events.count >= 20 { flushSoon() }
    }

    func clear() {
        events.removeAll()
        loaded = true
        try? FileManager.default.removeItem(at: Self.fileURL)
    }

    /// Sends if allowed and not backing off.
    func flushSoon() {
        guard Analytics.isSending, !sending, !events.isEmpty, Date() >= nextAttempt else { return }
        send()
    }

    /// At quit: one last attempt, ignoring the back-off; whatever does not
    /// make it stays on disk for next launch.
    func flushNow() {
        guard Analytics.isSending, !sending, !events.isEmpty else { return }
        send()
    }

    private func send() {
        guard let base = Analytics.serviceURL else { return }
        let batch = Array(events.prefix(Self.batchSize))
        let payload = Payload(install_id: Analytics.installID, session_id: Analytics.sessionID,
                              context: Analytics.context(),
                              events: batch.map { .init(name: $0.name, ts: $0.ts, props: $0.props) })
        guard let body = try? encoder.encode(payload) else { return }
        var request = URLRequest(url: base.appendingPathComponent("v1/events"))
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Analytics.serviceKey, forHTTPHeaderField: "X-Otto-Key")
        request.setValue("Otto/\(Analytics.appVersion)", forHTTPHeaderField: "User-Agent")
        sending = true
        URLSession.shared.dataTask(with: request) { _, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            Task { @MainActor in AnalyticsQueue.shared.finished(sent: batch.count, status: status) }
        }.resume()
    }

    private func finished(sent: Int, status: Int) {
        sending = false
        switch status {
        case 200..<300:
            events.removeFirst(min(sent, events.count))
            failures = 0
            nextAttempt = .distantPast
            persist()
            if !events.isEmpty { flushSoon() }
        case 400:
            // Refused as malformed: retrying the same batch would fail
            // forever and block everything behind it.
            events.removeFirst(min(sent, events.count))
            persist()
        default:
            // Offline or the server is down: 1, 2, 4 … minutes, up to an hour.
            failures += 1
            nextAttempt = Date().addingTimeInterval(min(3600, 60 * pow(2, Double(failures - 1))))
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: Self.fileURL),
              let text = String(data: data, encoding: .utf8) else { return }
        events = text.split(separator: "\n").compactMap {
            try? decoder.decode(QueuedEvent.self, from: Data($0.utf8))
        }
        prune()
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-Self.maxAge)
        events.removeAll { $0.ts < cutoff }
        if events.count > Self.maxEvents { events.removeFirst(events.count - Self.maxEvents) }
    }

    private func persist() {
        let url = Self.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lines = events.compactMap { try? encoder.encode($0) }.compactMap { String(data: $0, encoding: .utf8) }
        if lines.isEmpty { try? FileManager.default.removeItem(at: url); return }
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private struct Payload: Encodable {
        struct Event: Encodable {
            let name: String
            let ts: Date
            let props: [String: AnalyticsValue]
        }
        let install_id: String
        let session_id: String
        let context: [String: AnalyticsValue]
        let events: [Event]
    }

    #if DEBUG
    /// DebugDriver `analytics-dump`.
    func debugDump() -> String {
        load()
        return "consent=\(Analytics.consent.map(\.rawValue) ?? "nil") sending=\(Analytics.isSending) "
            + "queued=\(events.count) names=\(events.map(\.name))"
    }
    #endif
}

// MARK: - The one-time question, for people who never saw the onboarding ask

/// Anyone updating from a version without telemetry has `consent == nil` and
/// will not see the onboarding again. The panel asks them once, inline — a
/// card, not a window — and ⏎ / Esc answer it (keyboard-first).
@MainActor
final class ConsentPrompt: ObservableObject {
    static let shared = ConsentPrompt()

    @Published private(set) var visible: Bool

    private init() {
        visible = AppBuild.analyticsEnabled && Analytics.serviceURL != nil
            && AppState.shared.settings.analyticsConsent == nil
            && UserDefaults.standard.integer(forKey: "onboardingVersion") >= 1
    }

    func answer(_ share: Bool) {
        Analytics.setConsent(share)
        withAnimation(.easeOut(duration: 0.2)) { visible = false }
    }
}

struct ConsentCard: View {
    @ObservedObject private var prompt = ConsentPrompt.shared

    var body: some View {
        if prompt.visible {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.t("consent.title"))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(DSColor.textPrimaryBright)
                Text(L10n.t("consent.body"))
                    .font(.system(size: 12))
                    .foregroundStyle(DSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Spacer()
                    Button { prompt.answer(false) } label: {
                        HStack(spacing: 6) {
                            Text(L10n.t("consent.no"))
                            CaptureKeyHint(label: "esc")
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DSColor.textSecondary)
                    Button { prompt.answer(true) } label: {
                        HStack(spacing: 6) {
                            Text(L10n.t("consent.yes")).font(.system(size: 12.5, weight: .semibold))
                            CaptureKeyHint(label: "\u{21A9}")
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(SpaceInk.a(0.12)))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DSColor.textPrimaryBright)
                }
                .font(.system(size: 12.5))
            }
            .padding(14)
            .frame(maxWidth: 420, alignment: .leading)
            .ottoMenuSurface()
            .transition(.opacity.combined(with: .offset(y: 6)))
        }
    }
}
