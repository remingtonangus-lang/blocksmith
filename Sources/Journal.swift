import Foundation

// The journal (P116, Oct 12 PM: "a journal/log to reread notes and messages I've received"): every message the game
// shows (toasts: bounties, orders, quests, warnings...) and every document read (orders, letters, intercepted plans)
// is kept with its day and hour. Hotbar item names and repeats within a few seconds are left out. Kept with the world
// (Game.saveExtra "journal"), the last 400 entries (messages go first when it is full; documents stay).
// R24 (Oct 13 evening: "every order, Capital log, note and pamphlet is kept and readable later"): each document is
// filed on a shelf (Orders, Logs, Notes, Pamphlets, Other) with the place it was found, a toast says "Added to journal",
// and the Journal screen (JournalMenu: pause menu > Journal, or the chest pocket in VR) has a tab per shelf, the list,
// and a reading pane that pages long text.
struct JournalEntry: Codable, Equatable {
    var day: Int
    var hour: Int
    var minute: Int
    var text: String
    // A document (P189): its title and every page, kept whole so the journal can show it as it was read.
    var title: String? = nil
    var pages: [String]? = nil
    // R24: the shelf (a Journal.Cat key) and the place it was found. nil in older saves: the shelf is then worked out
    // from the title and the place is left blank. `id` dedupes documents that carry one (contracts).
    var cat: String? = nil
    var place: String? = nil
    var id: String? = nil
}

enum Journal {
    static let maxEntries = 400
    // Hotbar selection names flash as toasts: not news.
    static let itemNames: Set<String> = Set(Items.defs.map { $0.display })
    // The toast a new document gets; a toast carrying it is not itself kept.
    static let tag = "Added to journal: "
    // Bumped on every change, so an open JournalMenu knows to rebuild its list.
    static var rev = 0

    enum Cat: Int, CaseIterable {
        case all, orders, logs, notes, pamphlets, other, messages, events      // events: the Director's (P266)
        var key: String { ["all", "orders", "logs", "notes", "pamphlets", "other", "messages", "events"][rawValue] }
        var tab: String { ["All", "Orders", "Logs", "Notes", "Pamphlets", "Other", "Messages", "Events"][rawValue] }
        static func from(_ k: String) -> Cat? { allCases.first { $0.key == k } }
    }

    // The shelf a document goes on, from its title (callers that know better pass it).
    static func guess(_ title: String) -> Cat {
        let t = title.lowercased()
        if t.contains("order") || t.hasPrefix("contract") || t.contains("dispatch") { return .orders }
        if t.hasSuffix(" log") || t.contains(" log ") || t.contains("logbook") { return .logs }
        if t.contains("pamphlet") || t.contains("poster") || t.contains("notice") || t.contains("handbill") { return .pamphlets }
        if t.contains("note") || t.contains("journal") || t.contains("diary") || t.hasPrefix("repairs") { return .notes }
        return .other
    }
    static func cat(_ e: JournalEntry) -> Cat {
        if e.pages == nil { return .messages }
        if let k = e.cat, let c = Cat.from(k), c != .all { return c }
        return guess(e.title ?? "")
    }
    static func name(_ e: JournalEntry) -> String { e.pages == nil ? e.text : (e.title ?? "Document") }
    static func body(_ e: JournalEntry) -> String { e.pages.map { $0.joined(separator: "\n\n") } ?? e.text }
    // Documents rewritten each time they are opened (the war report, a hull's repair guide): one entry a day, updated.
    static func living(_ title: String) -> Bool { title == "War Report" || title.hasPrefix("Repairs:") }

    // Word-wraps text to a pixel width (Books.wrap, any width).
    static func wrap(_ text: String, width: Int) -> [String] {
        var out: [String] = []
        for para in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = ""
            for word in para.split(separator: " ", omittingEmptySubsequences: false) {
                let w = String(word)
                let cand = line.isEmpty ? w : line + " " + w
                if Font.width(cand) <= width { line = cand; continue }
                if !line.isEmpty { out.append(line) }
                var rest = w
                while Font.width(rest) > width {
                    var cut = rest.count
                    while cut > 1 && Font.width(String(rest.prefix(cut))) > width { cut -= 1 }
                    out.append(String(rest.prefix(cut)))
                    rest = String(rest.dropFirst(cut))
                }
                line = rest
            }
            out.append(line)
        }
        return out
    }
}

extension Game {
    // Day (from 1), hour and minute of the game clock.
    var journalStamp: (Int, Int, Int) {
        let f = dayFraction
        let hours: Double = (f * 24 + 6).truncatingRemainder(dividingBy: 24)
        let mins = Int(hours * 60)
        return (Int(time / DAY_LENGTH) + 1, mins / 60, mins % 60)
    }

    // Where the player stands, for a journal entry: the Capital city or town, else the land and the coordinates.
    func journalPlace() -> String {
        let p = player.pos
        let x = Int(floor(p.x)), z = Int(floor(p.z))
        if dim.dim != .overworld { return dim.dim.displayName }
        if let c = CapitalTown.city(self, x: x, z: z) { return c }
        if let sc = world.gen.structures, let s = sc.nearest("village", x: x, z: z, maxRegions: 1),
           abs(s.anchor.x - x) < 120 && abs(s.anchor.z - z) < 120 {
            return Townsfolk.townName(s.anchor.x, s.anchor.z, seed: world.seed)
        }
        var best: (String, Int)? = nil
        for (n, a) in Countries.state.towns where a.count == 2 {
            let d = max(abs(a[0] - x), abs(a[1] - z))
            if d < 120 && d < (best?.1 ?? Int.max) { best = (n, d) }
        }
        if let b = best { return b.0 }
        return "\(world.gen.column(x, z).biome.displayName), \(x) / \(z)"
    }

    func trimJournal() {
        while journal.count > Journal.maxEntries {
            if let i = journal.firstIndex(where: { $0.pages == nil }) { journal.remove(at: i) } else { journal.removeFirst() }
        }
    }

    func logMessage(_ s: String) {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // The journal's own note is not news; a message it was tacked onto was kept (or left out) when first shown.
        guard !t.contains(Journal.tag) else { return }
        guard !t.isEmpty, !Journal.itemNames.contains(t) else { return }
        if let last = journal.last, last.text == t, clock - journalLast < 20 { return }
        let (d, h, m) = journalStamp
        var e = JournalEntry(day: d, hour: h, minute: m, text: t)
        e.cat = Journal.Cat.messages.key
        journal.append(e)
        journalLast = clock
        trimJournal()
        Journal.rev += 1
    }

    // A document read or received: its title and pages, filed once (a second copy of the same text, or the same id, is
    // not news). Returns true when it is new.
    @discardableResult
    func logDocument(_ title: String, _ pages: [String], cat: Journal.Cat? = nil, id: String? = nil) -> Bool {
        let body = pages.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return false }
        if let id = id, journal.contains(where: { $0.id == id }) { return false }
        guard !journal.contains(where: { $0.title == title && $0.pages == pages || $0.text == "\(title): \(body)" }) else { return false }
        let (d, h, m) = journalStamp
        let place = journalPlace()
        if Journal.living(title), let i = journal.lastIndex(where: { $0.title == title && $0.day == d }) {
            journal[i].pages = pages; journal[i].hour = h; journal[i].minute = m; journal[i].place = place
            Journal.rev += 1
            return false
        }
        var e = JournalEntry(day: d, hour: h, minute: m, text: "Read: \(title)", title: title, pages: pages)
        e.cat = (cat ?? Journal.guess(title)).key
        e.place = place
        e.id = id
        journal.append(e)
        trimJournal()
        Journal.rev += 1
        // R24: "Added to journal: <title>". P207 (Oct 13 18:43, "I couldn't find how to open the journal"): the first
        // time, where to find it too. A message shown a moment ago (the orders' bearing) keeps its place: the note goes
        // after it.
        var note = Journal.tag + title
        // P296 / NO TEXT (Oct 15): no "where to reread it" hint any more; the journal sits in the inventory beside the
        // armour, with a badge when something is new.
        journalTold = true
        let old = toastText
        if clock - toastTime < 1.5, !old.isEmpty, !old.contains(Journal.tag), !Journal.itemNames.contains(old) {
            let end = old.hasSuffix(".") || old.hasSuffix("!") || old.hasSuffix("?")
            onToast?(old + (end ? " " : ". ") + note)
        } else {
            onToast?(note)
        }
        return true
    }

    // The journal as book pages (P189): a contents page of the documents read, each document whole, newest first;
    // then the messages, newest first. (Tests and any book-style export; the Journal screen is JournalMenu.)
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

    func openJournal(tab: Journal.Cat = .all) {
        let m = JournalMenu(game: self)
        m.markNew(from: journalSeen < 0 ? journal.count : journalSeen)     // Q2c-console-29: what is new this time
        journalSeen = journal.count
        if tab != .all { m.tab = tab; m.refresh() }
        openMenu(m)
    }
}

// R24: the Journal screen. Tabs (one per shelf, LB/RB on a pad), the entries newest first on the left (two lines each:
// the title, then day, hour and shelf or place), and the selected entry on a parchment pane on the right, paged
// (LT/RT, or the < > buttons). Every control is a menu button, so the headset's pointer works it like any panel.
final class JournalMenu: Menu, CustomDrawnMenu {
    static let tabY = 16, tabH = 12
    static let listX = 6, listY = 32, listW = 118, rowH = 19, visible = 7
    static let paneX = 130, paneY = 32, paneW = 184, paneH = 136
    static let lineH = 9, textTop = 27
    static let linesPerPage = (paneH - textTop - 3) / lineH
    static let tabBase = 200, scrollUp = 100, scrollDown = 101, prevPage = 110, nextPage = 111, close = 120

    var tab: Journal.Cat = .all
    var newFrom = Int.max                    // Q2c-console-29: entries at or past this index arrived since the last visit
    var scroll = 0
    var selected = 0                         // index into `shown`
    var page = 0
    private(set) var shown: [Int] = []       // journal indices on this shelf, newest first
    private(set) var lines: [String] = []    // the selected entry, wrapped to the pane
    // Cached per rebuild, so a frame only places text.
    private var rowName: [String] = [], rowDetail: [String] = []
    private var header = "", meta = ""
    private var builtRev = -1, builtTab = -1, builtSel = -1
    private var tabX: [Int] = [], tabW: [Int] = []

    init(game: Game) {
        super.init("Journal", game: game)
        width = 320; height = 200
        showInventoryLabel = false
        func button(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ id: Int) {
            let b = MenuSlot(x, y, nil, 0, .button(id)); b.w = w; b.h = h; slots.append(b)
        }
        // The list first, so the pad cursor starts on the newest entry.
        for i in 0..<JournalMenu.visible {
            button(JournalMenu.listX, JournalMenu.listY + JournalMenu.rowH * i, JournalMenu.listW, JournalMenu.rowH - 2, i)
        }
        let cats = Journal.Cat.allCases
        let textW = cats.reduce(0) { $0 + Font.width($1.tab) }
        let room = width - 12 - 2 * (cats.count - 1)
        let pad = max(4, min(10, (room - textW) / cats.count))
        var x = 6
        for c in cats {
            let w = Font.width(c.tab) + pad
            button(x, JournalMenu.tabY, w, JournalMenu.tabH, JournalMenu.tabBase + c.rawValue)
            tabX.append(x); tabW.append(w)
            x += w + 2
        }
        let half = (JournalMenu.listW - 4) / 2
        button(JournalMenu.listX, 168, half, 12, JournalMenu.scrollUp)
        button(JournalMenu.listX + JournalMenu.listW - half, 168, half, 12, JournalMenu.scrollDown)
        button(JournalMenu.paneX, 172, 26, 12, JournalMenu.prevPage)
        button(JournalMenu.paneX + JournalMenu.paneW - 26, 172, 26, 12, JournalMenu.nextPage)
        button(width - 58, 186, 52, 12, JournalMenu.close)
        refresh()
    }

    func markNew(from i: Int) { newFrom = i; builtRev = -1; refresh() }
    var pageCount: Int { max(1, (lines.count + JournalMenu.linesPerPage - 1) / JournalMenu.linesPerPage) }
    var entry: JournalEntry? {
        guard selected >= 0 && selected < shown.count, shown[selected] < game.journal.count else { return nil }
        return game.journal[shown[selected]]
    }

    // Rebuilds the list when the journal or the tab changed, and the reading pane when the selection did.
    func refresh() {
        if builtRev != Journal.rev || builtTab != tab.rawValue {
            let j = game.journal
            let keep: JournalEntry? = builtTab == tab.rawValue ? entry : nil
            shown.removeAll(keepingCapacity: true)
            rowName.removeAll(keepingCapacity: true)
            rowDetail.removeAll(keepingCapacity: true)
            let nameW = JournalMenu.listW - 8
            for i in stride(from: j.count - 1, through: 0, by: -1) {
                let e = j[i]
                guard tab == .all || Journal.cat(e) == tab else { continue }
                shown.append(i)
                rowName.append(ShopMenu.fit(Journal.name(e).replacingOccurrences(of: "\n", with: " "), nameW))
                var d = String(format: "Day %d, %02d:%02d", e.day, e.hour, e.minute)
                if i >= newFrom && e.pages != nil { d = "New - " + d }
                if tab == .all { d += " - " + Journal.cat(e).tab }
                else if let p = e.place { d += " - " + p }
                rowDetail.append(ShopMenu.fit(d, nameW))
            }
            if let k = keep, let at = shown.firstIndex(where: { j[$0] == k }) { selected = at } else { selected = 0; page = 0 }
            if builtTab != tab.rawValue { scroll = 0 }
            builtRev = Journal.rev; builtTab = tab.rawValue; builtSel = -1
        }
        selected = max(0, min(selected, shown.count - 1))
        scroll = max(0, min(scroll, shown.count - JournalMenu.visible))
        if builtSel != selected {
            builtSel = selected
            if let e = entry {
                header = ShopMenu.fit(Journal.name(e).replacingOccurrences(of: "\n", with: " "), JournalMenu.paneW - 12)
                var m = String(format: "Day %d, %02d:%02d", e.day, e.hour, e.minute)
                if let p = e.place { m += " - " + p }
                meta = ShopMenu.fit(m, JournalMenu.paneW - 12)
                lines = Journal.wrap(Journal.body(e), width: JournalMenu.paneW - 12)
            } else {
                header = ""; meta = ""
                lines = tab == .all ? ["Nothing written yet.", "", "Orders, logs, notes, pamphlets", "and messages you receive are", "kept here."]
                                    : ["Nothing on this shelf yet."]
            }
            page = max(0, min(page, pageCount - 1))
        }
        for i in 0..<JournalMenu.visible { slots[i].hidden = scroll + i >= shown.count }
    }

    override func tick() { refresh() }

    override func buttonPressed(_ i: Int) {
        switch i {
        case 0..<JournalMenu.visible:
            let idx = scroll + i
            guard idx < shown.count else { return }
            if idx != selected { selected = idx; page = 0; game.sfx(.pageTurn, 0.5) }
        case JournalMenu.scrollUp: scrollBy(-1)
        case JournalMenu.scrollDown: scrollBy(1)
        case JournalMenu.prevPage: turn(-1)
        case JournalMenu.nextPage: turn(1)
        case JournalMenu.close: game.closeMenu(); return
        case JournalMenu.tabBase..<(JournalMenu.tabBase + Journal.Cat.allCases.count):
            if let c = Journal.Cat(rawValue: i - JournalMenu.tabBase), c != tab { tab = c; game.sfx(.click, 0.4) }
        default: break
        }
        refresh()
    }

    func switchTab(_ d: Int) {
        let n = Journal.Cat.allCases.count
        tab = Journal.Cat(rawValue: (tab.rawValue + d + n) % n) ?? .all
        game.sfx(.click, 0.4)
        refresh()
    }

    func scrollBy(_ d: Int) {
        let s = max(0, min(max(0, shown.count - JournalMenu.visible), scroll + d))
        if s != scroll { scroll = s; game.sfx(.click, 0.3) }
        refresh()
    }

    func turn(_ d: Int) {
        let p = max(0, min(pageCount - 1, page + d))
        if p != page { page = p; game.sfx(.pageTurn, 0.6) }
    }

    func drawLines(_ L: HudLayout, _ o: V2) -> [HudLine] {
        let s = L.s
        var out: [HudLine] = []
        out.reserveCapacity(64)
        let dark = V4(0.12, 0.1, 0.09, 1), mid = V4(0.3, 0.27, 0.23, 1), faint = V4(0.4, 0.38, 0.36, 1)
        let ink = V4(0.1, 0.08, 0.06, 1), rule = V4(0.55, 0.38, 0.22, 1), parchment = V4(0.93, 0.89, 0.78, 1)
        func at(_ x: Int, _ y: Int) -> (Float, Float) { (o.x + Float(x) * s, o.y + Float(y) * s) }
        func box(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: V4) {
            let (px, py) = at(x, y)
            out.append(HudLine(text: "", x: px, y: py, scale: s, bg: c, box: V2(Float(w) * s, Float(h) * s)))
        }
        func label(_ t: String, _ x: Int, _ y: Int, _ c: V4) {
            let (px, py) = at(x, y)
            out.append(HudLine(text: t, x: px, y: py, scale: s, color: c))
        }
        func centred(_ t: String, _ x: Int, _ w: Int, _ y: Int, _ c: V4) { label(t, x + (w - Font.width(t)) / 2, y, c) }
        let hover = game.menuHover
        func button(_ id: Int, _ t: String, _ on: Bool) {
            guard let sl = slots.first(where: { if case .button(let b) = $0.kind { return b == id }; return false }) else { return }
            box(sl.x, sl.y, sl.w, sl.h, hover === sl && on ? V4(0.75, 0.72, 0.66, 1) : V4(0.5, 0.48, 0.45, 1))
            centred(t, sl.x, sl.w, sl.y + (sl.h - 7) / 2, on ? dark : faint)
        }

        // Tabs.
        for c in Journal.Cat.allCases {
            let x = tabX[c.rawValue], w = tabW[c.rawValue]
            let sel = c == tab
            box(x, JournalMenu.tabY, w, JournalMenu.tabH, V4(0.22, 0.2, 0.18, 1))
            box(x + 1, JournalMenu.tabY + 1, w - 2, JournalMenu.tabH - (sel ? 1 : 2), sel ? parchment : V4(0.6, 0.57, 0.52, 1))
            centred(c.tab, x, w, JournalMenu.tabY + 3, sel ? ink : dark)
        }

        // The list.
        let lx = JournalMenu.listX
        for i in 0..<JournalMenu.visible {
            let idx = scroll + i
            guard idx < shown.count else { break }
            let y = JournalMenu.listY + JournalMenu.rowH * i
            let hot = hover === slots[i], sel = idx == selected
            box(lx, y, JournalMenu.listW, JournalMenu.rowH - 2, V4(0.22, 0.2, 0.18, 1))
            let fill = sel ? parchment : (hot ? V4(0.86, 0.82, 0.72, 1) : V4(0.7, 0.67, 0.6, 1))
            box(lx + 1, y + 1, JournalMenu.listW - 2, JournalMenu.rowH - 4, fill)
            label(rowName[idx], lx + 4, y + 2, dark)
            label(rowDetail[idx], lx + 4, y + 10, mid)
        }
        if shown.isEmpty { label("Empty.", lx + 4, JournalMenu.listY + 4, mid) }
        button(JournalMenu.scrollUp, "^", scroll > 0)
        button(JournalMenu.scrollDown, "v", scroll + JournalMenu.visible < shown.count)
        label("\(shown.count) kept", lx, 188, mid)

        // The reading pane.
        let px = JournalMenu.paneX, py = JournalMenu.paneY
        box(px, py, JournalMenu.paneW, JournalMenu.paneH, rule)
        box(px + 1, py + 1, JournalMenu.paneW - 2, JournalMenu.paneH - 2, parchment)
        if !header.isEmpty {
            label(header, px + 6, py + 4, ink)
            label(meta, px + 6, py + 13, V4(0.38, 0.32, 0.26, 1))
            box(px + 6, py + 23, JournalMenu.paneW - 12, 1, rule)
        }
        let first = page * JournalMenu.linesPerPage
        let last = min(lines.count, first + JournalMenu.linesPerPage)
        if first < last {
            for k in first..<last where !lines[k].isEmpty {
                label(lines[k], px + 6, py + JournalMenu.textTop + (k - first) * JournalMenu.lineH, ink)
            }
        }
        button(JournalMenu.prevPage, "<", page > 0)
        button(JournalMenu.nextPage, ">", page + 1 < pageCount)
        centred("Page \(page + 1) of \(pageCount)", px + 26, JournalMenu.paneW - 52, 174, mid)
        button(JournalMenu.close, "Close", true)
        return out
    }

    var legend: String {
        if Prompt.pad { return Prompt.line([(.select, "Read"), (.tabs, "Shelf"), (.scroll, "Scroll"), (.back, "Close")]) + "   LT/RT Page" }
        return Glyph.mouseL.s + " Read   Wheel Scroll   " + Glyphs.key("Esc") + " Close"
    }
}
