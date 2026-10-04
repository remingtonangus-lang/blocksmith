import Foundation
import IOKit
import IOUSBHost

// Userspace fallback driver for wired Xbox One / Series controllers that macOS enumerates but no driver claims
// (vendor-specific class 0xFF, e.g. PowerA / BDA pads such as 20D6:2074), so GameController never sees them.
// Same approach as SDL's Xbox One driver and Linux xpad: open the GIP interface (class 0xFF, subclass 0x47,
// protocol 0xD0), send the power-on / init packets (plus vendor quirks), read input reports from the interrupt IN
// endpoint, acknowledge packets that ask for it, and rumble. PadManager reads `USBGamepads.shared.snapshot()` when no
// GameController pad is present, so the button mapping, Halo-style look settings and prompts all apply.
// The cloud CI has no hardware: the packet parser and builders are checked by --padtest (GIP.selfTest); the device
// path logs every step ("usb-gip: ...") and needs a hardware check on Remington's Mac.

// MARK: GIP packets (pure, testable)

struct GIPState {
    var pad = PadSnapshot()
    var guide = false
    var inputs = 0              // input reports parsed
}

enum GIP {
    // Commands (byte 0 of every packet), options (byte 1).
    static let cmdAck: UInt8 = 0x01, cmdAnnounce: UInt8 = 0x02, cmdStatus: UInt8 = 0x03, cmdPower: UInt8 = 0x05
    static let cmdAuth: UInt8 = 0x06, cmdGuide: UInt8 = 0x07, cmdRumble: UInt8 = 0x09, cmdLED: UInt8 = 0x0A, cmdInput: UInt8 = 0x20
    static let optInternal: UInt8 = 0x20, optNeedsAck: UInt8 = 0x10

    // Vendors that make GIP pads: Microsoft, PowerA (BDA and the older id), PDP, Hori, Razer, Turtle Beach, 8BitDo.
    static let vendors: [Int: String] = [0x045E: "Microsoft", 0x20D6: "PowerA", 0x24C6: "PowerA", 0x0E6F: "PDP", 0x0F0D: "Hori",
                                         0x1532: "Razer", 0x10F5: "Turtle Beach", 0x2DC8: "8BitDo"]
    static func isPowerA(_ vid: Int) -> Bool { vid == 0x20D6 || vid == 0x24C6 }

    // Host -> controller packets. `seq` is the packet sequence number (wraps, never 0 by convention).
    static func powerOn(_ seq: UInt8) -> [UInt8] { [cmdPower, optInternal, seq, 0x01, 0x00] }
    static func sInit(_ seq: UInt8) -> [UInt8] { [cmdPower, optInternal, seq, 0x0F, 0x06] }           // Xbox One S / Series
    static func ledOn(_ seq: UInt8) -> [UInt8] { [cmdLED, optInternal, seq, 0x03, 0x00, 0x01, 0x14] }
    static func pdpAuth(_ seq: UInt8) -> [UInt8] { [cmdAuth, optInternal, seq, 0x02, 0x01, 0x00] }
    // PowerA pads stay silent until a rumble begin / end pair (xpad's xboxone_rumblebegin_init / rumbleend_init).
    static func powerARumbleBegin(_ seq: UInt8) -> [UInt8] { [cmdRumble, 0x00, seq, 0x09, 0x00, 0x0F, 0x00, 0x00, 0x1D, 0x1D, 0xFF, 0x00, 0x00] }
    static func powerARumbleEnd(_ seq: UInt8) -> [UInt8] { [cmdRumble, 0x00, seq, 0x09, 0x00, 0x0F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00] }
    // Rumble: strong (left) and weak (right) motors 0...100, on for `ticks` x 10 ms, once.
    static func rumble(_ seq: UInt8, strong: UInt8, weak: UInt8, ticks: UInt8) -> [UInt8] {
        [cmdRumble, 0x00, seq, 0x09, 0x00, 0x0F, 0x00, 0x00, min(100, strong), min(100, weak), ticks, 0x00, 0x00]
    }
    // Acknowledges a received packet whose options asked for it.
    static func ack(_ seq: UInt8, for cmd: UInt8, length: UInt8) -> [UInt8] {
        [cmdAck, optInternal, seq, 0x09, 0x00, cmd, optInternal, length, 0x00, 0x00, 0x00, 0x00, 0x00]
    }

    // The init sequence for a vendor, with a name for each step (logged).
    static func initSequence(vendor: Int, seq: inout UInt8) -> [(String, [UInt8])] {
        func next() -> UInt8 { seq = seq == 255 ? 1 : seq + 1; return seq }
        var out: [(String, [UInt8])] = [("power on", powerOn(next())), ("S/Series init", sInit(next()))]
        if vendor == 0x0E6F { out.append(("PDP auth", pdpAuth(next()))) }
        if isPowerA(vendor) {
            out.append(("PowerA rumble begin", powerARumbleBegin(next())))
            out.append(("PowerA rumble end", powerARumbleEnd(next())))
        }
        out.append(("LED on", ledOn(next())))
        return out
    }

    @inline(__always) static func u16(_ b: [UInt8], _ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
    @inline(__always) static func s16(_ b: [UInt8], _ i: Int) -> Float {
        let v = Int16(bitPattern: UInt16(b[i]) | UInt16(b[i + 1]) << 8)
        return max(-1, Float(v) / 32767)
    }

    // Parses one packet into the state. Returns an ack to send back, if the packet asked for one.
    @discardableResult
    static func parse(_ b: [UInt8], into st: inout GIPState) -> [UInt8]? {
        guard b.count >= 4 else { return nil }
        let cmd = b[0], opt = b[1], seq = b[2], len = b[3]
        switch cmd {
        case cmdInput where b.count >= 18:
            // Payload from byte 4: buttons (2 bytes), triggers (2 x u16, 0...1023), sticks (4 x s16, y up positive).
            let b4 = b[4], b5 = b[5]
            var p = PadSnapshot()
            p.menu = b4 & 0x04 != 0; p.view = b4 & 0x08 != 0
            p.a = b4 & 0x10 != 0; p.b = b4 & 0x20 != 0; p.x = b4 & 0x40 != 0; p.y = b4 & 0x80 != 0
            p.up = b5 & 0x01 != 0; p.down = b5 & 0x02 != 0; p.left = b5 & 0x04 != 0; p.right = b5 & 0x08 != 0
            p.lb = b5 & 0x10 != 0; p.rb = b5 & 0x20 != 0; p.l3 = b5 & 0x40 != 0; p.r3 = b5 & 0x80 != 0
            p.lt = min(1, Float(u16(b, 6)) / 1023)
            p.rt = min(1, Float(u16(b, 8)) / 1023)
            p.lx = s16(b, 10); p.ly = s16(b, 12)
            p.rx = s16(b, 14); p.ry = s16(b, 16)
            p.share = st.pad.share
            st.pad = p
            st.inputs += 1
        case cmdGuide where b.count >= 5:
            st.guide = b[4] & 0x01 != 0
        default:
            break
        }
        return opt & optNeedsAck != 0 ? ack(seq, for: cmd, length: len) : nil
    }

    // Parser self-test against known packet layouts (run by --padtest).
    static func selfTest(_ check: (Bool, String) -> Void) {
        var st = GIPState()
        // Input: A + Menu, D-pad up + LB + R3, LT full, RT half, LX full left, LY full up, RX 0, RY a quarter down.
        let pkt: [UInt8] = [0x20, 0x00, 0x05, 0x0E, 0x14, 0x91, 0xFF, 0x03, 0x00, 0x02, 0x00, 0x80, 0xFF, 0x7F, 0x00, 0x00, 0x00, 0xE0]
        let ack = parse(pkt, into: &st)
        let p = st.pad
        check(ack == nil && st.inputs == 1, "gip: an input report parses without an ack")
        check(p.a && p.menu && !p.b && !p.x && !p.y && !p.view, "gip: face buttons and Menu from byte 4")
        check(p.up && p.lb && p.r3 && !p.down && !p.rb && !p.l3, "gip: D-pad, bumpers, stick clicks from byte 5")
        check(abs(p.lt - 1) < 0.001 && abs(p.rt - 512 / 1023) < 0.001, "gip: triggers 10-bit (LT \(p.lt), RT \(p.rt))")
        check(p.lx == -1 && abs(p.ly - 1) < 0.001 && p.rx == 0 && abs(p.ry + 0.25) < 0.01, "gip: sticks signed 16-bit, y up (\(p.lx), \(p.ly), \(p.ry))")
        // Guide button packet that asks for an ack.
        let g: [UInt8] = [0x07, 0x30, 0x09, 0x02, 0x01, 0x5B]
        let a = parse(g, into: &st)
        check(st.guide && a == [0x01, 0x20, 0x09, 0x09, 0x00, 0x07, 0x20, 0x02, 0, 0, 0, 0, 0], "gip: guide press read and acknowledged")
        // Short / unknown packets are ignored.
        let before = st.inputs
        parse([0x20, 0x00, 0x06], into: &st)
        parse([0x03, 0x20, 0x07, 0x04, 0x80, 0x00, 0x00, 0x00], into: &st)
        check(st.inputs == before && st.pad.a, "gip: short and status packets leave the pad state alone")
        // Init: power-on first, PowerA quirk present for 0x20D6, absent for Microsoft.
        var seq: UInt8 = 0
        let powerA = initSequence(vendor: 0x20D6, seq: &seq)
        check(powerA.first?.1 == [0x05, 0x20, 0x01, 0x01, 0x00], "gip: init starts with power-on (seq 1)")
        check(powerA.contains { $0.0 == "PowerA rumble begin" } && powerA.count == 5, "gip: PowerA init adds the rumble begin/end quirk")
        var seq2: UInt8 = 0
        check(initSequence(vendor: 0x045E, seq: &seq2).count == 3, "gip: Microsoft pads get power-on, S init and LED")
        let r = rumble(3, strong: 200, weak: 40, ticks: 25)
        check(r.count == 13 && r[0] == 0x09 && r[8] == 100 && r[9] == 40 && r[10] == 25, "gip: rumble packet layout (motors capped at 100)")
    }
}

// MARK: Device driver (IOUSBHost)

final class USBGamepads {
    static let shared = USBGamepads()
    // IOKit's function-like macros (iokit_common_msg / iokit_common_err) don't reach Swift.
    static let msgTerminated: UInt32 = 0xE000_0010          // kIOMessageServiceIsTerminated
    static let errAborted = Int32(bitPattern: 0xE000_02EB)  // USBGamepads.errAborted
    static let errNoDevice = Int32(bitPattern: 0xE000_02C0) // USBGamepads.errNoDevice

    private let queue = DispatchQueue(label: "blocksmith.usb-gip")
    private let lock = NSLock()
    private var state = GIPState()
    private var live = false
    private(set) var deviceName = ""
    private var opened = Set<UInt64>()          // registry entry ids of devices we hold
    private var device: IOUSBHostDevice?
    private var iface: IOUSBHostInterface?
    private var pipeIn: IOUSBHostPipe?
    private var pipeOut: IOUSBHostPipe?
    private var vendor = 0
    private var seq: UInt8 = 0
    private var timer: DispatchSourceTimer?
    var onConnect: ((String) -> Void)?
    var onDisconnect: ((String) -> Void)?

    var active: Bool { lock.lock(); defer { lock.unlock() }; return live }

    func snapshot() -> PadSnapshot? {
        lock.lock(); defer { lock.unlock() }
        return live ? state.pad : nil
    }

    private func log(_ s: String) { print("usb-gip: " + s) }

    // Starts hotplug polling (every 2 s; cheap registry lookups) when no GameController pad covers the device.
    func start() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.5, repeating: 2.0)
        t.setEventHandler { [weak self] in self?.scan() }
        timer = t
        t.resume()
        log("watching for wired Xbox (GIP) controllers: " + GIP.vendors.keys.sorted().map { String(format: "%04x", $0) }.joined(separator: ", "))
    }

    private func prop(_ s: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(s, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
    private func intProp(_ s: io_registry_entry_t, _ key: String) -> Int? { (prop(s, key) as? NSNumber)?.intValue }

    private func scan() {
        if device != nil { return }                // one pad at a time
        for vid in GIP.vendors.keys {
            guard let cf = IOServiceMatching("IOUSBHostDevice") else { continue }
            let match = cf as NSMutableDictionary
            match["idVendor"] = vid
            var it: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, match as CFDictionary, &it) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(it) }
            var s = IOIteratorNext(it)
            while s != 0 {
                defer { IOObjectRelease(s) }
                var rid: UInt64 = 0
                IORegistryEntryGetRegistryEntryID(s, &rid)
                if !opened.contains(rid), tryOpen(s, vid: vid) { opened.insert(rid); return }
                s = IOIteratorNext(it)
            }
        }
    }

    // The GIP interface (0xFF / 0x47 / 0xD0) under a device, if its configuration is set.
    private func gipInterface(under dev: io_service_t) -> io_service_t? {
        var it: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(dev, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &it) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(it) }
        var e = IOIteratorNext(it)
        while e != 0 {
            if IOObjectConformsTo(e, "IOUSBHostInterface") != 0, intProp(e, "bInterfaceClass") == 0xFF,
               intProp(e, "bInterfaceSubClass") == 0x47, intProp(e, "bInterfaceProtocol") == 0xD0 {
                return e                            // caller releases
            }
            IOObjectRelease(e)
            e = IOIteratorNext(it)
        }
        return nil
    }

    private func tryOpen(_ s: io_service_t, vid: Int) -> Bool {
        let pid = intProp(s, "idProduct") ?? 0
        let cls = intProp(s, "bDeviceClass") ?? -1
        let name = (prop(s, "USB Product Name") as? String) ?? (prop(s, "kUSBProductString") as? String) ?? "Xbox controller"
        let tag = String(format: "%@ %04x:%04x", name, vid, pid)
        // Pads that macOS drives itself (GameController sees them) are left alone.
        if PadManager.shared.hasSystemPad { return false }
        log("found \(tag) (device class 0x\(String(cls, radix: 16)))")
        do {
            let dev = try IOUSBHostDevice(__ioService: s, options: [], queue: queue, interestHandler: { [weak self] _, type, _ in
                if type == USBGamepads.msgTerminated { self?.queue.async { self?.close(reason: "unplugged") } }
            })
            log("step: device opened")
            var ifs = gipInterface(under: s)
            if ifs == nil {
                // No driver set a configuration (vendor class): set configuration 1 so the interfaces appear.
                do { try dev.configure(withValue: 1, matchInterfaces: true); log("step: configuration 1 set") }
                catch { log("step: configure failed: \(error.localizedDescription)") }
                for _ in 0..<20 where ifs == nil { usleep(50_000); ifs = gipInterface(under: s) }
            }
            guard let ifService = ifs else {
                log("no GIP interface (class ff/47/d0) on \(tag); not an Xbox One/Series pad")
                dev.destroy()
                return true                          // don't retry this device every scan
            }
            defer { IOObjectRelease(ifService) }
            let i = try IOUSBHostInterface(__ioService: ifService, options: [], queue: queue, interestHandler: nil)
            log("step: GIP interface opened")
            var pin: IOUSBHostPipe?, pout: IOUSBHostPipe?
            for a in [0x81, 0x82, 0x83, 0x84] where pin == nil { pin = try? i.copyPipe(withAddress: a); if pin != nil { log(String(format: "step: input endpoint 0x%02x", a)) } }
            for a in [0x01, 0x02, 0x03, 0x04] where pout == nil { pout = try? i.copyPipe(withAddress: a); if pout != nil { log(String(format: "step: output endpoint 0x%02x", a)) } }
            guard let inP = pin, let outP = pout else {
                log("missing interrupt endpoints on \(tag)")
                i.destroy(); dev.destroy()
                return true
            }
            device = dev; iface = i; pipeIn = inP; pipeOut = outP; vendor = vid; deviceName = name
            for (what, pkt) in GIP.initSequence(vendor: vid, seq: &seq) {
                let ok = send(pkt)
                log("step: init \(what) [\(pkt.map { String(format: "%02x", $0) }.joined(separator: " "))] \(ok ? "sent" : "FAILED")")
            }
            for _ in 0..<4 { readNext() }
            lock.lock(); live = true; state = GIPState(); lock.unlock()
            log("opened \(tag)")
            DispatchQueue.main.async { [weak self] in self?.onConnect?(name) }
            return true
        } catch {
            log("could not open \(tag): \(error.localizedDescription)")
            return true
        }
    }

    @discardableResult
    private func send(_ bytes: [UInt8]) -> Bool {
        guard let p = pipeOut else { return false }
        let d = NSMutableData(bytes: bytes, length: bytes.count)
        do { try p.sendIORequest(with: d, bytesTransferred: nil, completionTimeout: 1); return true } catch { return false }
    }

    private func readNext() {
        guard let p = pipeIn else { return }
        let buf = NSMutableData(length: 64)!
        do {
            try p.enqueueIORequest(with: buf, completionTimeout: 0) { [weak self] status, n in
                guard let self else { return }
                if status != kIOReturnSuccess {
                    if status != USBGamepads.errAborted { self.log(String(format: "read failed 0x%08x", status)) }
                    if self.pipeIn != nil && status != USBGamepads.errAborted && status != USBGamepads.errNoDevice { self.queue.asyncAfter(deadline: .now() + 0.05) { self.readNext() } }
                    return
                }
                let bytes = [UInt8](Data(bytes: buf.bytes, count: n))
                self.lock.lock()
                let ack = GIP.parse(bytes, into: &self.state)
                let first = self.state.inputs == 1 && bytes.first == GIP.cmdInput
                self.lock.unlock()
                if first { self.log("first input report (\(n) bytes)") }
                if bytes.first == GIP.cmdAnnounce {
                    self.log("controller announced itself: sending init again")
                    for (_, pkt) in GIP.initSequence(vendor: self.vendor, seq: &self.seq) { self.send(pkt) }
                }
                if let a = ack { self.send(a) }
                self.readNext()
            }
        } catch {
            log("could not queue a read: \(error.localizedDescription)")
        }
    }

    // Rumble for `duration` seconds at 0...1 (both motors; the strong one leads).
    func rumble(_ strength: Float, _ duration: Float) {
        queue.async { [weak self] in
            guard let self, self.pipeOut != nil else { return }
            self.seq = self.seq == 255 ? 1 : self.seq + 1
            let s = UInt8(max(0, min(100, strength * 100))), w = UInt8(max(0, min(100, strength * 70)))
            self.send(GIP.rumble(self.seq, strong: s, weak: w, ticks: UInt8(max(1, min(255, duration * 100)))))
        }
    }

    private func close(reason: String) {
        guard device != nil else { return }
        let name = deviceName
        try? pipeIn?.abort()
        iface?.destroy(); device?.destroy()
        pipeIn = nil; pipeOut = nil; iface = nil; device = nil
        opened.removeAll()                           // a replug gets a new registry id; allow it again
        lock.lock(); live = false; state = GIPState(); lock.unlock()
        log("closed \(name) (\(reason))")
        DispatchQueue.main.async { [weak self] in self?.onDisconnect?(name) }
    }
}
