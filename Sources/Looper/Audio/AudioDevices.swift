import AudioToolbox
import CoreAudio
import Foundation

/// A Core Audio device (built-in, USB/Thunderbolt interface, aggregate device, …).
struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let inputChannels: Int
    let outputChannels: Int
    let sampleRate: Double
}

/// Thin wrapper around the Core Audio HAL property API.
enum AudioDevices {
    static let bufferChoices = [32, 64, 128, 256, 512, 1024, 2048]

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func all() -> [AudioDevice] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.map { id in
            AudioDevice(id: id,
                        uid: string(id, kAudioDevicePropertyDeviceUID),
                        name: string(id, kAudioObjectPropertyName),
                        inputChannels: channelCount(id, input: true),
                        outputChannels: channelCount(id, input: false),
                        sampleRate: sampleRate(id))
        }
    }

    static func defaultDevice(input: Bool) -> AudioDeviceID {
        var addr = address(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    static func device(uid: String) -> AudioDeviceID? {
        guard !uid.isEmpty else { return nil }
        return all().first { $0.uid == uid }?.id
    }

    static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value)
        guard status == noErr, let v = value?.takeRetainedValue() else { return "" }
        return v as String
    }

    static func name(_ id: AudioDeviceID) -> String { string(id, kAudioObjectPropertyName) }

    static func channelCount(_ id: AudioObjectID, input: Bool) -> Int {
        var addr = address(kAudioDevicePropertyStreamConfiguration,
                           input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func sampleRate(_ id: AudioDeviceID) -> Double {
        var addr = address(kAudioDevicePropertyNominalSampleRate)
        var rate = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        _ = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &rate)
        return rate
    }

    private static func uint32(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector,
                               _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32 {
        var addr = address(selector, scope)
        var v = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        _ = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &v)
        return v
    }

    static func bufferSize(_ id: AudioDeviceID) -> Int { Int(uint32(id, kAudioDevicePropertyBufferFrameSize)) }

    static func bufferRange(_ id: AudioDeviceID) -> ClosedRange<Int> {
        var addr = address(kAudioDevicePropertyBufferFrameSizeRange)
        var range = AudioValueRange(mMinimum: 0, mMaximum: 0)
        var size = UInt32(MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &range) == noErr, range.mMaximum > 0 else { return 32...4096 }
        return Int(range.mMinimum)...Int(range.mMaximum)
    }

    @discardableResult
    static func setBufferSize(_ id: AudioDeviceID, _ frames: Int) -> Bool {
        guard id != 0 else { return false }
        let r = bufferRange(id)
        var v = UInt32(min(r.upperBound, max(r.lowerBound, frames)))
        var addr = address(kAudioDevicePropertyBufferFrameSize)
        return AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v) == noErr
    }

    /// Hardware latency + safety offset + buffer, in frames, for one direction.
    static func latencyFrames(_ id: AudioDeviceID, input: Bool) -> Int {
        guard id != 0 else { return 0 }
        let scope = input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
        let lat = Int(uint32(id, kAudioDevicePropertyLatency, scope))
        let safety = Int(uint32(id, kAudioDevicePropertySafetyOffset, scope))
        return lat + safety + bufferSize(id)
    }

    /// Calls `block` on the main queue whenever devices are added/removed or the defaults change.
    static func observeChanges(_ block: @escaping () -> Void) {
        let system = AudioObjectID(kAudioObjectSystemObject)
        for sel in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDefaultOutputDevice] {
            var addr = address(sel)
            _ = AudioObjectAddPropertyListenerBlock(system, &addr, DispatchQueue.main) { _, _ in block() }
        }
    }

    /// Selects the device used by an AUHAL unit (AVAudioEngine input/output node).
    @discardableResult
    static func assign(_ id: AudioDeviceID, to unit: AudioUnit?) -> OSStatus {
        guard let unit, id != 0 else { return -1 }
        var dev = id
        return AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                    &dev, UInt32(MemoryLayout<AudioDeviceID>.size))
    }
}
