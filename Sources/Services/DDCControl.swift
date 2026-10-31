import CoreGraphics
import Darwin
import Foundation
import IOKit

/// Reads and writes an external monitor's brightness over DDC/CI (VCP code
/// 0x10, luminance) on Apple silicon, through the display's AV service.
final class DDCControl: @unchecked Sendable {
    private typealias CreateService = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias WriteI2C = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
    private typealias ReadI2C = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    private static let symbols: (CreateService, WriteI2C, ReadI2C)? = {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
              let create = dlsym(handle, "IOAVServiceCreateWithService"),
              let write = dlsym(handle, "IOAVServiceWriteI2C"),
              let read = dlsym(handle, "IOAVServiceReadI2C") else { return nil }
        return (unsafeBitCast(create, to: CreateService.self),
                unsafeBitCast(write, to: WriteI2C.self),
                unsafeBitCast(read, to: ReadI2C.self))
    }()

    private static let ddcAddress: UInt32 = 0x37
    private static let hostAddress: UInt32 = 0x51
    private static let luminance: UInt8 = 0x10

    private let service: CFTypeRef
    private let queue = DispatchQueue(label: "hal.ddc", qos: .userInitiated)
    private var pending: Double?
    private var writing = false
    /// The monitor's own maximum for the luminance control.
    private(set) var maximum: Int = 100

    private init(service: CFTypeRef) {
        self.service = service
    }

    /// The external AV services the system exposes. Matching one to a display
    /// is only certain when there is exactly one external display and one
    /// service, so other layouts fall back to software dimming.
    static func controls(forExternalDisplays externals: [CGDirectDisplayID]) -> [CGDirectDisplayID: DDCControl] {
        guard let symbols, externals.count == 1 else { return [:] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator) == KERN_SUCCESS else {
            return [:]
        }
        defer { IOObjectRelease(iterator) }
        var services: [CFTypeRef] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            let location = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            guard location == "External", let service = symbols.0(kCFAllocatorDefault, entry)?.takeRetainedValue() else { continue }
            services.append(service)
        }
        guard services.count == 1 else { return [:] }
        return [externals[0]: DDCControl(service: services[0])]
    }

    /// The current brightness as 0...1, or nil when the monitor does not answer.
    func readBrightness() -> Double? {
        guard let symbols = Self.symbols else { return nil }
        var request: [UInt8] = [0x82, 0x01, Self.luminance]
        request.append(Self.checksum(seed: 0x6E ^ UInt8(Self.hostAddress), request))
        for _ in 0..<3 {
            let wrote = request.withUnsafeMutableBytes {
                symbols.1(service, Self.ddcAddress, Self.hostAddress, $0.baseAddress!, UInt32($0.count))
            }
            guard wrote == kIOReturnSuccess else { usleep(20_000); continue }
            usleep(40_000)
            var reply = [UInt8](repeating: 0, count: 12)
            let read = reply.withUnsafeMutableBytes {
                symbols.2(service, Self.ddcAddress, 0, $0.baseAddress!, UInt32($0.count))
            }
            guard read == kIOReturnSuccess, reply[2] == 0x02, reply[3] == 0x00, reply[4] == Self.luminance else {
                usleep(20_000)
                continue
            }
            let maximum = Int(reply[6]) << 8 | Int(reply[7])
            let current = Int(reply[8]) << 8 | Int(reply[9])
            guard maximum > 0 else { continue }
            self.maximum = maximum
            return min(1, max(0, Double(current) / Double(maximum)))
        }
        return nil
    }

    /// Sends the latest requested level; a slider drag only sends what is
    /// current when the previous write finishes.
    func setBrightness(_ level: Double) {
        queue.async { [self] in
            pending = level
            guard !writing else { return }
            writing = true
            while let next = pending {
                pending = nil
                write(next)
            }
            writing = false
        }
    }

    private func write(_ level: Double) {
        guard let symbols = Self.symbols else { return }
        let value = Int((min(1, max(0, level)) * Double(maximum)).rounded())
        var data: [UInt8] = [0x84, 0x03, Self.luminance, UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
        data.append(Self.checksum(seed: 0x6E ^ UInt8(Self.hostAddress), data))
        for _ in 0..<2 {
            let result = data.withUnsafeMutableBytes {
                symbols.1(service, Self.ddcAddress, Self.hostAddress, $0.baseAddress!, UInt32($0.count))
            }
            if result == kIOReturnSuccess { break }
            usleep(20_000)
        }
        usleep(30_000)
    }

    private static func checksum(seed: UInt8, _ bytes: [UInt8]) -> UInt8 {
        bytes.reduce(seed, ^)
    }
}
