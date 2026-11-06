import AVFoundation
import CoreAudio

/// Owns the AVAudioEngine graph:  input → sink(LoopCore.capture)   source(LoopCore.render) → main mixer → output
final class AudioEngineManager {
    let core: LoopCore
    private var engine = AVAudioEngine()
    private var observer: NSObjectProtocol?
    private(set) var isRunning = false
    private(set) var inputEnabled = false
    private(set) var inputDescription = "—"
    private(set) var outputDescription = "—"
    private(set) var inputChannelCount = 0
    private(set) var outputChannelCount = 0
    private(set) var activeOutputPair = 0
    private(set) var activeInputDevice: AudioDeviceID = 0
    private(set) var activeOutputDevice: AudioDeviceID = 0
    private(set) var actualBufferFrames = 0
    private(set) var lastError: String?
    var onConfigurationChange: (() -> Void)?

    /// Device UIDs chosen by the user ("" = follow the macOS default device).
    var inputDeviceUID = ""
    var outputDeviceUID = ""
    /// Requested hardware buffer size in frames (0 = leave the device setting alone).
    var bufferFrames = 0
    /// First (0-based) device output channel that receives the stereo signal: 0 = outputs 1–2, 2 = outputs 3–4, …
    var outputPair = 0

    init(maxSeconds: Double) {
        let probe = AVAudioEngine()
        let hw = probe.outputNode.outputFormat(forBus: 0).sampleRate
        let sr = hw > 0 ? hw : 48000
        core = LoopCore(sampleRate: sr, capacityFrames: Int(maxSeconds * sr))
    }

    /// Round-trip latency estimate from the Core Audio HAL (device latency + safety offset + buffers).
    var estimatedLatencyMs: Double {
        guard isRunning else { return 0 }
        var ms = 0.0
        if activeOutputDevice != 0 {
            let sr = max(1, AudioDevices.sampleRate(activeOutputDevice))
            ms += Double(AudioDevices.latencyFrames(activeOutputDevice, input: false)) / sr * 1000
        }
        if inputEnabled && activeInputDevice != 0 {
            let sr = max(1, AudioDevices.sampleRate(activeInputDevice))
            ms += Double(AudioDevices.latencyFrames(activeInputDevice, input: true)) / sr * 1000
        }
        // one extra buffer for the input → output hand-over inside the app
        ms += Double(max(actualBufferFrames, 64)) / core.sampleRate * 1000
        return ms
    }

    func start(withInput: Bool) throws {
        stop()
        lastError = nil
        engine = AVAudioEngine()
        let core = self.core

        // 1. Pick devices before touching formats.
        let outID = AudioDevices.device(uid: outputDeviceUID) ?? AudioDevices.defaultDevice(input: false)
        if !outputDeviceUID.isEmpty {
            let st = AudioDevices.assign(outID, to: engine.outputNode.audioUnit)
            if st != noErr { lastError = "Could not select output device (\(st))" }
        }
        activeOutputDevice = outID

        var inID: AudioDeviceID = 0
        if withInput {
            inID = AudioDevices.device(uid: inputDeviceUID) ?? AudioDevices.defaultDevice(input: true)
            if !inputDeviceUID.isEmpty {
                let st = AudioDevices.assign(inID, to: engine.inputNode.audioUnit)
                if st != noErr { lastError = "Could not select input device (\(st))" }
            }
        }
        activeInputDevice = inID

        // 2. Buffer size.
        if bufferFrames > 0 {
            AudioDevices.setBufferSize(outID, bufferFrames)
            if inID != 0 && inID != outID { AudioDevices.setBufferSize(inID, bufferFrames) }
        }
        actualBufferFrames = AudioDevices.bufferSize(outID)

        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: core.sampleRate, channels: 2) else {
            throw NSError(domain: "Looper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported audio format"])
        }

        // 3. Output: loop core → main mixer (does sample-rate conversion to the device if needed).
        let source = AVAudioSourceNode(format: fmt) { _, _, frameCount, abl -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(abl)
            guard list.count > 0, let d0 = list[0].mData else { return noErr }
            let l = d0.assumingMemoryBound(to: Float.self)
            var r = l
            if list.count > 1, let d1 = list[1].mData { r = d1.assumingMemoryBound(to: Float.self) }
            core.render(frames: Int(frameCount), outL: l, outR: r)
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: fmt)

        // 4. Input: device → sink node → loop core.
        inputEnabled = false
        inputChannelCount = 0
        inputDescription = withInput ? "No input device" : "Disabled (no microphone permission)"
        if withInput {
            let input = engine.inputNode
            let inFmt = input.outputFormat(forBus: 0)
            if inFmt.channelCount > 0 && inFmt.sampleRate > 0 {
                core.inputSampleRate = inFmt.sampleRate
                let sink = AVAudioSinkNode { _, frameCount, abl -> OSStatus in
                    let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: abl))
                    guard list.count > 0, let d0 = list[0].mData else { return noErr }
                    let n = Int(frameCount)
                    if list.count == 1 {
                        // interleaved (or mono)
                        let ch = max(1, Int(list[0].mNumberChannels))
                        let lc = min(max(0, core.inputLeftChannel), ch - 1)
                        let rc = min(max(0, core.inputRightChannel), ch - 1)
                        let base = UnsafePointer(d0.assumingMemoryBound(to: Float.self))
                        core.capture(frames: n, ch0: base + lc, ch1: ch > 1 ? base + rc : nil, stride: ch)
                    } else {
                        let ch = list.count
                        let lc = min(max(0, core.inputLeftChannel), ch - 1)
                        let rc = min(max(0, core.inputRightChannel), ch - 1)
                        guard let dl = list[lc].mData else { return noErr }
                        let pl = UnsafePointer(dl.assumingMemoryBound(to: Float.self))
                        var pr: UnsafePointer<Float>? = nil
                        if let dr = list[rc].mData { pr = UnsafePointer(dr.assumingMemoryBound(to: Float.self)) }
                        core.capture(frames: n, ch0: pl, ch1: pr, stride: 1)
                    }
                    return noErr
                }
                engine.attach(sink)
                engine.connect(input, to: sink, format: inFmt)
                inputEnabled = true
                inputChannelCount = Int(inFmt.channelCount)
                inputDescription = "\(AudioDevices.name(inID)) · \(inFmt.channelCount) ch @ \(Int(inFmt.sampleRate)) Hz"
            }
        }

        let outFmt = engine.outputNode.outputFormat(forBus: 0)

        // 5. Output routing on multichannel interfaces: send L/R to the chosen pair of outputs.
        let devOut = AudioDevices.channelCount(outID, input: false)
        outputChannelCount = devOut
        activeOutputPair = 0
        var channelMap: [NSNumber]?
        if devOut > 2 {
            let first = min(max(0, outputPair), devOut - 1)
            var map = [NSNumber](repeating: -1, count: devOut)
            map[first] = 0
            if first + 1 < devOut { map[first + 1] = 1 }
            channelMap = map
            activeOutputPair = first
        }
        let routing = devOut > 2
            ? (activeOutputPair + 1 < devOut ? "outputs \(activeOutputPair + 1)–\(activeOutputPair + 2)" : "output \(activeOutputPair + 1)")
            : "\(outFmt.channelCount) ch"
        outputDescription = "\(AudioDevices.name(outID)) · \(routing) @ \(Int(outFmt.sampleRate)) Hz"

        if let channelMap { engine.outputNode.auAudioUnit.channelMap = channelMap }
        engine.prepare()
        // set again after prepare in case the I/O unit was re-initialised
        if let channelMap { engine.outputNode.auAudioUnit.channelMap = channelMap }
        core.hostRunning = true
        do {
            try engine.start()
        } catch {
            core.hostRunning = false
            throw error
        }
        isRunning = true
        actualBufferFrames = AudioDevices.bufferSize(outID)

        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.onConfigurationChange?()
        }
    }

    func stop() {
        if let o = observer {
            NotificationCenter.default.removeObserver(o)
            observer = nil
        }
        if isRunning {
            engine.stop()
        }
        isRunning = false
        core.hostRunning = false
    }
}
