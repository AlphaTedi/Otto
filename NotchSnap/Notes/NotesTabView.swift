import SwiftUI

// MARK: - NotesTabView — quick notes + Apple Reminders inside the notch
//
// Left: composer (auto-saving draft) with a "Make reminder" toggle and due
// picker — committing with the reminder on creates a real EKReminder in the
// NotchSnap list (syncs with Apple's Reminders app). Right: upcoming
// reminders with complete toggles, then recent notes (click to edit,
// right-click to copy/delete). Permission-denied degrades to a message
// with a System Settings deep link, never a silent failure.

struct NotesTabView: View {
    @ObservedObject private var notes = NotesStore.shared
    @ObservedObject private var reminders = ReminderStore.shared

    @ObservedObject private var appState = AppState.shared
    @State private var makeReminder = false
    @FocusState private var composerFocused: Bool

    private var draftIsEmpty: Bool {
        notes.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        // Notes is notes again — the to-do system lives in its own tab
        // (⌃⇧T), so this layout stays stable and never jumps.
        HStack(alignment: .top, spacing: 12) {
            composer
                .frame(maxWidth: .infinity)
            rightColumn
                .frame(width: 240)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .task {
            if reminders.access == .granted {
                await reminders.refresh()
            }
        }
        .onAppear { consumeFocusRequest() }
        .onChange(of: appState.focusNotesComposer) { _ in consumeFocusRequest() }
    }

    /// ⌃⇧N wants the caret in the composer immediately. Small delay lets
    /// the expand animation land and the panel become key first.
    private func consumeFocusRequest() {
        guard appState.focusNotesComposer else { return }
        appState.focusNotesComposer = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            composerFocused = true
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if notes.draft.isEmpty {
                    Text(L10n.t("notes.placeholder"))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.top, 6)
                        .padding(.leading, 6)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $notes.draft)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .focused($composerFocused)
                    .onChange(of: notes.draft) { _ in notes.draftChanged() }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(composerFocused ? 0.25 : 0.12), lineWidth: 1)
            )
            .frame(maxHeight: .infinity)

            HStack(spacing: 8) {
                // Compact-control scale (macOS HIG): 24pt pills, 11pt labels,
                // shared keycap style — consistent with the filter chips.
                Toggle(isOn: $makeReminder) {
                    NotchControlLabel(
                        icon: "checklist",
                        title: L10n.t("notes.makeReminder"),
                        keys: "\u{2318}R",
                        emphasized: makeReminder
                    )
                }
                .toggleStyle(.button)
                .buttonStyle(.plain)
                .keyboardShortcut("r", modifiers: .command)
                .background(
                    Capsule(style: .continuous)
                        .fill(makeReminder ? Color.accentColor.opacity(0.85) : Color.white.opacity(0.08))
                )
                .onChange(of: makeReminder) { on in
                    if on {
                        Task { _ = await reminders.requestAccess() }
                    }
                }

                Spacer()

                Button(action: commit) {
                    NotchControlLabel(
                        icon: nil,
                        title: L10n.t(makeReminder ? "notes.saveButtonReminder" : "notes.saveButtonNote"),
                        keys: "\u{2318}\u{21A9}",
                        emphasized: !draftIsEmpty
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .background(
                    Capsule(style: .continuous)
                        .fill(draftIsEmpty ? Color.white.opacity(0.08) : Color.green.opacity(0.8))
                )
                .disabled(draftIsEmpty)
            }
            .animation(Motion.swap, value: makeReminder)
        }
    }

    private func commit() {
        let title = notes.draft
            .split(separator: "\n").first.map(String.init) ?? notes.draft
        if makeReminder {
            Task { @MainActor in
                if let id = await reminders.createReminder(title: title, due: nil) {
                    notes.commitDraft(promotedReminderID: id)
                    makeReminder = false
                    HapticManager.shared.copyConfirmed()
                }
            }
        } else {
            notes.commitDraft()
        }
    }

    // MARK: - Right column: reminders + note history

    private var rightColumn: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                if reminders.access == .denied {
                    deniedState
                } else {
                    ForEach(reminders.upcoming) { reminder in
                        ReminderRow(reminder: reminder) {
                            Task { await reminders.toggleComplete(reminder.id) }
                        }
                    }
                }

                if !notes.notes.isEmpty {
                    if !reminders.upcoming.isEmpty || reminders.access == .denied {
                        Divider().opacity(0.3).padding(.vertical, 2)
                    }
                    ForEach(notes.notes) { note in
                        NoteRow(note: note)
                    }
                }

                if notes.notes.isEmpty && reminders.upcoming.isEmpty
                    && reminders.access != .denied {
                    Text(L10n.t("notes.emptyList"))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.top, 8)
                }
            }
        }
    }

    private var deniedState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t("notes.remindersDenied"))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            Button(L10n.t("notes.openSettings")) {
                ReminderStore.openSystemSettings()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.accentColor)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ReminderRow

private struct ReminderRow: View {
    let reminder: UpcomingReminder
    let onToggle: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onToggle) {
                Image(systemName: reminder.isCompleted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundStyle(reminder.isCompleted ? Color.accentColor : .white.opacity(0.5))
            }
            .buttonStyle(.plain)

            Text(reminder.title)
                .font(.system(size: 11))
                .strikethrough(reminder.isCompleted)
                .foregroundStyle(.white.opacity(reminder.isCompleted ? 0.4 : 0.85))
                .lineLimit(1)

            Spacer(minLength: 4)

            if let due = reminder.dueDate {
                Text(Self.dueLabel(due))
                    .font(.system(size: 9))
                    .foregroundStyle(reminder.isOverdue ? Color.red.opacity(0.9) : .white.opacity(0.4))
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(hover ? 0.06 : 0))
        )
        // A highlight, not a state change: the shortest band there is.
        .animation(Motion.hoverFade, value: hover)
        .onHover { hover = $0 }
    }

    static func dueLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        if cal.isDateInToday(date) {
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            return formatter.string(from: date)
        }
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - NoteRow

private struct NoteRow: View {
    let note: QuickNote
    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: note.promotedReminderID != nil ? "bell.fill" : "note.text")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.4))

            Text(note.firstLine)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(L10n.relativeTime(from: note.updatedAt))
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(hover ? 0.06 : 0))
        )
        .contentShape(Rectangle())
        // A highlight, not a state change: the shortest band there is.
        .animation(Motion.hoverFade, value: hover)
        .onHover { hover = $0 }
        .onTapGesture { NotesStore.shared.edit(note.id) }
        .contextMenu {
            Button(L10n.t("action.copy")) {
                ClipboardMonitor.shared.skipNextChange()
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(note.content, forType: .string)
                HapticManager.shared.copyConfirmed()
            }
            Button(L10n.t("action.delete"), role: .destructive) {
                NotesStore.shared.delete(note.id)
            }
        }
    }
}


// MARK: - NotchControlLabel — one compact control anatomy for notch pills
//
// macOS HIG compact-control scale: 24pt tall, 11pt semibold label, 10pt
// keycap chip. Both the reminder toggle and the save button use this, so
// every actionable pill in the notch shares one size and rhythm.

struct NotchControlLabel: View {
    let icon: String?
    let title: String
    let keys: String
    let emphasized: Bool

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 11, weight: .semibold))
            Text(keys)
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.black.opacity(0.25))
                )
        }
        .foregroundStyle(emphasized ? Color.white : Color.white.opacity(0.55))
        .padding(.horizontal, 10)
        .frame(height: 24)
        .contentShape(Capsule())
    }
}
