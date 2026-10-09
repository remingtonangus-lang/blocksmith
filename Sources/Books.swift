import Foundation
import simd

// Book and Quill (editable pages, signing with a title), Written Books (read-only, copyable:
// original -> copy of original -> copy of copy), and lecterns that hold a book for reading.
enum Books {
    static let pageWidth = 114            // GUI px of text per line
    static let linesPerPage = 14
    static let maxPages = 100
    static let generations = ["Original", "Copy of Original", "Copy of a Copy", "Tattered"]

    // Word-wraps a page into lines that fit the page width.
    static func wrap(_ text: String) -> [String] {
        var out: [String] = []
        for para in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = ""
            for word in para.split(separator: " ", omittingEmptySubsequences: false) {
                let w = String(word)
                let cand = line.isEmpty ? w : line + " " + w
                if Font.width(cand) <= pageWidth { line = cand; continue }
                if !line.isEmpty { out.append(line) }
                // Hard-break words longer than a line.
                var rest = w
                while Font.width(rest) > pageWidth {
                    var cut = rest.count
                    while cut > 1 && Font.width(String(rest.prefix(cut))) > pageWidth { cut -= 1 }
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

final class BookMenu: Menu {
    enum Source { case hand(Int), lectern(BlockEntity) }
    let source: Source
    var pages: [String]
    var page = 0
    let editable: Bool
    var signing = false
    var bookTitle = ""
    init(game: Game, stack: ItemStack, source: Source) {
        self.source = source
        editable = Items.key(stack.item) == "writable_book"
        var pg = stack.pages ?? [""]
        if pg.isEmpty { pg = [""] }
        pages = pg
        super.init(editable ? "Book and Quill" : (stack.label ?? "Written Book"), game: game)
        width = 192; height = 200
        showInventoryLabel = false
        if case .lectern(let be) = source { page = max(0, min(pg.count - 1, Int(be.delay))) }
        func button(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ i: Int) {
            let b = MenuSlot(x, y, nil, 0, .button(i)); b.w = w; b.h = h; slots.append(b)
        }
        button(40, 160, 18, 12, 0)                 // previous page
        button(134, 160, 18, 12, 1)                // next page
        button(98, 180, 60, 16, 2)                 // done
        if editable { button(34, 180, 60, 16, 3) }  // sign
        if case .lectern = source { button(34, 180, 60, 16, 6) }  // take book
    }
    override var capturesText: Bool { editable }
    var lectern: BlockEntity? { if case .lectern(let be) = source { return be } else { return nil } }

    override func buttonPressed(_ i: Int) {
        switch i {
        case 0: if signing { signing = false } else { page = max(0, page - 1) }
        case 1:
            if page < pages.count - 1 { page += 1 }
            else if editable && pages.count < Books.maxPages && !pages[page].isEmpty { pages.append(""); page += 1 }
        case 2:
            if signing { sign() } else { game.closeMenu() }
        case 3: signing = true
        case 6:
            if let be = lectern {
                let s = be.container[0]
                be.container[0] = .empty
                let rest = game.inventory.add(s)
                if !rest.isEmpty { game.dropItem(rest) }
                game.closeMenu()
            }
        default: break
        }
        if let be = lectern {
            let turned = Int(be.delay) != page
            be.delay = Float(page)
            // A turned page pulses copper wire (reference); comparators read the new page on their own.
            if turned, let p = game.world.blockEntities.first(where: { $0.value === be })?.key { game.world.redstone.lecternTurned(p) }
        }
    }
    override func typed(_ s: String) {
        guard editable else { return }
        for c in s {
            if signing {
                if c == "\u{8}" { if !bookTitle.isEmpty { bookTitle.removeLast() } }
                else if bookTitle.count < 32 { bookTitle.append(c) }
                continue
            }
            if c == "\u{8}" { if !pages[page].isEmpty { pages[page].removeLast() } }
            else {
                let cand = pages[page] + String(c)
                if Books.wrap(cand).count <= Books.linesPerPage && cand.count <= 1024 { pages[page] = cand }
            }
        }
    }
    override func tick() {
        guard editable && !signing else {
            if game.input.tapped(Key.arrowLeft) { buttonPressed(0) }
            if game.input.tapped(Key.arrowRight) { buttonPressed(1) }
            return
        }
        if game.input.tapped(Key.enter) {
            let cand = pages[page] + "\n"
            if Books.wrap(cand).count <= Books.linesPerPage { pages[page] = cand }
        }
    }
    func sign() {
        guard !bookTitle.trimmingCharacters(in: .whitespaces).isEmpty, case .hand(let slot) = source else { return }
        var b = ItemStack(Items.id("written_book"), 1)
        b.pages = pages
        b.label = bookTitle
        b.tag = 0
        game.inventory.main[slot] = b
        game.sfx(.pageTurn, 0.7)
        signed = true
        game.closeMenu()
    }
    var signed = false
    override func onClose() {
        guard editable, !signed, case .hand(let slot) = source else { return }
        var s = game.inventory.main[slot]
        guard Items.key(s.item) == "writable_book" else { return }
        while pages.count > 1 && pages.last!.isEmpty { pages.removeLast() }
        s.pages = pages
        game.inventory.main[slot] = s
    }
}

extension Game {
    // Right-click holding a book: open it.
    func useBook() -> Bool {
        let k = Items.key(held.item)
        guard k == "writable_book" || k == "written_book" else { return false }
        openMenu(BookMenu(game: self, stack: held, source: .hand(inventory.selected)))
        return true
    }

    // Lecterns: put a book on (right-click with it), read it (right-click), take it back from the reading screen.
    func useLectern(_ p: IVec3) {
        let be = world.entity(p, .lectern)
        world.blockEntities[p] = be
        if be.container[0].isEmpty {
            let k = Items.key(held.item)
            guard k == "writable_book" || k == "written_book" else { return }
            be.container[0] = held.with(count: 1)
            be.delay = 0
            consumeHeld()
            sfx(.pageTurn, 0.7, at: V3(Float(p.x) + 0.5, Float(p.y) + 1, Float(p.z) + 0.5))
            return
        }
        openMenu(BookMenu(game: self, stack: be.container[0], source: .lectern(be)))
    }

    // The open book lying on each lectern.
    func writeLecternBooks(_ wr: inout EntityWriter, eye: V3) {
        let cover = Int(Tex.id("smoke"))
        for (p, be) in world.blockEntities where be.kind == .lectern && !be.container[0].isEmpty {
            let c = V3(Float(p.x) + 0.5, Float(p.y) + 1.0, Float(p.z) + 0.5) - eye
            guard simd_length(c) < 48 else { continue }
            let l = world.lightAt(p.x, p.y + 1, p.z)
            let light = max(0.2, max(Float(l.sky) / 15 * daylight, Float(l.block) / 15))
            wr.orientedBox(c + V3(-0.2, 0.02, 0), V3(0.18, 0, 0), V3(0, 0.02, 0), V3(0, 0, 0.25), layer: cover, color: V4(V3(0.45, 0.28, 0.16) * light, 1))
            wr.orientedBox(c + V3(0.2, 0.02, 0), V3(0.18, 0, 0), V3(0, 0.02, 0), V3(0, 0, 0.25), layer: cover, color: V4(V3(0.45, 0.28, 0.16) * light, 1))
            wr.orientedBox(c + V3(-0.19, 0.05, 0), V3(0.16, 0, 0), V3(0, 0.015, 0), V3(0, 0, 0.23), layer: cover, color: V4(V3(0.95, 0.92, 0.8) * light, 1))
            wr.orientedBox(c + V3(0.19, 0.05, 0), V3(0.16, 0, 0), V3(0, 0.015, 0), V3(0, 0, 0.23), layer: cover, color: V4(V3(0.95, 0.92, 0.8) * light, 1))
        }
    }
}
