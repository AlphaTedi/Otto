import Foundation

// MARK: - L10n — lightweight in-app localization
//
// Default: follow the Mac's system language (like the theme follows the
// system appearance). The user can override in Settings → General.
// Kept as simple dictionaries — no .lproj plumbing — so adding a language
// is one table.

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case italian = "it"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system:  return L10n.t("lang.system")
        case .english: return "English"
        case .italian: return "Italiano"
        }
    }
}

enum L10n {
    static let storageKey = "appLanguage"

    /// Effective 2-letter code: user override, else the system language.
    static var languageCode: String {
        let pref = UserDefaults.standard.string(forKey: storageKey) ?? "system"
        if pref != "system" { return pref }
        let sys = Locale.preferredLanguages.first ?? "en"
        return String(sys.prefix(2))
    }

    static var locale: Locale { Locale(identifier: languageCode) }

    static func t(_ key: String) -> String {
        if languageCode == "it", let s = it[key] { return s }
        return en[key] ?? key
    }

    /// System-style relative timestamp ("2 min ago" / "2 min fa") in the
    /// effective language.
    static func relativeTime(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return t("time.now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Tables

    private static let en: [String: String] = [
        "lang.system": "System default",
        "time.now": "now",
        // Filters
        "filter.all": "All",
        "filter.tray": "Tray",
        "filter.shots": "Shots",
        "filter.snippets": "Snippets",
        "filter.links": "Links",
        "filter.text": "Text",
        "tray.clear": "Clear",
        "menu.clearTray": "Clear Tray",
        "menu.clearShots": "Remove All Screenshots",
        "menu.clearHistory": "Clear Clipboard History",
        // Notch
        "notch.empty": "No content yet.\nTake a screenshot, copy something, or drop a file.",
        "tray.empty": "Drop files here, drag them out anywhere",
        "tile.quickCopy": "Quick Copy",
        "tile.copied": "\u{2713} Copied",
        // Actions
        "action.copy": "Copy",
        "action.pin": "Pin",
        "action.unpin": "Unpin",
        "action.delete": "Delete",
        "action.remove": "Remove",
        "action.edit": "Edit\u{2026}",
        "action.moveLeft": "Move Left",
        "action.moveRight": "Move Right",
        "action.save": "Save\u{2026}",
        // Snippets
        "snippet.new": "New Snippet",
        "snippet.editTitle": "Edit Snippet",
        "snippet.newTitle": "New Snippet",
        "snippet.labelPlaceholder": "Label (e.g. Email sign-off)",
        "snippet.create": "Create",
        "snippet.saveButton": "Save",
        "snippet.cancel": "Cancel",
        // Notes
        "filter.notes": "Notes",
        "filter.todos": "To-dos",
        "notes.placeholder": "Jot something down\u{2026}",
        "notes.makeReminder": "Make reminder",
        "notes.saveNote": "Save note (\u{2318}\u{21A9})",
        "notes.saveReminder": "Create reminder (\u{2318}\u{21A9})",
        "notes.saveButtonNote": "Save",
        "notes.saveButtonReminder": "Remind",
        "notes.emptyList": "Notes and reminders you add appear here.",
        "notes.remindersDenied": "Reminders access is off. Allow it in System Settings to sync with Apple Reminders.",
        "notes.openSettings": "Open System Settings",
        // To-dos
        "urgency.low": "Low",
        "urgency.medium": "Medium",
        "urgency.high": "High",
        "urgency.low.full": "Low priority",
        "urgency.medium.full": "Medium priority",
        "urgency.high.full": "High priority",
        "todo.completed": "Completed",
        "todo.empty": "Nothing here yet.",
        "todo.emptyToday": "Nothing due today.",
        "todo.newTodo": "New to-do",
        "todo.titlePlaceholder": "What needs doing?",
        "todo.create": "Create",
        "todo.noCollection": "No collection",
        "todo.newCollection": "New collection",
        "todo.collectionName": "Collection name",
        "todo.moveTo": "Move to\u{2026}",
        "todo.searchCollections": "Search collections\u{2026}",
        "todo.shortcuts": "Keyboard shortcuts",
        "todo.sc.quickEntry": "Quick entry (from anywhere)",
        "todo.sc.newTodo": "New to-do (in app)",
        "todo.sc.switchCollection": "Switch collection",
        "todo.sc.moveFocus": "Move between to-dos",
        "todo.sc.reorder": "Reorder within the list",
        "todo.sc.shortcuts": "Show this reference",
        "todo.sc.expandRow": "Show / hide details",
        "todo.sc.quickFind": "Quick Find (just type)",
        "todo.sc.closeHint": "press ? again to close",
        "cal.with": "with",
        "cal.join": "Join",
        "cal.joinHelp": "Open the video call",
        "cal.guests": "%d guests",
        "cal.snooze": "Snooze %dm",
        "cal.startingIn": "Starting in %d min",
        // Short form for the meeting card's top-right countdown ("in 34 min").
        "cal.inMinutes": "in %d min",
        "cal.inHours": "in %dh %dm",
        "cal.now": "now",
        "cal.startingNow": "Starting now",
        "cal.untitled": "(No title)",
        "cal.nudgeTitle": "See today's meetings here",
        "cal.nudgeSubtitle": "Connect your calendar in Settings",
        "cal.err.denied": "Calendar access was denied. Allow it in System Settings \u{203A} Privacy & Security \u{203A} Calendars.",
        "integrity.translocated": "macOS is running NotchSnap from a temporary read-only copy, so it cannot ask for calendar access. Move NotchSnap to your Applications folder, then open it from there.",
        "integrity.quarantined": "macOS has NotchSnap quarantined as a downloaded app, so it cannot ask for calendar access. Move it to Applications, then right-click it \u{203A} Open once to clear the quarantine.",
        "cal.err.noCalendars": "No calendars found. Add your account in System Settings \u{203A} Internet Accounts, then try again.",
        "voice.start": "Voice brain-dump",
        "voice.stop": "Stop and review",
        "voice.listeningHint": "Speak your to-dos\u{2026}",
        "voice.onDeviceCaption": "Listening \u{00B7} on-device, nothing leaves your Mac",
        "voice.parsing": "Sorting that into to-dos\u{2026}",
        "voice.engine.ai": "Apple Intelligence, on-device",
        "voice.engine.rules": "On-device, no network",
        "voice.foundOne": "%d to-do found \u{2014} review before adding",
        "voice.foundMany": "%d to-dos found \u{2014} review before adding",
        "voice.addNone": "Nothing to add",
        "voice.addOne": "Add it",
        "voice.addBoth": "Add both",
        "voice.addAll": "Add all %d",
        "voice.unavailable": "Voice capture unavailable",
        "voice.useTyping": "Type it instead",
        "voice.err.permission": "NotchSnap needs microphone and speech recognition access. Enable them in System Settings \u{203A} Privacy & Security.",
        "voice.err.onDevice": "On-device speech recognition isn't available for your language on this Mac. NotchSnap won't send your voice to a server, so voice capture stays off.",
        "voice.err.recognizer": "Speech recognition isn't available right now.",
        "voice.err.noInput": "No microphone input was found.",
        "todo.setDefault": "Default for new to-dos",
        "todo.manageCategories": "Categories",
        "todo.categoryName": "Name",
        "todo.categoryColor": "Color",
        "todo.matches": "Matches",
        "todo.noMatches": "No matches.",
        "todo.inCategory": "in",
        "todo.notePlaceholder": "Add a note\u{2026}",
        "todo.addStep": "Add a step\u{2026}",
        "date.today": "Today",
        "date.tomorrow": "Tomorrow",
        "todo.sc.toggleComplete": "Complete / uncomplete",
        "todo.sc.moveItem": "Move to another collection",
        "todo.sc.cycleCollection": "Cycle collection (creating)",
        "todo.sc.cycleUrgency": "Cycle urgency (creating)",
        "todo.sc.create": "Create the to-do",
        "todo.sc.cancel": "Cancel / close",
        // Settings
        "settings.language": "Language",
        "settings.language.subtitle": "Follows your Mac's language by default.",
    ]

    private static let it: [String: String] = [
        "lang.system": "Predefinita di sistema",
        "time.now": "ora",
        "filter.all": "Tutti",
        "filter.tray": "Vassoio",
        "filter.shots": "Scatti",
        "filter.snippets": "Snippet",
        "filter.links": "Link",
        "filter.text": "Testo",
        "tray.clear": "Svuota",
        "menu.clearTray": "Svuota il vassoio",
        "menu.clearShots": "Rimuovi tutti gli screenshot",
        "menu.clearHistory": "Svuota cronologia appunti",
        "notch.empty": "Ancora niente qui.\nFai uno screenshot, copia qualcosa o trascina un file.",
        "tray.empty": "Trascina i file qui, portali fuori dove vuoi",
        "tile.quickCopy": "Copia rapida",
        "tile.copied": "\u{2713} Copiato",
        "action.copy": "Copia",
        "action.pin": "Fissa",
        "action.unpin": "Sblocca",
        "action.delete": "Elimina",
        "action.remove": "Rimuovi",
        "action.edit": "Modifica\u{2026}",
        "action.moveLeft": "Sposta a sinistra",
        "action.moveRight": "Sposta a destra",
        "action.save": "Salva\u{2026}",
        "snippet.new": "Nuovo snippet",
        "snippet.editTitle": "Modifica snippet",
        "snippet.newTitle": "Nuovo snippet",
        "snippet.labelPlaceholder": "Etichetta (es. Firma email)",
        "snippet.create": "Crea",
        "snippet.saveButton": "Salva",
        "snippet.cancel": "Annulla",
        "filter.notes": "Note",
        "filter.todos": "To-do",
        "notes.placeholder": "Scrivi qualcosa\u{2026}",
        "notes.makeReminder": "Crea promemoria",
        "notes.saveNote": "Salva nota (\u{2318}\u{21A9})",
        "notes.saveReminder": "Crea promemoria (\u{2318}\u{21A9})",
        "notes.saveButtonNote": "Salva",
        "notes.saveButtonReminder": "Ricorda",
        "notes.emptyList": "Le note e i promemoria che aggiungi appaiono qui.",
        "notes.remindersDenied": "L'accesso ai Promemoria \u{00E8} disattivato. Consentilo nelle Impostazioni di Sistema per sincronizzare con Promemoria.",
        "notes.openSettings": "Apri Impostazioni di Sistema",
        "urgency.low": "Bassa",
        "urgency.medium": "Media",
        "urgency.high": "Alta",
        "urgency.low.full": "Priorit\u{00E0} bassa",
        "urgency.medium.full": "Priorit\u{00E0} media",
        "urgency.high.full": "Priorit\u{00E0} alta",
        "todo.completed": "Completati",
        "todo.empty": "Ancora niente.",
        "todo.emptyToday": "Niente in scadenza oggi.",
        "todo.newTodo": "Nuovo to-do",
        "todo.titlePlaceholder": "Cosa c'\u{00E8} da fare?",
        "todo.create": "Crea",
        "todo.noCollection": "Nessuna raccolta",
        "todo.newCollection": "Nuova raccolta",
        "todo.collectionName": "Nome della raccolta",
        "todo.moveTo": "Sposta in\u{2026}",
        "todo.searchCollections": "Cerca raccolte\u{2026}",
        "todo.shortcuts": "Scorciatoie da tastiera",
        "todo.sc.quickEntry": "Inserimento rapido (ovunque)",
        "todo.sc.newTodo": "Nuovo to-do (nell'app)",
        "todo.sc.switchCollection": "Cambia raccolta",
        "todo.sc.moveFocus": "Naviga tra i to-do",
        "todo.sc.reorder": "Riordina nella lista",
        "todo.sc.shortcuts": "Mostra questa guida",
        "todo.sc.expandRow": "Mostra/nascondi dettagli",
        "todo.sc.quickFind": "Ricerca rapida (digita)",
        "todo.sc.closeHint": "premi ? per chiudere",
        "cal.with": "con",
        "cal.join": "Partecipa",
        "integrity.translocated": "macOS sta eseguendo NotchSnap da una copia temporanea in sola lettura, quindi non pu\u{00F2} chiedere l'accesso al calendario. Sposta NotchSnap nella cartella Applicazioni e aprilo da l\u{00EC}.",
        "integrity.quarantined": "macOS tiene NotchSnap in quarantena come app scaricata, quindi non pu\u{00F2} chiedere l'accesso al calendario. Spostalo in Applicazioni, poi fai clic destro \u{203A} Apri una volta per togliere la quarantena.",
        "cal.inMinutes": "tra %d min",
        "cal.inHours": "tra %dh %dm",
        "cal.now": "ora",
        "cal.joinHelp": "Apri la videochiamata",
        "cal.guests": "%d partecipanti",
        "cal.snooze": "Rimanda %dm",
        "cal.startingIn": "Inizia tra %d min",
        "cal.startingNow": "Sta iniziando",
        "cal.untitled": "(Senza titolo)",
        "cal.nudgeTitle": "Vedi qui le riunioni di oggi",
        "cal.nudgeSubtitle": "Collega il calendario nelle Impostazioni",
        "cal.err.denied": "Accesso al calendario negato. Consentilo in Impostazioni di Sistema \u{203A} Privacy e sicurezza \u{203A} Calendari.",
        "cal.err.noCalendars": "Nessun calendario trovato. Aggiungi il tuo account in Impostazioni di Sistema \u{203A} Account Internet, poi riprova.",
        "voice.start": "Dettatura rapida",
        "voice.stop": "Ferma e rivedi",
        "voice.listeningHint": "Detta i tuoi to-do\u{2026}",
        "voice.onDeviceCaption": "In ascolto \u{00B7} sul dispositivo, nulla lascia il tuo Mac",
        "voice.parsing": "Trasformo in to-do\u{2026}",
        "voice.engine.ai": "Apple Intelligence, sul dispositivo",
        "voice.engine.rules": "Sul dispositivo, nessuna rete",
        "voice.foundOne": "%d to-do trovato \u{2014} rivedi prima di aggiungere",
        "voice.foundMany": "%d to-do trovati \u{2014} rivedi prima di aggiungere",
        "voice.addNone": "Niente da aggiungere",
        "voice.addOne": "Aggiungi",
        "voice.addBoth": "Aggiungi entrambi",
        "voice.addAll": "Aggiungi tutti e %d",
        "voice.unavailable": "Dettatura non disponibile",
        "voice.useTyping": "Scrivilo invece",
        "voice.err.permission": "NotchSnap ha bisogno di accesso a microfono e riconoscimento vocale. Attivali in Impostazioni di Sistema \u{203A} Privacy e sicurezza.",
        "voice.err.onDevice": "Il riconoscimento vocale sul dispositivo non \u{00E8} disponibile per la tua lingua su questo Mac. NotchSnap non invia la tua voce a un server, quindi la dettatura resta disattivata.",
        "voice.err.recognizer": "Il riconoscimento vocale non \u{00E8} disponibile ora.",
        "voice.err.noInput": "Nessun ingresso microfono trovato.",
        "todo.setDefault": "Predefinita per nuovi to-do",
        "todo.manageCategories": "Categorie",
        "todo.categoryName": "Nome",
        "todo.categoryColor": "Colore",
        "todo.matches": "Risultati",
        "todo.noMatches": "Nessun risultato.",
        "todo.inCategory": "in",
        "todo.notePlaceholder": "Aggiungi una nota\u{2026}",
        "todo.addStep": "Aggiungi un passaggio\u{2026}",
        "date.today": "Oggi",
        "date.tomorrow": "Domani",
        "todo.sc.toggleComplete": "Completa / annulla",
        "todo.sc.moveItem": "Sposta in un'altra raccolta",
        "todo.sc.cycleCollection": "Cambia raccolta (creazione)",
        "todo.sc.cycleUrgency": "Cambia urgenza (creazione)",
        "todo.sc.create": "Crea il to-do",
        "todo.sc.cancel": "Annulla / chiudi",
        "settings.language": "Language",
        "settings.language.subtitle": "Segue la lingua del Mac per impostazione predefinita.",
    ]
}
