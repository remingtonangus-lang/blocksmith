import Foundation

// The slice of Apple's Metal API that Blocksmith's shared simulation code touches (World keeps the device so
// MeshArena can carve section meshes out of shared buffers). On the Quest the renderer installs a device whose
// buffers are persistently mapped Vulkan buffers (QuestDevice); HostDevice (plain memory) is the default for tests.

public struct MTLResourceOptions: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let storageModeShared = MTLResourceOptions([])
    public static let storageModeManaged = MTLResourceOptions(rawValue: 1 << 4)
    public static let storageModePrivate = MTLResourceOptions(rawValue: 2 << 4)
    public static let cpuCacheModeWriteCombined = MTLResourceOptions(rawValue: 1)
}

public protocol MTLBuffer: AnyObject {
    func contents() -> UnsafeMutableRawPointer
    var length: Int { get }
    var label: String? { get set }
}

public protocol MTLDevice: AnyObject {
    var name: String { get }
    func makeBuffer(length: Int, options: MTLResourceOptions) -> MTLBuffer?
    func makeBuffer(bytes: UnsafeRawPointer, length: Int, options: MTLResourceOptions) -> MTLBuffer?
}

extension MTLDevice {
    public func makeBuffer(bytes: UnsafeRawPointer, length: Int, options: MTLResourceOptions) -> MTLBuffer? {
        guard let b = makeBuffer(length: length, options: options) else { return nil }
        memcpy(b.contents(), bytes, length)
        return b
    }
}

// Plain host memory (unit tests, tools).
public final class HostBuffer: MTLBuffer {
    public let length: Int
    public var label: String?
    private let mem: UnsafeMutableRawPointer
    public init(length: Int) {
        self.length = length
        mem = UnsafeMutableRawPointer.allocate(byteCount: max(1, length), alignment: 256)
        mem.initializeMemory(as: UInt8.self, repeating: 0, count: max(1, length))
    }
    deinit { mem.deallocate() }
    public func contents() -> UnsafeMutableRawPointer { mem }
}

public final class HostDevice: MTLDevice {
    public init() {}
    public var name: String { "host memory" }
    public func makeBuffer(length: Int, options: MTLResourceOptions) -> MTLBuffer? { HostBuffer(length: length) }
}

// The process-wide device (the Quest renderer replaces it with its Vulkan-backed one before creating worlds).
public var sharedSystemDevice: MTLDevice = HostDevice()
public func MTLCreateSystemDefaultDevice() -> MTLDevice? { sharedSystemDevice }
