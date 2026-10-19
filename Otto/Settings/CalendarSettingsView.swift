import SwiftUI

// MARK: - CalendarSettingsView — Calendar & Meetings (calendar PRD §2)
//
// SU-1: connection lives in the standard Settings window, not the notch —
// the one deliberate exception to "everything lives in the notch", because
// granting calendar access is a rare, one-time, system-mediated action.
//
// A grouped Form like every other page (SETTINGS_REDESIGN_SPEC, 2026-10-01).
// Access status lives in Permissions; this page keeps one line pointing
// there when access is refused. The "is macOS still syncing?" hint is here,
// beside the account it is about (2026-10-19). The
// diagnostics (today's events, the wide sync check) are DEBUG-only now.

struct CalendarSettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var calendar = CalendarStore.shared
    @State private var isConnecting = false
    #if DEBUG
    @State private var probeLines: [String] = []
    #endif

    var body: some View {
        SettingsPage(section: .calendar) {
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

        // A hint, not an alarm: nothing new has reached this Mac for three
        // weeks, which is what a Google account whose macOS sync died looks
        // like (it happened on Marcello's Mac in 2026). It may also just be a
        // quiet calendar, so it says what to try, step by step, and nothing is
        // badged anywhere (2026-10-19).
        if calendar.syncLooksStale, let last = calendar.lastSyncedAt {
            Section {
                SettingRow(title: "Missing new meetings?",
                           subtitle: "The newest event on this Mac is from \(last.formatted(date: .abbreviated, time: .omitted)). If you have added meetings since, macOS has stopped syncing that account.") {
                    Link("Open Internet Accounts", destination: SettingsPermissions.internetAccountsURL)
                }
            } header: {
                Text("Calendar sync")
            } footer: {
                Text("1. Open Internet Accounts and choose your Google account.\n2. Turn Calendars off, wait a few seconds, and turn it back on.\n3. Still nothing after a minute? Remove the account and add it again.\nOtto reads whatever the Calendar app has, so once it syncs, meetings appear here on their own.")
            }
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
