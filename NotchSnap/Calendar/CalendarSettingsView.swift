import SwiftUI

// MARK: - CalendarSettingsView — the Calendar tab (calendar PRD §2)
//
// SU-1: connection lives in the standard Settings window, not the notch —
// the one deliberate exception to "everything lives in the notch", because
// granting calendar access is a rare, one-time, system-mediated action.
//
// Two sources (2026-07-26). macOS Calendar via EventKit was the original and
// still suits a Mac whose sync is healthy. Google OAuth was added because that
// assumption failed twice over: macOS stopped syncing Marcello's Google
// account entirely, and an ad-hoc-signed copy on a second Mac cannot obtain
// the calendar permission EventKit needs. Talking to Google directly sidesteps
// both — no macOS sync in the path, and no TCC prompt at all.

struct CalendarSettingsView: View {
    @ObservedObject private var calendar = CalendarStore.shared
    @State private var isConnecting = false
    @State private var probeLines: [String] = []
    @State private var clientID = ""
    @State private var clientSecret = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle(title: "Calendar",
                      subtitle: "Meetings in Today, and a heads-up before they start.")

            // Only offered when there is more than one usable source; a
            // one-option picker is just noise.
            let sources = CalendarStore.Source.available
            if sources.count > 1 {
                Picker(L10n.t("gcal.source"), selection: Binding(
                    get: { calendar.source },
                    set: { calendar.source = $0 }
                )) {
                    ForEach(sources) { source in
                        Text(source.label).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if calendar.isConnected {
                connected
            } else if calendar.source == .google, sources.contains(.google) {
                googleDisconnected
            } else {
                disconnected
            }
        }
    }

    // MARK: Google (disconnected)

    private var googleDisconnected: some View {
        SettingsSection_Card(title: L10n.t("gcal.title")) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.t("gcal.subtitle"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if GoogleOAuth.hasBundledCredentials {
                    // The shipped-credential case: one button, nothing else.
                    signInButton
                } else {
                    // No credential compiled in. Do NOT show a dead button
                    // beside a hidden panel — that was the worst of both
                    // (Marcello, 2026-07-28). Show the setup plainly instead.
                    setupSteps
                    LabeledContent(L10n.t("gcal.clientID")) {
                        TextField("", text: $clientID).textFieldStyle(.roundedBorder)
                    }
                    LabeledContent(L10n.t("gcal.clientSecret")) {
                        SecureField("", text: $clientSecret).textFieldStyle(.roundedBorder)
                    }
                    signInButton
                }

                if let error = calendar.lastError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "#E07A5F"))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear {
            if GoogleOAuth.shared.usesCustomCredentials {
                clientID = KeychainStore.get(KeychainStore.Key.clientID) ?? ""
                clientSecret = KeychainStore.get(KeychainStore.Key.clientSecret) ?? ""
            }
        }
    }

    private var signInButton: some View {
        Button {
            saveCredentialsAndConnect()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 12, weight: .medium))
                Text(isConnecting ? "Connecting\u{2026}" : L10n.t("gcal.signIn"))
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color(hex: "#111111"))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(hex: "#EEEEEE"))
            )
        }
        .buttonStyle(.plain)
        .disabled(isConnecting || !canSignIn)
    }

    /// Shown only in a build with no credential compiled in — i.e. to whoever
    /// is building the app, not to someone who was handed a finished copy.
    private var setupSteps: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t("gcal.setupIntro"))
                .font(.system(size: 11, weight: .semibold))
            ForEach(Array([L10n.t("gcal.step1"), L10n.t("gcal.step2"),
                           L10n.t("gcal.step3"), L10n.t("gcal.step4")].enumerated()),
                    id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 6) {
                    Text("\(index + 1).")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, alignment: .trailing)
                    Text(step)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button {
                NSWorkspace.shared.open(
                    URL(string: "https://console.cloud.google.com/apis/credentials")!)
            } label: {
                Text(L10n.t("gcal.openConsole"))
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.top, 2)
        }
    }

    /// Signing in needs a credential from somewhere: shipped, or typed in.
    private var canSignIn: Bool {
        GoogleOAuth.hasBundledCredentials
            || (!clientID.isEmpty && !clientSecret.isEmpty)
    }

    private func saveCredentialsAndConnect() {
        // Only persist an override when one was actually typed; otherwise the
        // shipped credential is used and nothing is written to the Keychain.
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        if !id.isEmpty && !secret.isEmpty {
            GoogleOAuth.shared.clientID = id
            GoogleOAuth.shared.clientSecret = secret
        }
        connect()
    }

    // MARK: Disconnected

    private var disconnected: some View {
        SettingsSection_Card(title: "macOS Calendar") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Connect to see meetings in Today and get notch alerts before they start.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    connect()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.system(size: 12, weight: .medium))
                        Text(isConnecting ? "Connecting\u{2026}" : "Connect Calendar")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Color(hex: "#111111"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color(hex: "#EEEEEE"))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isConnecting)

                if let error = calendar.lastError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "#E07A5F"))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Uses the calendars already in the macOS Calendar app — including Google accounts you've added in System Settings \u{203A} Internet Accounts. NotchSnap only ever reads them.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Connected (SU-5)

    private var connected: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection_Card(title: "Account") {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: "#8FBF7A"))
                        .frame(width: 8, height: 8)
                    Text(calendar.accountDescription ?? "macOS Calendar")
                        .font(.system(size: 12))
                    Spacer()
                    Text("Connected")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: "#8FBF7A"))
                }
            }

            // The failure that wasted an evening: macOS had silently stopped
            // syncing these accounts in mid-May, so nothing created since then
            // ever reached this Mac — and NotchSnap looked broken while
            // faithfully showing an empty (frozen) database. Say it loudly.
            if calendar.syncLooksStale, let last = calendar.lastSyncedAt {
                SettingsSection_Card(title: "\u{26A0} macOS isn't syncing your calendars") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("The newest event on this Mac is from \(last.formatted(date: .abbreviated, time: .shortened)). Anything created in Google since then hasn't arrived, so NotchSnap can't show it.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "#E07A5F"))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Fix: System Settings \u{203A} Internet Accounts \u{203A} your Google account \u{203A} toggle Calendars off and on. If that doesn't help, remove and re-add the account — Google expires its tokens, and a dead token looks exactly like this.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Internet Accounts") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.systempreferences.InternetAccounts") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .font(.system(size: 11))
                    }
                }
            }

            // "Connected" on its own was misleading — it reported account
            // emails while the calendar holding the actual meeting wasn't
            // synced to this Mac. Listing exactly what NotchSnap can read
            // makes a missing calendar obvious instead of silent.
            SettingsSection_Card(
                title: "Calendars NotchSnap can read",
                subtitle: "Only these are checked for meetings. A calendar missing here isn't synced to this Mac."
            ) {
                let calendars = calendar.visibleCalendars
                if calendars.isEmpty {
                    Text("No calendars found. Add your account in System Settings \u{203A} Internet Accounts and make sure Calendars is enabled for it.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "#E07A5F"))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // Per-calendar opt-out: macOS grants access to the whole
                    // calendar database at once (there's no per-account system
                    // permission), so choosing what NotchSnap uses happens here.
                    ForEach(calendars) { entry in
                        Toggle(isOn: Binding(
                            get: { entry.isEnabled },
                            set: { calendar.setCalendar(entry.id, enabled: $0) }
                        )) {
                            HStack(spacing: 8) {
                                Text(entry.title).font(.system(size: 12))
                                Spacer()
                                Text("\(entry.source) \u{00B7} \(entry.sourceType)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            SettingsSection_Card(
                title: "Today's events",
                subtitle: "What NotchSnap sees right now, and why anything is hidden."
            ) {
                let rows = calendar.diagnoseToday()
                if rows.isEmpty {
                    Text("No events at all in today's calendars.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rows, id: \.self) { row in
                        Text(row)
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(row.hasSuffix("SHOWN") ? Color(hex: "#8FBF7A") : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Divider()
                HStack {
                    Text("Showing \(calendar.upcomingToday.count) upcoming")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh") {
                        Task { await calendar.refresh() }
                    }
                    .font(.system(size: 11))
                }

                // If today looks empty, this answers "is anything syncing at
                // all?" — counts over -7d…+30d per calendar.
                DisclosureGroup("Sync check") {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(probeLines, id: \.self) { line in
                            Text(line)
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Button("Run check") { probeLines = calendar.probeWideWindow() }
                            .font(.system(size: 11))
                            .padding(.top, 4)
                    }
                    .padding(.top, 6)
                }
                .font(.system(size: 11))
            }

            SettingsSection_Card(
                title: "Alert timing",
                subtitle: "How far ahead NotchSnap warns you about a meeting."
            ) {
                leadTimeRow(
                    label: "Ambient dot",
                    help: "A small dot on the notch, no interruption.",
                    value: $calendar.ambientLeadMinutes,
                    range: 5...60, step: 5
                )
                Divider()
                leadTimeRow(
                    label: "Open the notch",
                    help: "The panel opens itself with Join and Snooze.",
                    value: $calendar.alertLeadMinutes,
                    range: 1...15, step: 1
                )
                Divider()
                leadTimeRow(
                    label: "Snooze length",
                    help: "How long Snooze delays the alert.",
                    value: $calendar.snoozeMinutes,
                    range: 1...30, step: 1
                )
            }

            // SU-8
            Button {
                calendar.disconnect()
            } label: {
                Text("Disconnect")
                    .font(.system(size: 11))
                    .underline()
                    .foregroundStyle(Color(hex: "#999999"))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("Disconnecting stops all meeting alerts immediately. To revoke calendar access entirely, use System Settings \u{203A} Privacy & Security \u{203A} Calendars.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func leadTimeRow(label: String, help: String,
                             value: Binding<Int>, range: ClosedRange<Int>,
                             step: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13))
                Text(help).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Stepper(value: value, in: range, step: step) {
                Text("\(value.wrappedValue) min")
                    .font(.system(size: 12))
                    .monospacedDigit()
            }
            .fixedSize()
        }
    }

    private func connect() {
        isConnecting = true
        Task {
            await calendar.connect()
            isConnecting = false
        }
    }
}
