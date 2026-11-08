import Foundation

// MARK: - Demo mode: plausible data for recording videos (2026-11-03)
//
// On, Otto reads and writes a folder of its own (`Otto Demo` beside the real
// one) and its Markdown mirror goes there too, so nothing it shows or records
// touches the real to-dos and notes. The first launch fills that folder with
// the sections, to-dos and notes below; after that they behave like any data,
// and deleting the folder starts them over.
//
// Debug and Otto Lab only: a switch in Settings › Appearance, applied on the
// next launch (the data folder is chosen once, before any store opens).

enum DemoMode {
    static let key = "demoMode"

    nonisolated static var isAvailable: Bool {
        #if DEBUG
        return true
        #else
        return AppBuild.isLab
        #endif
    }

    nonisolated static var isOn: Bool { isAvailable && UserDefaults.standard.bool(forKey: key) }
}

/// The seeded content. Dates are relative to the first launch, so the due
/// chips always read as this week and next.
enum DemoData {
    static func todos(now: Date = Date()) -> (collections: [TodoCollection], items: [TodoItem]) {
        let calendar = Calendar.current
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) ?? now
        }

        var collections = [
            TodoCollection(id: UUID(), name: "Today", colorHex: "#E8C15A",
                           sortOrder: 0, shortcutKey: "1", isSystemToday: true),
        ]
        var items: [TodoItem] = []

        /// A to-do: a title, an optional due day (its chip goes at the end of
        /// the title, as the input writes it), steps, done or not.
        struct Seed {
            var title: String
            var due: Int? = nil
            var steps: [(String, Bool)] = []
            var done = false
        }

        func section(_ name: String, tint: String, _ seeds: [Seed]) {
            let hex = DockTint.swatches[tint].map { String(format: "#%06X", $0) } ?? "#9EE0B0"
            let collection = TodoCollection(id: UUID(), name: name, colorHex: hex,
                                            sortOrder: collections.count,
                                            shortcutKey: collections.count < 9 ? String(collections.count + 1) : nil,
                                            tint: tint)
            collections.append(collection)
            for (index, seed) in seeds.enumerated() {
                let due = seed.due.map(day)
                let title = due.map { seed.title + " " + NLDateParser.token(for: $0) } ?? seed.title
                items.append(TodoItem(
                    id: UUID(), title: title, collectionID: collection.id,
                    isCompleted: seed.done,
                    completedAt: seed.done ? now.addingTimeInterval(-Double(index + 1) * 2400) : nil,
                    dueDate: due, sortOrder: index,
                    createdAt: now.addingTimeInterval(-Double(seeds.count - index) * 86_400),
                    checklist: seed.steps.map { ChecklistItem(id: UUID(), title: $0.0, isDone: $0.1) }))
            }
        }

        section("Work", tint: "work", [
            Seed(title: "Send the Q4 roadmap to the design team", due: 1),
            Seed(title: "Prepare the launch review", due: 3, steps: [
                ("Collect the beta feedback", true),
                ("Draft the pricing slide", false),
                ("Book the meeting room", false),
            ]),
            Seed(title: "Reply to Sofia about the onboarding copy"),
            Seed(title: "Review the analytics dashboard before standup"),
            Seed(title: "Write the release notes for 2.4", due: 6),
            Seed(title: "Update the hiring scorecard"),
            Seed(title: "Share the meeting notes with the team", done: true),
            Seed(title: "Fix the typo on the pricing page", done: true),
        ])
        section("Personal", tint: "personal", [
            Seed(title: "Call mum for her birthday", due: 2),
            Seed(title: "Book the dentist"),
            Seed(title: "Renew the passport", steps: [
                ("Take new photos", true),
                ("Fill in the form online", false),
            ]),
            Seed(title: "Pick up the dry cleaning"),
            Seed(title: "Plan Saturday's dinner with friends", due: 4),
            Seed(title: "Pay the electricity bill", done: true),
        ])
        section("Groceries", tint: "grocery", [
            Seed(title: "Oat milk"),
            Seed(title: "Sourdough bread"),
            Seed(title: "Avocados ×3"),
            Seed(title: "Greek yoghurt"),
            Seed(title: "Coffee beans"),
            Seed(title: "Basil and cherry tomatoes"),
            Seed(title: "Parmesan", done: true),
        ])
        section("Home", tint: "coral", [
            Seed(title: "Fix the bathroom tap", steps: [
                ("Buy a new washer", false),
                ("Watch the repair video", true),
            ]),
            Seed(title: "Order the new desk lamp"),
            Seed(title: "Water the plants", due: 0),
            Seed(title: "Take the recycling out", due: 1),
        ])
        section("Travel", tint: "teal", [
            Seed(title: "Book the flights to Lisbon", due: 5),
            Seed(title: "Find a hotel near Alfama"),
            Seed(title: "Check the train times to Sintra"),
            Seed(title: "Buy a travel adapter"),
        ])
        section("Side project", tint: "violet", [
            Seed(title: "Sketch the landing page"),
            Seed(title: "Record the demo video", due: 2),
            Seed(title: "Write to five beta testers"),
        ])
        return (collections, items)
    }

    static func notes(now: Date = Date()) -> [QuickNote] {
        func note(_ title: String, _ content: String, hoursAgo: Double) -> QuickNote {
            let date = now.addingTimeInterval(-hoursAgo * 3600)
            return QuickNote(content: content, createdAt: date, updatedAt: date,
                             title: title, titleSource: .user)
        }
        return [
            note("Launch review", """
                Launch review
                Beta feedback is mostly about onboarding: people want to start typing straight away.
                - Shorten the first screen
                - Move the shortcuts to tooltips
                - Ship the pricing page before the announcement
                """, hoursAgo: 2),
            note("Lisbon trip", """
                Lisbon trip
                Four days, mid-December. Alfama for the evenings, Sintra on the second day.
                Restaurants to try: Taberna da Rua das Flores, Cervejaria Ramiro.
                """, hoursAgo: 20),
            note("Ideas for the newsletter", """
                Ideas for the newsletter
                A short story about how the notch became a to-do list.
                Three tips for capturing tasks without leaving what you are doing.
                """, hoursAgo: 46),
            note("Book notes: Deep Work", """
                Book notes: Deep Work
                Schedule every minute of the day, then protect the blocks.
                Shallow work expands to fill the time it is given.
                """, hoursAgo: 96),
            note("Gift ideas", """
                Gift ideas
                Mum: a ceramics class. Luca: the new climbing guide. Anna: a good pen.
                """, hoursAgo: 150),
        ]
    }
}
