import SwiftUI

// MARK: - CalendarSettingsView — Calendar & Meetings (calendar PRD §2)
//
// SU-1: connection lives in the standard Settings window, not the notch —
// the one deliberate exception to "everything lives in the notch", because
// granting calendar access is a rare, one-time, system-mediated action.
//
// A grouped Form like every other page (SETTINGS_REDESIGN_SPEC, 2026-10-01).
// Access status and the "macOS isn't syncing" warning moved to Permissions;
// this page keeps one line pointing there when something is off. The
// diagnostics (today's events, the wide sync check) are DEBUG-only now.

struct CalendarSettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var calendar = CalendarStore.shared
    @State private var isConnecting = false
    @State private var clientID = ""
    @State private var clientSecret = ""
    #if DEBUG
    @State private var probeLines: [String] = []
    #endif

    var body: some View {
        SettingsPage(section: .calendar) {
            // Only offered when there is more than one usable source; a
            // one-option picker is just noise.
            let sources = CalendarStore.Source.available
            if sources.count > 1 {
                Section {
                    Picker(L10n.t("gcal.source"), selection: Binding(
                        get: { calendar.source },
                        set: { calendar.source = $0 }
                    )) {
                        ForEach(sources) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }

            if SettingsPermissions.needsAttention(calendar) {
                Section {
                    HStack {
                        Label {
                            Text("Something needs attention in Permissions.")
                        } icon: {
                            OttoIcon("exclamationmark.triangle.fill", pointSize: 12)
                        }
                        .foregroundStyle(.orange)
                        Spacer()
                        Button("Open Permissions") { appState.pendingSettingsSection = .permissions }
                    }
                }
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

    // MARK: Disconnected

    @ViewBuilder
    private var disconnected: some View {
        Section {
            SettingRow(title: "macOS Calendar", subtitle: "Meetings in Today, and a heads-up before they start.") {
                Button(isConnecting ? "Connecting\u{2026}" : "Connect Calendar") { connect() }
                    .disabled(isConnecting)
            }
            if let error = calendar.lastError {
                Text(error).foregroundStyle(.orange)
            }
        } header: {
            Text("Account")
        } footer: {
            Text("Uses the calendars already in the Calendar app, including Google accounts added in Internet Accounts. Otto only reads them.")
        }
    }

    // MARK: Google (only when that source is offered)

    @ViewBuilder
    private var googleDisconnected: some View {
        Section {
            if !GoogleOAuth.hasBundledCredentials {
                TextField(L10n.t("gcal.clientID"), text: $clientID)
                SecureField(L10n.t("gcal.clientSecret"), text: $clientSecret)
                Link(L10n.t("gcal.openConsole"),
                     destination: URL(string: "https://console.cloud.google.com/apis/credentials")!)
            }
            SettingRow(title: L10n.t("gcal.title"), subtitle: L10n.t("gcal.subtitle")) {
                Button(isConnecting ? "Connecting\u{2026}" : L10n.t("gcal.signIn")) {
                    saveCredentialsAndConnect()
                }
                .disabled(isConnecting || !canSignIn)
            }
            if let error = calendar.lastError {
                Text(error).foregroundStyle(.orange)
            }
        } header: {
            Text("Account")
        }
        .onAppear {
            if GoogleOAuth.shared.usesCustomCredentials {
                clientID = KeychainStore.get(KeychainStore.Key.clientID) ?? ""
                clientSecret = KeychainStore.get(KeychainStore.Key.clientSecret) ?? ""
            }
        }
    }

    /// Signing in needs a credential from somewhere: shipped, or typed in.
    private var canSignIn: Bool {
        GoogleOAuth.hasBundledCredentials || (!clientID.isEmpty && !clientSecret.isEmpty)
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

    // MARK: Connected (SU-5)

    @ViewBuilder
    private var connected: some View {
        Section {
            SettingRow(title: calendar.accountDescription ?? "macOS Calendar") {
                StatusLabel(text: "Connected", icon: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .fixedSize()
            }
            // Otto re-reads every 10 s; the lag on a meeting booked five
            // minutes out is macOS's download interval for the account.
            SettingRow(title: L10n.t("cal.faster.title"),
                       subtitle: "Calendar \u{203A} Settings \u{203A} Accounts \u{203A} Refresh: Every minute.") {
                Button(L10n.t("cal.faster.open")) {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
                        NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    }
                }
            }
            .help(L10n.t("cal.faster.steps"))
        } header: {
            Text("Account")
        }

        // Per-calendar opt-out: macOS grants the whole calendar database at
        // once, so choosing what Otto uses happens here.
        Section {
            let calendars = calendar.visibleCalendars
            if calendars.isEmpty {
                Text("No calendars found. Add your account in Internet Accounts with Calendars turned on.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(calendars) { entry in
                    SettingRow(title: entry.title, subtitle: "\(entry.source) \u{00B7} \(entry.sourceType)") {
                        RowSwitch(label: entry.title, isOn: Binding(
                            get: { entry.isEnabled },
                            set: { calendar.setCalendar(entry.id, enabled: $0) }
                        ))
                    }
                }
            }
        } header: {
            Text("Calendars")
        } footer: {
            Text("Only these are checked for meetings. One missing here isn't synced to this Mac.")
        }

        Section("Alert timing") {
            leadTimeRow("Ambient dot", "A small dot on the notch, no interruption.",
                        value: $calendar.ambientLeadMinutes, range: 5...60, step: 5)
            leadTimeRow("Open the notch", "The panel opens itself with Join and Snooze.",
                        value: $calendar.alertLeadMinutes, range: 1...15, step: 1)
            leadTimeRow("Snooze length", "How long Snooze delays the alert.",
                        value: $calendar.snoozeMinutes, range: 1...30, step: 1)
        }

        #if DEBUG
        diagnostics
        #endif

        Section {
            HStack {
                Spacer()
                Button("Disconnect", role: .destructive) { calendar.disconnect() }
            }
        } footer: {
            Text("Stops all meeting alerts. To revoke access entirely, use System Settings \u{203A} Privacy & Security \u{203A} Calendars.")
        }
    }

    #if DEBUG
    /// What Otto sees right now and why anything is hidden — development only.
    @ViewBuilder
    private var diagnostics: some View {
        Section {
            let rows = calendar.diagnoseToday()
            if rows.isEmpty {
                Text("No events at all in today's calendars.").foregroundStyle(.secondary)
            } else {
                ForEach(rows, id: \.self) { row in
                    Text(row).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("Showing \(calendar.upcomingToday.count) upcoming").foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") { Task { await calendar.refresh() } }
                Button("Run check") { probeLines = calendar.probeWideWindow() }
            }
            ForEach(probeLines, id: \.self) { line in
                Text(line).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        } header: {
            Text("Today's events (DEBUG)")
        }
    }
    #endif

    private func leadTimeRow(_ label: String, _ help: String,
                             value: Binding<Int>, range: ClosedRange<Int>,
                             step: Int) -> some View {
        SettingRow(title: label, subtitle: help) {
            Stepper(value: value, in: range, step: step) {
                Text("\(value.wrappedValue) min").monospacedDigit()
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
