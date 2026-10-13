import Foundation

// The journal (P116, Oct 12 PM: "a journal/log to reread notes and messages I've received"): every message the game
// shows (toasts: bounties, orders, quests, warnings...) and every document read (orders, letters, intercepted plans)
// is kept with its day and hour, newest first, and opens as a book from the pause menu ("Journal"). Hotbar item names
// and repeats within a few seconds are left out. Kept with the world (Game.saveExtra "journal"), the last 400 entries.
struct JournalEntry: Codable, Equatable {
    var day: Int
    var hour: Int
    var minute: Int
    var text: String
}

enum Journal {
    static let maxEntries = 400
    // Hotbar selection names flash as toasts: not news.
    static let itemNames: Set<String> = Set(Items.defs.map { $0.display })
}

extension Game {
    func logMessage(_ s: String) {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !Journal.itemNames.contains(t) else { return }
        if let last = journal.last, last.text == t, clock - journalLast < 20 { return }
        let f = dayFraction
        let mins = Int(((f * 24 + 6).truncatingRemainder(dividingBy: 24)) * 60)
        journal.append(JournalEntry(day: Int(time / DAY_LENGTH) + 1, hour: mins / 60, minute: mins % 60, text: t))
        journalLast = clock
        if journal.count > Journal.maxEntries { journal.removeFirst(journal.count - Journal.maxEntries) }
    }

    // A document read (BookMenu, not editable): its title and pages, once.
    func logDocument(_ title: String, _ pages: [String]) {
        let body = pages.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let text = "\(title): \(body)"
        guard !journal.contains(where: { $0.text == text }) else { return }
        logMessage(text)
    }

    // The journal as book pages, newest first.
    var journalPages: [String] {
        if journal.isEmpty { return ["Nothing written yet.\n\nMessages and documents you receive are kept here."] }
        var pages: [String] = [], cur = ""
        for e in journal.reversed() {
            let line = String(format: "Day %d, %02d:%02d\n", e.day, e.hour, e.minute) + e.text + "\n\n"
            let cand = cur + line
            if !cur.isEmpty && Books.wrap(cand).count > Books.linesPerPage { pages.append(cur); cur = line } else { cur = cand }
            if pages.count >= Books.maxPages { break }
        }
        if !cur.isEmpty && pages.count < Books.maxPages { pages.append(cur) }
        return pages
    }

    func openJournal() {
        var st = ItemStack(Items.id("written_book"), 1)
        st.label = "Journal"
        st.pages = journalPages
        openMenu(BookMenu(game: self, stack: st, source: .hand(-1)))
    }
}
