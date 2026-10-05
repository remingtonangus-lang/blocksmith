// padbridge: feeds Alabaster from wired Xbox-protocol (GIP) pads that macOS has no driver for, such as the
// PowerA 20D6:2074. Such pads are USB vendor-class devices (not HID), so neither GameController nor SDL sees
// them. This tool opens the pad's GIP interface with IOUSBHost, sends the power-on packet, parses input
// reports and sends "PAD lx ly rx ry lt rt bits" to 127.0.0.1:47731 (Controls.gd's virtual pad).
// Build: clang -O2 -fobjc-arc main.m -o padbridge -framework Foundation -framework IOKit -framework IOUSBHost
// Run:   ./padbridge [vendorHex productHex]   (defaults 20d6 2074; the game starts it on its own on macOS)

#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOUSBHost/IOUSBHost.h>
#include <arpa/inet.h>
#include <sys/socket.h>

static int sock = -1;
static struct sockaddr_in dest;
static double lx, ly, rx, ry, lt, rt;
static int bits;
static BOOL guideDown;

static void say(NSString *s) { fprintf(stderr, "padbridge: %s\n", s.UTF8String); }

static void sendState(void) {
	char buf[160];
	int b = bits | (guideDown ? 1 << 14 : 0);
	int n = snprintf(buf, sizeof buf, "PAD %.4f %.4f %.4f %.4f %.4f %.4f %d", lx, ly, rx, ry, lt, rt, b);
	sendto(sock, buf, n, 0, (struct sockaddr *)&dest, sizeof dest);
}

static int le16(const uint8_t *d, int i) { return d[i] | (d[i + 1] << 8); }
static double s16(const uint8_t *d, int i) { return (int16_t)(uint16_t)le16(d, i) / 32767.0; }

// GIP input report 0x20: buttons at 4-5, triggers (10 bit) at 6 and 8, sticks (signed, y up) at 10..17.
// Returns the length of an acknowledgement written to `ack`, or 0.
static int parse(const uint8_t *d, NSUInteger n, uint8_t *ack) {
	if (n < 4) return 0;
	if (d[0] == 0x20 && n >= 18) {
		uint8_t b0 = d[4], b1 = d[5];
		int b = 0;
		if (b0 & 0x10) b |= 1 << 0;   // A
		if (b0 & 0x20) b |= 1 << 1;   // B
		if (b0 & 0x40) b |= 1 << 2;   // X
		if (b0 & 0x80) b |= 1 << 3;   // Y
		if (b1 & 0x10) b |= 1 << 4;   // LB
		if (b1 & 0x20) b |= 1 << 5;   // RB
		if (b0 & 0x08) b |= 1 << 6;   // View (back)
		if (b0 & 0x04) b |= 1 << 7;   // Menu (start)
		if (b1 & 0x40) b |= 1 << 8;   // LS click
		if (b1 & 0x80) b |= 1 << 9;   // RS click
		if (b1 & 0x01) b |= 1 << 10;  // d-pad up
		if (b1 & 0x02) b |= 1 << 11;  // down
		if (b1 & 0x04) b |= 1 << 12;  // left
		if (b1 & 0x08) b |= 1 << 13;  // right
		bits = b;
		lt = le16(d, 6) / 1023.0;
		rt = le16(d, 8) / 1023.0;
		lx = s16(d, 10); ly = -s16(d, 12);   // Godot: y down is positive
		rx = s16(d, 14); ry = -s16(d, 16);
		sendState();
	} else if (d[0] == 0x07 && n >= 5) {
		guideDown = (d[4] & 0x01) != 0;
		sendState();
		if (d[1] & 0x10) {
			// The pad asks for an acknowledgement of the guide-button report.
			uint8_t a[] = {0x01, 0x20, d[2], 0x09, 0x00, 0x07, 0x20, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00};
			memcpy(ack, a, sizeof a);
			return sizeof a;
		}
	}
	return 0;
}

static IOUSBHostInterface *openInterface(int vid, int pid) {
	CFMutableDictionaryRef match = IOServiceMatching("IOUSBHostInterface");
	NSMutableDictionary *m = (__bridge NSMutableDictionary *)match;
	m[@"idVendor"] = @(vid);
	m[@"idProduct"] = @(pid);
	m[@"bInterfaceNumber"] = @0;
	io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, match);   // consumes `match`
	if (service == IO_OBJECT_NULL) return nil;
	NSError *err = nil;
	IOUSBHostInterface *iface = [[IOUSBHostInterface alloc] initWithIOService:service options:IOUSBHostObjectInitOptionsNone
		queue:nil error:&err interestHandler:nil];
	IOObjectRelease(service);
	if (!iface) say([NSString stringWithFormat:@"found the pad but could not open its interface: %@", err]);
	return iface;
}

static void writePipe(IOUSBHostPipe *pipe, const uint8_t *bytes, NSUInteger n) {
	NSMutableData *data = [NSMutableData dataWithBytes:bytes length:n];
	NSError *err = nil;
	if (![pipe sendIORequestWithData:data bytesTransferred:NULL completionTimeout:1.0 error:&err])
		say([NSString stringWithFormat:@"write failed: %@", err]);
}

int main(int argc, const char *argv[]) {
	@autoreleasepool {
		int vid = argc > 2 ? (int)strtol(argv[1], NULL, 16) : 0x20D6;
		int pid = argc > 2 ? (int)strtol(argv[2], NULL, 16) : 0x2074;
		sock = socket(AF_INET, SOCK_DGRAM, 0);
		memset(&dest, 0, sizeof dest);
		dest.sin_family = AF_INET;
		dest.sin_port = htons(47731);
		dest.sin_addr.s_addr = inet_addr("127.0.0.1");
		say([NSString stringWithFormat:@"looking for %04x:%04x", vid, pid]);
		NSDate *keepAlive = [NSDate date];
		for (;;) {
			@autoreleasepool {
				IOUSBHostInterface *iface = openInterface(vid, pid);
				if (!iface) { [NSThread sleepForTimeInterval:2.0]; continue; }
				IOUSBHostPipe *inPipe = nil, *outPipe = nil;
				for (int a = 1; a <= 4; a++) {
					if (!inPipe) inPipe = [iface copyPipeWithAddress:(0x80 | a) error:nil];
					if (!outPipe) outPipe = [iface copyPipeWithAddress:a error:nil];
				}
				if (!inPipe || !outPipe) {
					say(@"pad interface has no interrupt pipes");
					[iface destroy];
					[NSThread sleepForTimeInterval:2.0];
					continue;
				}
				say(@"pad opened, powering on");
				const uint8_t on[] = {0x05, 0x20, 0x00, 0x01, 0x00};
				const uint8_t start[] = {0x05, 0x20, 0x01, 0x0f, 0x06};
				const uint8_t rumbleInit[] = {0x09, 0x00, 0x02, 0x09, 0x00, 0x0f, 0x00, 0x00, 0x1d, 0x1d, 0xff, 0x00, 0x00};
				const uint8_t rumbleOff[] = {0x09, 0x00, 0x03, 0x09, 0x00, 0x0f, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};
				writePipe(outPipe, on, sizeof on);
				writePipe(outPipe, start, sizeof start);
				writePipe(outPipe, rumbleInit, sizeof rumbleInit);
				writePipe(outPipe, rumbleOff, sizeof rumbleOff);
				NSMutableData *buf = [NSMutableData dataWithLength:64];
				int failures = 0;
				while (failures < 20) {
					@autoreleasepool {
						buf.length = 64;
						NSUInteger n = 0;
						NSError *err = nil;
						if ([inPipe sendIORequestWithData:buf bytesTransferred:&n completionTimeout:0.5 error:&err]) {
							failures = 0;
							uint8_t ack[16];
							int an = parse(buf.bytes, n, ack);
							if (an > 0) writePipe(outPipe, ack, an);
						} else if (err.code != kIOReturnTimeout && err.code != kIOReturnAborted) {
							// Timeouts while the pad is idle are normal; a run of hard errors means it was unplugged.
							failures++;
						}
						if (-[keepAlive timeIntervalSinceNow] > 0.5) {
							sendState();               // the game drops the bridge after 2 s of silence
							keepAlive = [NSDate date];
						}
					}
				}
				say(@"pad lost, waiting for it again");
				[iface destroy];
			}
		}
	}
	return 0;
}
