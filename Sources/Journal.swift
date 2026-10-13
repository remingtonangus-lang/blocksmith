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
    // A document (P189): its title and every page, kept whole so the journal can show it as it was read.
    var title: String? = nil
    var pages: [String]? = nil
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

    // A document read (BookMenu, not editable): its title and pages, once (a second copy of the same text is not news).
    func logDocument(_ title: String, _ pages: [String]) {
        let body = pages.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        guard !journal.contains(where: { $0.title == title && $0.pages == pages || $0.text == "\(title): \(body)" }) else { return }
        let f = dayFraction
        let mins = Int(((f * 24 + 6).truncatingRemainder(dividingBy: 24)) * 60)
        journal.append(JournalEntry(day: Int(time / DAY_LENGTH) + 1, hour: mins / 60, minute: mins % 60, text: "Read: \(title)", title: title, pages: pages))
        if journal.count > Journal.maxEntries { journal.removeFirst(journal.count - Journal.maxEntries) }
    }

    // The journal as book pages (P189, Oct 13: "a journal that collects everything I read"): a contents page of the
    // documents read (logs, pamphlets, orders, notes), each document whole, page for page as it was read, newest
    // first; then the messages, newest first.
    var journalPages: [String] {
        if journal.isEmpty { return ["Nothing written yet.\n\nMessages and documents you receive are kept here."] }
        var pages: [String] = []
        let docs = journal.reversed().filter { $0.pages != nil }
        if !docs.isEmpty {
            // Contents: where each document starts (page numbers counted from 1, after the contents pages, which
            // are packed by the book's own wrapping; two passes settle how many contents pages there are).
            let shown = Array(docs.prefix(24))
            func contents(_ n: Int) -> [String] {
                var out: [String] = [], cur = "DOCUMENTS READ\n", at = n
                for d in shown {
                    let cand = cur + "\n\(at + 1). \(d.title ?? "Document")"
                    if Books.wrap(cand).count > Books.linesPerPage { out.append(cur); cur = "\(at + 1). \(d.title ?? "Document")" } else { cur = cand }
                    at += d.pages?.count ?? 0
                }
                out.append(cur)
                return out
            }
            var toc = contents(1)
            if toc.count != 1 { toc = contents(toc.count) }
            pages += toc
            for d in shown { for pg in d.pages ?? [] where pages.count < Books.maxPages - 4 { pages.append(pg) } }
        }
        var cur = ""
        for e in journal.reversed() where e.pages == nil {
            let line = String(format: "Day %d, %02d:%02d\n", e.day, e.hour, e.minute) + e.text + "\n\n"
            let cand = cur + line
            if !cur.isEmpty && Books.wrap(cand).count > Books.linesPerPage { pages.append(cur); cur = line } else { cur = cand }
            if pages.count >= Books.maxPages { break }
        }
        if !cur.isEmpty && pages.count < Books.maxPages { pages.append(cur) }
        return pages.isEmpty ? ["Nothing written yet."] : pages
    }

    func openJournal() {
        var st = ItemStack(Items.id("written_book"), 1)
        st.label = "Journal"
        st.pages = journalPages
        openMenu(BookMenu(game: self, stack: st, source: .hand(-1)))
    }
}
