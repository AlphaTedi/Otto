import Foundation

// MARK: - App-wide notification names
//
// Every Notification.Name Otto posts, in one place. All are in-process
// (NotificationCenter) except `ottoShowRequest`, which crosses processes.

extension Notification.Name {
    /// A second Otto asking the running one to show itself (distributed).
    static let ottoShowRequest = Notification.Name("otto.show")
    static let openSettingsRequest = Notification.Name("otto.openSettings")
    static let settingsWindowClosed = Notification.Name("otto.settingsClosed")
    /// Posted whenever the global quick-entry hotkey actually fires. Onboarding
    /// listens for this so its practice step advances on the REAL keypress
    /// rather than a "Next" button — the user performs the app's core action
    /// for real before onboarding ends.
    static let quickEntryFired = Notification.Name("otto.quickEntryFired")
    /// Posted when a to-do is actually committed. Onboarding uses it to know
    /// the user finished the job, not just opened the panel.
    static let todoCreated = Notification.Name("otto.todoCreated")
    /// Posted by the key router when Escape lands while a row's title or
    /// step editor holds the caret. The editors listen and DISCARD their
    /// draft — the router must consume Esc itself (letting it through would
    /// close the notch), so "Escape means cancel" has to travel this way.
    static let todoEditorEscape = Notification.Name("otto.todoEditorEscape")
    /// Keyboard commands for the meeting's task list (MeetingNotes).
    static let meetingTaskCommand = Notification.Name("otto.meeting.task.command")
}
