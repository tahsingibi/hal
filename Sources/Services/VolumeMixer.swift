import AppKit
import CoreAudio
import Foundation
import os

struct MixerApp: Identifiable, Equatable {
    var id: String
    var name: String
    var iconPath: String?
    var playing: Bool
    var volume: Double
    var muted: Bool
}

struct MixerDevice: Identifiable, Equatable {
    var id: AudioDeviceID
    var name: String
}

/// Çıkış sesi ve uygulama başına seviye.
///
/// 100% ve sessiz değilken uygulamanın kendi sesi olduğu gibi gider.
/// Seviye değişince macOS 14.2 süreç tap’i o uygulamanın çıkışını susturur
/// ve Hâl aynı sesi seçilen kazançla yeniden çalar. Kayıt tutulmaz.
@MainActor
final class VolumeMixer: ObservableObject {
    static let shared = VolumeMixer()

    @Published private(set) var apps: [MixerApp] = []
    @Published private(set) var outputName = ""
    @Published private(set) var outputs: [MixerDevice] = []
    @Published private(set) var inputs: [MixerDevice] = []
    @Published var outputVolume: Double = 1
    @Published var outputMuted = false
    @Published var outputID: AudioDeviceID = 0
    @Published var systemOutputID: AudioDeviceID = 0
    @Published var inputID: AudioDeviceID = 0
    @Published var inputVolume: Double = 1
    @Published var inputMuted = false
    @Published var note: String?

    private var taps: [String: AppTap] = [:]
    private var liveIDs: [String: [AudioObjectID]] = [:]
    private var routedOutput: AudioDeviceID = 0
    private var ticker: Timer?
    private var watchers = 0
    private var watching: Bool { watchers > 0 }
    private let gainKey = "hal.mixer.gains"
    private let muteKey = "hal.mixer.muted"

    private init() {}

    func restore() {
        guard needsEngine else { return }
        ensureTicker()
        tick()
    }

    func shutdown() {
        ticker?.invalidate()
        ticker = nil
        for tap in taps.values { tap.destroy() }
        taps.removeAll()
    }

    func setWatching(_ on: Bool) {
        if on {
            watchers += 1
        } else {
            watchers = max(0, watchers - 1)
        }
        if watchers > 0 {
            ensureTicker()
            tick()
        } else if !needsEngine {
            ticker?.invalidate()
            ticker = nil
        }
    }

    func setOutputVolume(_ value: Double) {
        let clamped = min(1, max(0, value))
        outputVolume = clamped
        AudioDevices.setVolume(Float(clamped))
    }

    func setOutputMuted(_ muted: Bool) {
        outputMuted = muted
        AudioDevices.setMuted(muted)
    }

    func setOutputDevice(_ id: AudioDeviceID) {
        AudioDevices.setDefault(kAudioHardwarePropertyDefaultOutputDevice, id)
        outputID = id
        tick()
    }

    func setSystemOutputDevice(_ id: AudioDeviceID) {
        AudioDevices.setDefault(kAudioHardwarePropertyDefaultSystemOutputDevice, id)
        systemOutputID = id
    }

    func setInputDevice(_ id: AudioDeviceID) {
        AudioDevices.setDefault(kAudioHardwarePropertyDefaultInputDevice, id)
        inputID = id
        tick()
    }

    func setInputVolume(_ value: Double) {
        let clamped = min(1, max(0, value))
        inputVolume = clamped
        AudioDevices.writeScalar(inputID, scope: kAudioDevicePropertyScopeInput, Float(clamped))
    }

    func setInputMuted(_ muted: Bool) {
        inputMuted = muted
        AudioDevices.writeMuted(inputID, scope: kAudioDevicePropertyScopeInput, muted)
    }

    func setVolume(id: String, _ value: Double) {
        let clamped = min(1.5, max(0, value))
        var gains = storedGains()
        let muted = storedMutes()
        if abs(clamped - 1) < 0.01 && !muted.contains(id) {
            gains.removeValue(forKey: id)
        } else {
            gains[id] = clamped
        }
        save(gains: gains, muted: muted)
        updateRow(id: id, volume: clamped, muted: muted.contains(id))
        rebind()
        if needsEngine { ensureTicker() }
    }

    func setMuted(id: String, _ muted: Bool) {
        var gains = storedGains()
        var mutes = storedMutes()
        if muted {
            mutes.insert(id)
        } else {
            mutes.remove(id)
            if abs((gains[id] ?? 1) - 1) < 0.01 { gains.removeValue(forKey: id) }
        }
        save(gains: gains, muted: mutes)
        updateRow(id: id, volume: gains[id] ?? 1, muted: muted)
        rebind()
        if needsEngine { ensureTicker() }
    }

    func openCaptureSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AudioCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
        ]
        for raw in urls {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
    }

    private var needsEngine: Bool {
        !storedGains().isEmpty || !storedMutes().isEmpty
    }

    private func ensureTicker() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        let snapshot = AudioDevices.apps(gains: storedGains(), muted: storedMutes())
        liveIDs = snapshot.ids
        if watching || needsEngine {
            apps = snapshot.rows
            let output = AudioDevices.output()
            outputName = output.name
            outputVolume = Double(output.volume)
            outputMuted = output.muted
            outputs = AudioDevices.endpoints(scope: kAudioDevicePropertyScopeOutput)
            inputs = AudioDevices.endpoints(scope: kAudioDevicePropertyScopeInput)
            outputID = AudioDevices.defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
            systemOutputID = AudioDevices.defaultDevice(kAudioHardwarePropertyDefaultSystemOutputDevice)
            inputID = AudioDevices.defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
            if let level = AudioDevices.scalarVolume(of: inputID, scope: kAudioDevicePropertyScopeInput) {
                inputVolume = Double(level)
            }
            inputMuted = AudioDevices.isMuted(inputID, scope: kAudioDevicePropertyScopeInput)
        }
        rebind()
    }

    private func updateRow(id: String, volume: Double, muted: Bool) {
        guard let index = apps.firstIndex(where: { $0.id == id }) else {
            tick()
            return
        }
        apps[index].volume = volume
        apps[index].muted = muted
    }

    private func rebind() {
        let output = AudioDevices.defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        if output != routedOutput {
            for tap in taps.values { tap.destroy() }
            taps.removeAll()
            routedOutput = output
        }
        let gains = storedGains()
        let mutes = storedMutes()
        var wanted: Set<String> = []
        var failure: String?
        for (id, objectIDs) in liveIDs {
            let volume = gains[id] ?? 1
            let muted = mutes.contains(id)
            let adjust = muted || abs(volume - 1) > 0.01
            guard adjust, !objectIDs.isEmpty else { continue }
            wanted.insert(id)
            let tap = taps[id] ?? AppTap()
            let gain = muted ? Float(0) : Float(volume)
            if let error = tap.sync(ids: objectIDs, gain: gain) {
                failure = error
                tap.destroy()
            }
            taps[id] = tap
        }
        for id in taps.keys where !wanted.contains(id) {
            taps[id]?.destroy()
            taps[id] = nil
        }
        note = failure.map { code in
            Lf(
                "Uygulama sesi ayrılamadı (%1$@). Sistem Ayarları’nda Hâl için sistem sesi kaydına izin ver.",
                "Could not separate app audio (%1$@). Allow system audio recording for Hâl in System Settings.",
                code
            )
        }
    }

    private func storedGains() -> [String: Double] {
        let raw = UserDefaults.standard.dictionary(forKey: gainKey) ?? [:]
        var out: [String: Double] = [:]
        for (key, value) in raw {
            if let number = value as? NSNumber { out[key] = number.doubleValue }
        }
        return out
    }

    private func storedMutes() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: muteKey) ?? [])
    }

    private func save(gains: [String: Double], muted: Set<String>) {
        UserDefaults.standard.set(gains, forKey: gainKey)
        UserDefaults.standard.set(Array(muted), forKey: muteKey)
    }
}

private enum AudioDevices {
    struct Output {
        var name: String
        var volume: Float
        var muted: Bool
    }

    static func output() -> Output {
        let device = defaultOutput()
        return Output(
            name: string(device, kAudioObjectPropertyName) ?? L("Çıkış", "Output"),
            volume: volume(of: device) ?? 1,
            muted: muted(of: device)
        )
    }

    static func setVolume(_ value: Float) {
        let device = defaultOutput()
        guard device != 0 else { return }
        writeScalar(device, scope: kAudioDevicePropertyScopeOutput, value)
    }

    static func endpoints(scope: AudioObjectPropertyScope) -> [MixerDevice] {
        devices().compactMap { id in
            guard streamCount(id, scope: scope) > 0 else { return nil }
            let name = string(id, kAudioObjectPropertyName) ?? ""
            guard !name.isEmpty, name != "Hal Mixer" else { return nil }
            return MixerDevice(id: id, name: name)
        }
    }

    static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioDeviceID {
        var device: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }

    static func setDefault(_ selector: AudioObjectPropertySelector, _ id: AudioDeviceID) {
        var device = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &device)
    }

    static func scalarVolume(of device: AudioDeviceID, scope: AudioObjectPropertyScope) -> Float? {
        guard var address = volumeAddress(device, scope: scope) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func writeScalar(_ device: AudioDeviceID, scope: AudioObjectPropertyScope, _ value: Float) {
        guard device != 0, var address = volumeAddress(device, scope: scope) else { return }
        var sample = Float32(value)
        let size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(device, &address, 0, nil, size, &sample)
    }

    static func isMuted(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        guard var address = muteAddress(device, scope: scope) else { return false }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    static func writeMuted(_ device: AudioDeviceID, scope: AudioObjectPropertyScope, _ on: Bool) {
        guard device != 0, var address = muteAddress(device, scope: scope) else { return }
        var value: UInt32 = on ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
    }

    static func setMuted(_ on: Bool) {
        writeMuted(defaultOutput(), scope: kAudioDevicePropertyScopeOutput, on)
    }

    static func apps(gains: [String: Double], muted: Set<String>) -> (rows: [MixerApp], ids: [String: [AudioObjectID]]) {
        let mine = ProcessInfo.processInfo.processIdentifier
        struct Bucket {
            var name: String
            var iconPath: String?
            var aliases: Set<String> = []
            var objectIDs: [AudioObjectID] = []
            var playing = false
        }
        var buckets: [String: Bucket] = [:]
        for object in processObjectIDs() {
            guard let pid = pid(of: object), pid != mine, pid > 0 else { continue }
            let rawBundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
                ?? string(object, kAudioProcessPropertyBundleID)
            let resolved = AppIdentity.resolve(pid: pid, bundleIdentifier: rawBundle)
            var bucket = buckets[resolved.id] ?? Bucket(
                name: resolved.name ?? AppIdentity.prettify(rawBundle ?? "") ?? "\(pid)",
                iconPath: resolved.iconPath
            )
            if bucket.iconPath == nil { bucket.iconPath = resolved.iconPath }
            if let rawBundle { bucket.aliases.insert(rawBundle) }
            bucket.aliases.insert(resolved.id)
            if uint32(object, kAudioProcessPropertyIsRunningOutput) == 1 {
                bucket.objectIDs.append(object)
                bucket.playing = true
            }
            buckets[resolved.id] = bucket
        }

        var consumed = Set(buckets.keys)
        for bucket in buckets.values { consumed.formUnion(bucket.aliases) }

        func storedVolume(_ id: String, aliases: Set<String>) -> Double {
            if let value = gains[id] { return value }
            for alias in aliases {
                if let value = gains[alias] { return value }
            }
            return 1
        }
        func storedMuted(_ id: String, aliases: Set<String>) -> Bool {
            if muted.contains(id) { return true }
            return aliases.contains { muted.contains($0) }
        }
        func remembered(_ id: String, aliases: Set<String>) -> Bool {
            if gains[id] != nil || muted.contains(id) { return true }
            return aliases.contains { gains[$0] != nil || muted.contains($0) }
        }

        var rows: [MixerApp] = []
        var ids: [String: [AudioObjectID]] = [:]
        for (id, bucket) in buckets {
            guard bucket.playing || remembered(id, aliases: bucket.aliases) else { continue }
            rows.append(MixerApp(
                id: id,
                name: bucket.name,
                iconPath: bucket.iconPath,
                playing: bucket.playing,
                volume: storedVolume(id, aliases: bucket.aliases),
                muted: storedMuted(id, aliases: bucket.aliases)
            ))
            if bucket.playing { ids[id] = bucket.objectIDs }
        }

        let leftovers = Set(gains.keys).union(muted).subtracting(consumed)
        for key in leftovers {
            let resolved = AppIdentity.resolve(bundleIdentifier: key)
            if rows.contains(where: { $0.id == resolved.id }) { continue }
            rows.append(MixerApp(
                id: resolved.id,
                name: resolved.name ?? AppIdentity.prettify(key) ?? key,
                iconPath: resolved.iconPath,
                playing: false,
                volume: gains[key] ?? gains[resolved.id] ?? 1,
                muted: muted.contains(key) || muted.contains(resolved.id)
            ))
        }

        rows.sort { lhs, rhs in
            if lhs.playing != rhs.playing { return lhs.playing && !rhs.playing }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return (rows, ids)
    }

    private static func processObjectIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }
        var values = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &values) == noErr else { return [] }
        return values
    }

    private static func defaultOutput() -> AudioDeviceID {
        var device: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }

    private static func devices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }
        var values = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &values) == noErr else { return values }
        return values
    }

    private static func streamCount(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }

    private static func volume(of device: AudioDeviceID) -> Float? {
        scalarVolume(of: device, scope: kAudioDevicePropertyScopeOutput)
    }

    private static func volumeAddress(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress? {
        for element: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1, 2] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: scope,
                mElement: element
            )
            if AudioObjectHasProperty(device, &address) { return address }
        }
        return nil
    }

    private static func muted(of device: AudioDeviceID) -> Bool {
        isMuted(device, scope: kAudioDevicePropertyScopeOutput)
    }

    private static func muteAddress(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress? {
        for element: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: scope,
                mElement: element
            )
            if AudioObjectHasProperty(device, &address) { return address }
        }
        return nil
    }

    private static func pid(of object: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanaged: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutableBytes(of: &unmanaged) { raw in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, raw.baseAddress!)
        }
        guard status == noErr, let unmanaged else { return nil }
        return unmanaged.takeRetainedValue() as String
    }

    private static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func streamIsFloat32(_ object: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(object, &address) else { return false }
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &format) == noErr else { return false }
        return format.mBitsPerChannel == 32 && (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0
    }
}

/// Bir uygulamanın tap’i. Ses iş parçacığı yalnızca kazancı okur.
private final class AppTap: @unchecked Sendable {
    private let gain = OSAllocatedUnfairLock(initialState: Float(1))
    private var tapID: AudioObjectID = 0
    private var aggregate: AudioDeviceID = 0
    private var proc: AudioDeviceIOProcID?
    private var bound: Set<AudioObjectID> = []

    func sync(ids: [AudioObjectID], gain value: Float) -> String? {
        guard #available(macOS 14.2, *) else { return "14.2" }
        gain.withLock { $0 = value }
        if tapID != 0, bound == Set(ids) { return nil }
        destroy()
        let description = CATapDescription(stereoMixdownOfProcesses: ids)
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        description.name = "Hal"
        var created: AudioObjectID = 0
        let tapStatus = AudioHardwareCreateProcessTap(description, &created)
        guard tapStatus == noErr, created != 0 else { return "\(tapStatus)" }
        tapID = created
        guard AudioDevices.streamIsFloat32(created, selector: kAudioTapPropertyFormat, scope: kAudioObjectPropertyScopeGlobal) else {
            destroy()
            return "format"
        }
        let output = Self.defaultOutput()
        guard output != 0,
              AudioDevices.streamIsFloat32(output, selector: kAudioDevicePropertyStreamFormat, scope: kAudioDevicePropertyScopeOutput),
              let tapUID = AudioDevices.string(created, kAudioTapPropertyUID),
              let outputUID = AudioDevices.string(output, kAudioDevicePropertyDeviceUID) else {
            destroy()
            return "device"
        }
        let subdevice: [String: Any] = [kAudioSubDeviceUIDKey: outputUID]
        let tap: [String: Any] = [
            kAudioSubTapUIDKey: tapUID,
            kAudioSubTapDriftCompensationKey: 1
        ]
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Hal Mixer",
            kAudioAggregateDeviceUIDKey: "dev.sungur.Hal.mixer.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceIsStackedKey: 0,
            kAudioAggregateDeviceTapAutoStartKey: 1,
            kAudioAggregateDeviceSubDeviceListKey: [subdevice],
            kAudioAggregateDeviceTapListKey: [tap]
        ]
        var aggregateID: AudioDeviceID = 0
        let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID)
        guard aggregateStatus == noErr, aggregateID != 0 else {
            destroy()
            return "\(aggregateStatus)"
        }
        aggregate = aggregateID
        var procID: AudioDeviceIOProcID?
        let context = Unmanaged.passUnretained(self).toOpaque()
        let procStatus = AudioDeviceCreateIOProcID(aggregateID, Self.render, context, &procID)
        guard procStatus == noErr, let procID else {
            destroy()
            return "\(procStatus)"
        }
        proc = procID
        let start = AudioDeviceStart(aggregateID, procID)
        guard start == noErr else {
            destroy()
            return "\(start)"
        }
        bound = Set(ids)
        return nil
    }

    func destroy() {
        if let proc, aggregate != 0 {
            AudioDeviceStop(aggregate, proc)
            AudioDeviceDestroyIOProcID(aggregate, proc)
        }
        proc = nil
        if aggregate != 0 {
            AudioHardwareDestroyAggregateDevice(aggregate)
            aggregate = 0
        }
        if tapID != 0 {
            if #available(macOS 14.2, *) {
                AudioHardwareDestroyProcessTap(tapID)
            }
            tapID = 0
        }
        bound = []
    }

    private static let render: AudioDeviceIOProc = { _, _, input, _, output, _, client in
        guard let client else { return noErr }
        let tap = Unmanaged<AppTap>.fromOpaque(client).takeUnretainedValue()
        let gain = tap.gain.withLock { $0 }
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let destination = UnsafeMutableAudioBufferListPointer(output)
        for index in 0..<destination.count {
            let out = destination[index]
            guard let raw = out.mData else { continue }
            let frames = Int(out.mDataByteSize) / MemoryLayout<Float>.size
            guard frames > 0 else { continue }
            let written = raw.bindMemory(to: Float.self, capacity: frames)
            if index < source.count, let inData = source[index].mData {
                let available = min(frames, Int(source[index].mDataByteSize) / MemoryLayout<Float>.size)
                let read = inData.bindMemory(to: Float.self, capacity: available)
                var cursor = 0
                while cursor < available {
                    let sample = read[cursor] * gain
                    written[cursor] = min(1, max(-1, sample))
                    cursor += 1
                }
                while cursor < frames {
                    written[cursor] = 0
                    cursor += 1
                }
            } else {
                memset(raw, 0, Int(out.mDataByteSize))
            }
        }
        return noErr
    }

    private static func defaultOutput() -> AudioDeviceID {
        var device: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }
}
