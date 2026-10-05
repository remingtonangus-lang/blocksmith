// padbridge: feeds Alabaster from wired Xbox-protocol (GIP) pads that macOS has no driver for, such as the
// PowerA 20D6:2074. Such pads are USB vendor-class devices (not HID), so neither GameController nor SDL sees
// them. This tool opens the pad's GIP interface with IOUSBHost, sends the power-on packet, parses input
// reports and sends "PAD lx ly rx ry lt rt bits" to 127.0.0.1:47731 (Controls.gd's virtual pad).
// Build: swiftc -O main.swift -o padbridge -framework IOUSBHost
// Run:   ./padbridge [vendorHex productHex]   (defaults 20d6 2074; the game starts it on its own on macOS)

import Foundation
import IOKit
import IOUSBHost

let args = CommandLine.arguments
let vid = args.count > 2 ? Int(args[1], radix: 16) ?? 0x20D6 : 0x20D6
let pid = args.count > 2 ? Int(args[2], radix: 16) ?? 0x2074 : 0x2074

func log(_ s: String) {
	FileHandle.standardError.write(("padbridge: " + s + "\n").data(using: .utf8)!)
}

// ---------------------------------------------------------------------------------------------- UDP out
let sock = socket(AF_INET, SOCK_DGRAM, 0)
var dest = sockaddr_in()
dest.sin_family = sa_family_t(AF_INET)
dest.sin_port = UInt16(47731).bigEndian
dest.sin_addr.s_addr = inet_addr("127.0.0.1")

func send(_ s: String) {
	var d = dest
	_ = s.withCString { p in
		withUnsafePointer(to: &d) { dp in
			dp.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
				sendto(sock, p, strlen(p), 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
			}
		}
	}
}

// ------------------------------------------------------------------------------------------------ state
var lx = 0.0, ly = 0.0, rx = 0.0, ry = 0.0, lt = 0.0, rt = 0.0
var bits = 0
var guide = false

func packet() -> String {
	let b = bits | (guide ? 1 << 14 : 0)
	return String(format: "PAD %.4f %.4f %.4f %.4f %.4f %.4f %d", lx, ly, rx, ry, lt, rt, b)
}

func le16(_ d: [UInt8], _ i: Int) -> Int { Int(d[i]) | (Int(d[i + 1]) << 8) }
func s16(_ d: [UInt8], _ i: Int) -> Double { Double(Int16(bitPattern: UInt16(le16(d, i)))) / 32767.0 }

// GIP input report 0x20: buttons at 4-5, triggers (10 bit) at 6 and 8, sticks (signed, y up) at 10..17.
func parse(_ d: [UInt8]) -> [UInt8]? {
	guard d.count >= 4 else { return nil }
	switch d[0] {
	case 0x20 where d.count >= 18:
		let b0 = d[4], b1 = d[5]
		var b = 0
		if b0 & 0x10 != 0 { b |= 1 << 0 }    // A
		if b0 & 0x20 != 0 { b |= 1 << 1 }    // B
		if b0 & 0x40 != 0 { b |= 1 << 2 }    // X
		if b0 & 0x80 != 0 { b |= 1 << 3 }    // Y
		if b1 & 0x10 != 0 { b |= 1 << 4 }    // LB
		if b1 & 0x20 != 0 { b |= 1 << 5 }    // RB
		if b0 & 0x08 != 0 { b |= 1 << 6 }    // View (back)
		if b0 & 0x04 != 0 { b |= 1 << 7 }    // Menu (start)
		if b1 & 0x40 != 0 { b |= 1 << 8 }    // LS click
		if b1 & 0x80 != 0 { b |= 1 << 9 }    // RS click
		if b1 & 0x01 != 0 { b |= 1 << 10 }   // d-pad up
		if b1 & 0x02 != 0 { b |= 1 << 11 }   // down
		if b1 & 0x04 != 0 { b |= 1 << 12 }   // left
		if b1 & 0x08 != 0 { b |= 1 << 13 }   // right
		bits = b
		lt = Double(le16(d, 6)) / 1023.0
		rt = Double(le16(d, 8)) / 1023.0
		lx = s16(d, 10); ly = -s16(d, 12)    // Godot: y down is positive
		rx = s16(d, 14); ry = -s16(d, 16)
		send(packet())
	case 0x07:
		guide = d[4] & 0x01 != 0
		send(packet())
		if d[1] & 0x10 != 0 {
			// The pad asks for an acknowledgement of the guide-button report.
			return [0x01, 0x20, d[2], 0x09, 0x00, 0x07, 0x20, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00]
		}
	default:
		break
	}
	return nil
}

// ------------------------------------------------------------------------------------------------- USB
func openInterface() -> IOUSBHostInterface? {
	let match = IOUSBHostInterface.createMatchingDictionary(vendorID: NSNumber(value: vid), productID: NSNumber(value: pid),
		bcdDevice: nil, interfaceNumber: NSNumber(value: 0), configurationValue: nil, interfaceClass: nil,
		interfaceSubclass: nil, interfaceProtocol: nil, speed: nil, productIDArray: nil)
	let service = IOServiceGetMatchingService(kIOMainPortDefault, match)
	if service == 0 {
		return nil
	}
	defer { IOObjectRelease(service) }
	do {
		return try IOUSBHostInterface(__ioService: service, options: [], queue: nil, interestHandler: nil)
	} catch {
		log("found the pad but could not open its interface: \(error)")
		return nil
	}
}

func findPipes(_ iface: IOUSBHostInterface) -> (IOUSBHostPipe, IOUSBHostPipe)? {
	var inPipe: IOUSBHostPipe?
	var outPipe: IOUSBHostPipe?
	for a in 1...4 {
		if inPipe == nil, let p = try? iface.copyPipe(withAddress: 0x80 | a) { inPipe = p }
		if outPipe == nil, let p = try? iface.copyPipe(withAddress: a) { outPipe = p }
	}
	if let i = inPipe, let o = outPipe { return (i, o) }
	return nil
}

func write(_ pipe: IOUSBHostPipe, _ bytes: [UInt8]) {
	let data = NSMutableData(bytes: bytes, length: bytes.count)
	do {
		try pipe.sendIORequest(with: data, bytesTransferred: nil, completionTimeout: 1.0)
	} catch {
		log("write failed: \(error)")
	}
}

// kIOReturnTimeout / kIOReturnAborted are function-like macros in C, not imported into Swift.
let ioReturnTimeout = Int(Int32(bitPattern: 0xE00002D6))
let ioReturnAborted = Int(Int32(bitPattern: 0xE00002EB))

log(String(format: "looking for %04x:%04x", vid, pid))
var lastKeepAlive = Date()
while true {
	guard let iface = openInterface() else {
		Thread.sleep(forTimeInterval: 2.0)
		continue
	}
	guard let (inPipe, outPipe) = findPipes(iface) else {
		log("pad interface has no interrupt pipes")
		iface.destroy()
		Thread.sleep(forTimeInterval: 2.0)
		continue
	}
	log("pad opened, powering on")
	write(outPipe, [0x05, 0x20, 0x00, 0x01, 0x00])                                         // power on
	write(outPipe, [0x05, 0x20, 0x01, 0x0f, 0x06])                                         // newer pads: start reports
	write(outPipe, [0x09, 0x00, 0x02, 0x09, 0x00, 0x0f, 0x00, 0x00, 0x1d, 0x1d, 0xff, 0x00, 0x00])  // rumble init
	write(outPipe, [0x09, 0x00, 0x03, 0x09, 0x00, 0x0f, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])  // rumble off
	let buf = NSMutableData(length: 64)!
	var failures = 0
	while failures < 20 {
		var n = 0
		buf.length = 64
		do {
			try inPipe.sendIORequest(with: buf, bytesTransferred: &n, completionTimeout: 0.5)
			failures = 0
			let bytes = [UInt8](Data(bytes: buf.bytes, count: n))
			if let ack = parse(bytes) {
				write(outPipe, ack)
			}
		} catch {
			// Timeouts while the pad is idle are normal; a run of hard errors means it was unplugged.
			let ns = error as NSError
			if ns.code != ioReturnTimeout && ns.code != ioReturnAborted {
				failures += 1
			}
		}
		if Date().timeIntervalSince(lastKeepAlive) > 0.5 {
			send(packet())                                     // the game drops the bridge after 2 s of silence
			lastKeepAlive = Date()
		}
	}
	log("pad lost, waiting for it again")
	iface.destroy()
}
