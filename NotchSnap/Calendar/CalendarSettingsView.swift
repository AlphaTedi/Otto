import SwiftUI

// MARK: - CalendarSettingsView — the Calendar tab (calendar PRD §2)
//
// SU-1: connection lives in the standard Settings window, not the notch —
// the one deliberate exception to "everything lives in the notch", because
// granting calendar access is a rare, one-time, system-mediated action.
//
// Deviation from SU-2/SU-3/SU-4, agreed with Marcello (2026-07-25): the data
// source is macOS Calendar via EventKit rather than Google OAuth, so there's
// no Google-branded button and no consent sheet — macOS presents its own
// permission prompt instead. The user-visible outcome (see your Google
// meetings in Today, get alerts) is the same, with no Google Cloud project to
// register. The rest of this screen follows the PRD's connected/disconnected
// structure exactly.

struct CalendarSettingsView: View {
    @ObservedObject private var calendar = CalendarStore.shared
    @State private var isConnecting = false
    @State private var probeLines: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle(title: "Calendar",
                      subtitle: "Meetings in Today, and a heads-up before they start.")

            if calendar.isConnected {
                connected
            } else {
                disconnected
            }
        }
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
