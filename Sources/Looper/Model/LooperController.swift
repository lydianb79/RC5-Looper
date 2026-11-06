import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

enum SideTab: String, CaseIterable, Identifiable {
    case setup = "Setup", audio = "Audio", rhythm = "Rhythm", memory = "Memory", help = "Help"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .setup: return "slider.horizontal.3"
        case .audio: return "cable.connector"
        case .rhythm: return "metronome"
        case .memory: return "square.stack.3d.up"
        case .help: return "questionmark.circle"
        }
    }
}

/// Main-thread brain of the app: pedal logic, memories, settings, MIDI, UI snapshot.
final class LooperController: ObservableObject {
    static let version = "1.7"

    // MARK: Published UI state
    @Published var settings = MemorySettings.defaults(for: 0) { didSet { applySettings() } }
    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var waveform: [Float] = []
    @Published private(set) var memoryIndex = 0
    @Published private(set) var memoryInfo: [MemoryInfo] = []
    @Published var dirty = false
    @Published var pendingMemorySwitch: Int?
    @Published var message: String?
    @Published var selectedTab: SideTab = .audio
    @Published var themeID: ThemeID = ThemeID(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .midnight {
        didSet { UserDefaults.standard.set(themeID.rawValue, forKey: "theme") }
    }
    @Published private(set) var audioStatus = "Starting audio…"
    @Published private(set) var inputGranted = false

    // Global preferences (not per memory)
    @Published var latencyMs: Double { didSet { defaults.set(latencyMs, forKey: "latencyMs"); applyGlobals() } }
    @Published var inputMonitor: Bool { didSet { defaults.set(inputMonitor, forKey: "inputMonitor"); applyGlobals() } }
    @Published var monoInput: Bool { didSet { defaults.set(monoInput, forKey: "monoInput"); applyGlobals() } }
    @Published var autoRecThreshold: Double { didSet { defaults.set(autoRecThreshold, forKey: "autoRecThreshold"); applyGlobals() } }
    @Published var midiClockOut: Bool { didSet { defaults.set(midiClockOut, forKey: "midiClockOut") } }
    @Published var maxLoopMinutes: Double { didSet { defaults.set(maxLoopMinutes, forKey: "maxLoopMinutes") } }

    // Audio device setup
    @Published private(set) var inputDevices: [AudioDevice] = []
    @Published private(set) var outputDevices: [AudioDevice] = []
    @Published private(set) var inputChannelCount = 0
    @Published private(set) var actualBufferFrames = 0
    @Published private(set) var deviceSummary = ""
    @Published var inputDeviceUID: String { didSet { if inputDeviceUID != oldValue { defaults.set(inputDeviceUID, forKey: "inputDeviceUID"); restartAudio() } } }
    @Published var outputDeviceUID: String { didSet { if outputDeviceUID != oldValue { defaults.set(outputDeviceUID, forKey: "outputDeviceUID"); restartAudio() } } }
    @Published var bufferFrames: Int { didSet { if bufferFrames != oldValue { defaults.set(bufferFrames, forKey: "bufferFrames"); restartAudio() } } }
    @Published private(set) var outputChannelCount = 0
    @Published var outputPair: Int { didSet { if outputPair != oldValue { defaults.set(outputPair, forKey: "outputPair"); restartAudio() } } }
    @Published var inputLeftChannel: Int { didSet { defaults.set(inputLeftChannel, forKey: "inputLeftChannel"); applyGlobals() } }
    @Published var inputRightChannel: Int { didSet { defaults.set(inputRightChannel, forKey: "inputRightChannel"); applyGlobals() } }

    let audio: AudioEngineManager
    var core: LoopCore { audio.core }
    let store = MemoryStore()
    let midi = MIDIManager()
    private let defaults = UserDefaults.standard

    // MARK: Private
    private var timer: Timer?
    private var keyMonitor: Any?
    private var lastLoopLength = 0
    private var lastGeneration = 0
    private var loading = false
    private var needWave = true
    private var tickCount = 0
    private var messageItem: DispatchWorkItem?
    private var taps: [TimeInterval] = []
    private var audioStarted = false

    private enum PedalAction { case none, armed, cancel, finishedRec, startedDub, stoppedDub, play, restart }
    private var lastPedalTime: TimeInterval = 0
    private var lastPedalAction: PedalAction = .none
    private var stateAtPress: LoopState = .empty
    private var pedalLongPress: DispatchWorkItem?
    private var stopLongPress: DispatchWorkItem?

    init() {
        let d = UserDefaults.standard
        latencyMs = d.object(forKey: "latencyMs") as? Double ?? -1
        inputMonitor = d.object(forKey: "inputMonitor") as? Bool ?? false
        monoInput = d.object(forKey: "monoInput") as? Bool ?? true
        autoRecThreshold = d.object(forKey: "autoRecThreshold") as? Double ?? 0.05
        midiClockOut = d.object(forKey: "midiClockOut") as? Bool ?? false
        let maxMinutes = d.object(forKey: "maxLoopMinutes") as? Double ?? 10
        maxLoopMinutes = maxMinutes
        inputDeviceUID = d.string(forKey: "inputDeviceUID") ?? ""
        outputDeviceUID = d.string(forKey: "outputDeviceUID") ?? ""
        bufferFrames = d.object(forKey: "bufferFrames") as? Int ?? 0
        outputPair = d.object(forKey: "outputPair") as? Int ?? 0
        inputLeftChannel = d.object(forKey: "inputLeftChannel") as? Int ?? 0
        inputRightChannel = d.object(forKey: "inputRightChannel") as? Int ?? 1
        audio = AudioEngineManager(maxSeconds: max(1, maxMinutes) * 60)

        memoryInfo = store.allInfo()
        let lastSlot = d.integer(forKey: "lastMemory")
        memoryIndex = max(0, min(MemoryStore.slotCount - 1, lastSlot))
        settings = store.loadSettings(memoryIndex) ?? MemorySettings.defaults(for: memoryIndex)
        applySettings()          // property observers don't fire inside init
        applyGlobals()

        midi.onMessage = { [weak self] s, a, b in self?.handleMIDI(s, a, b) }
        audio.onConfigurationChange = { [weak self] in
            guard let self else { return }
            self.bootEngine(input: self.inputGranted)
        }

        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        installKeyMonitor()
        refreshDevices()
        AudioDevices.observeChanges { [weak self] in self?.devicesChanged() }
        DispatchQueue.main.async { [weak self] in self?.startAudio() }
    }

    // MARK: Audio startup

    private func startAudio() {
        audioStarted = true
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            inputGranted = true
            bootEngine(input: true)
            loadMemoryAudio(memoryIndex)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    self.inputGranted = granted
                    self.bootEngine(input: granted)
                    self.loadMemoryAudio(self.memoryIndex)
                    if !granted { self.flash("Microphone access denied — recording is disabled") }
                }
            }
        default:
            inputGranted = false
            bootEngine(input: false)
            loadMemoryAudio(memoryIndex)
            flash("Enable microphone access in System Settings › Privacy & Security › Microphone")
        }
    }

    func bootEngine(input: Bool) {
        audio.inputDeviceUID = inputDeviceUID
        audio.outputDeviceUID = outputDeviceUID
        audio.bufferFrames = bufferFrames
        audio.outputPair = outputPair
        do {
            try audio.start(withInput: input)
            audioStatus = "In: \(audio.inputDescription)\nOut: \(audio.outputDescription)\nEngine: \(Int(core.sampleRate)) Hz · buffer \(audio.actualBufferFrames) frames"
            if let e = audio.lastError { audioStatus += "\n⚠︎ \(e)" }
            let outs = audio.outputChannelCount > 2 ? " \(audio.activeOutputPair + 1)–\(audio.activeOutputPair + 2)" : ""
            deviceSummary = "\(AudioDevices.name(audio.activeInputDevice)) → \(AudioDevices.name(audio.activeOutputDevice))\(outs) · \(audio.actualBufferFrames)"
            if latencyMs < 0 { latencyMs = (audio.estimatedLatencyMs * 10).rounded() / 10 }
        } catch {
            audioStatus = "Audio failed to start: \(error.localizedDescription)"
            if !inputDeviceUID.isEmpty && !outputDeviceUID.isEmpty && inputDeviceUID != outputDeviceUID {
                audioStatus += "\nTip: if separate input/output devices don't work together, combine them into an Aggregate Device in Audio MIDI Setup."
            }
        }
        inputChannelCount = audio.inputChannelCount
        outputChannelCount = audio.outputChannelCount
        actualBufferFrames = audio.actualBufferFrames
        applyGlobals()
    }

    func restartAudio() {
        guard audioStarted else { return }
        bootEngine(input: inputGranted)
    }

    func refreshDevices() {
        let all = AudioDevices.all()
        inputDevices = all.filter { $0.inputChannels > 0 }
        outputDevices = all.filter { $0.outputChannels > 0 }
    }

    private func devicesChanged() {
        refreshDevices()
        let inMissing = !inputDeviceUID.isEmpty && !inputDevices.contains { $0.uid == inputDeviceUID }
        let outMissing = !outputDeviceUID.isEmpty && !outputDevices.contains { $0.uid == outputDeviceUID }
        if inMissing || outMissing {
            flash("Selected audio device disconnected — using the system default")
            restartAudio()
        }
    }

    /// Buffer sizes the active output device supports.
    var bufferChoices: [Int] {
        let r = AudioDevices.bufferRange(audio.activeOutputDevice)
        return AudioDevices.bufferChoices.filter { r.contains($0) }
    }

    func useEstimatedLatency() { latencyMs = (audio.estimatedLatencyMs * 10).rounded() / 10 }

    var estimatedLatencyMs: Double { audio.estimatedLatencyMs }

    // MARK: Settings → core

    private func applySettings() {
        let c = core
        c.dubMode = settings.dubMode
        c.quantize = settings.quantize
        c.countIn = settings.countIn
        c.autoRec = settings.autoRec
        c.startMode = settings.startMode
        c.stopMode = settings.stopMode
        c.fadeSeconds = settings.fadeSeconds
        c.oneShot = settings.oneShot
        c.reverse = settings.reverse
        c.loopLevel = Float(settings.loopLevel)
        c.rhythmOn = settings.rhythmOn
        c.patternIndex = settings.rhythmPattern
        c.variation = settings.rhythmVariation
        c.kitIndex = settings.rhythmKit
        c.rhythmLevel = Float(settings.rhythmLevel)
        c.reverbLevel = Float(settings.rhythmReverb)
        c.stretchMode = settings.stretchMode
        c.tempo = settings.tempo
    }

    private func applyGlobals() {
        let c = core
        c.latencyFrames = Int(max(0, latencyMs) / 1000 * c.sampleRate)
        c.inputMonitor = inputMonitor
        c.monoInput = monoInput
        c.inputLeftChannel = inputLeftChannel
        c.inputRightChannel = inputRightChannel
        c.autoRecThreshold = Float(autoRecThreshold)
    }

    /// Only locked while the first recording is running; afterwards the tempo changes the loop speed (RC-5 style).
    var tempoLocked: Bool { snapshot.state == .recording }

    var hasLoop: Bool { snapshot.loopSeconds > 0 && core.loopTempo > 0 }

    /// Allowed tempo range: with a loop, 50 %…200 % of the recorded tempo.
    var tempoRange: ClosedRange<Double> {
        if hasLoop {
            let lt = core.loopTempo
            return max(20, lt * 0.5)...min(400, lt * 2)
        }
        return 40...250
    }

    func resetTempo() {
        guard hasLoop else { return }
        settings.tempo = core.loopTempo
    }

    // MARK: Pedal (REC / PLAY / DUB)

    func pedalDown() {
        let now = ProcessInfo.processInfo.systemUptime
        pedalLongPress?.cancel()
        if now - lastPedalTime < 0.4 {
            lastPedalTime = 0
            doublePress(after: lastPedalAction)
            return
        }
        lastPedalTime = now
        stateAtPress = core.state
        lastPedalAction = pedalPress(stateAtPress)
        let item = DispatchWorkItem { [weak self] in self?.pedalHeld() }
        pedalLongPress = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: item)
    }

    func pedalUp() {
        pedalLongPress?.cancel()
        pedalLongPress = nil
    }

    func pedalTap() {
        pedalDown()
        pedalUp()
    }

    private func pedalPress(_ st: LoopState) -> PedalAction {
        switch st {
        case .empty:
            if !inputGranted { flash("No audio input — check microphone permission") }
            core.send(.armRecording)
            return .armed
        case .armed, .autoRecArmed:
            core.send(.cancelArm)
            return .cancel
        case .recording:
            let next: LoopState = settings.recAction == .recDubPlay && !settings.oneShot ? .overdubbing : .playing
            core.send(.finishRecording(next: next))
            return .finishedRec
        case .playing:
            if settings.oneShot {
                core.send(.restart)
                return .restart
            }
            core.send(.startOverdub)
            return .startedDub
        case .overdubbing:
            core.send(.stopOverdub)
            return .stoppedDub
        case .stopped:
            core.send(.play)
            return .play
        }
    }

    /// Double press = STOP (as on the RC-5).
    private func doublePress(after action: PedalAction) {
        switch action {
        case .armed:
            if core.state == .recording { core.send(.clear) } else { core.send(.cancelArm) }
        case .startedDub, .finishedRec:
            core.send(.abortOverdub)
            core.send(.stop)
        default:
            core.send(.stop)
        }
    }

    /// Hold 2 s: UNDO/REDO while playing, CLEAR while stopped.
    private func pedalHeld() {
        switch stateAtPress {
        case .playing, .overdubbing:
            if lastPedalAction == .startedDub { core.send(.abortOverdub) }
            core.send(.toggleUndo)
            flash(snapshot.canUndo ? "UNDO" : "REDO")
        case .stopped:
            clear()
        default:
            break
        }
    }

    // MARK: Other transport buttons

    func stopDown() {
        stopLongPress?.cancel()
        core.send(.stop)
        let item = DispatchWorkItem { [weak self] in self?.clear() }
        stopLongPress = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: item)
    }

    func stopUp() {
        stopLongPress?.cancel()
        stopLongPress = nil
    }

    func stop() { core.send(.stop) }

    func undoRedo() {
        guard snapshot.canUndo || snapshot.canRedo else { flash("Nothing to undo"); return }
        let wasUndo = snapshot.canUndo
        core.send(.toggleUndo)
        flash(wasUndo ? "UNDO" : "REDO")
    }

    func clear() {
        core.send(.clear)
        settings.loopTempo = 0
        dirty = false
        flash("CLEAR")
    }

    func toggleRhythm() { settings.rhythmOn.toggle() }

    func toggleVariation() { settings.rhythmVariation = settings.rhythmVariation == 0 ? 1 : 0 }

    func selectPattern(_ i: Int) {
        let p = RhythmLibrary.pattern(i)
        settings.rhythmPattern = i
        if !tempoLocked && !hasLoop { settings.tempo = p.tempo }
        if !settings.rhythmOn { settings.rhythmOn = true }      // picking a pattern means you want to hear it
        flash("♫ \(String(format: "%02d", i + 1)) \(p.name)")
    }

    func tapTempo() {
        let now = ProcessInfo.processInfo.systemUptime
        if let last = taps.last, now - last > 2 { taps.removeAll() }
        taps.append(now)
        if taps.count > 6 { taps.removeFirst() }
        guard taps.count >= 2, let first = taps.first, let last = taps.last else { return }
        setTempo(60.0 / ((last - first) / Double(taps.count - 1)))
    }

    func setTempo(_ t: Double) {
        guard !tempoLocked else { flash("Tempo can't change while recording"); return }
        let r = tempoRange
        var v = (max(r.lowerBound, min(r.upperBound, t)) * 10).rounded() / 10
        if hasLoop && abs(v - core.loopTempo) < 0.3 { v = core.loopTempo }   // snap back to the original speed
        settings.tempo = v
    }

    // MARK: Snapshot / UI refresh

    private func tick() {
        let c = core
        let sr = c.sampleRate
        var s = Snapshot()
        s.state = c.state
        let L = c.loopLength
        s.loopSeconds = Double(L) / sr
        s.recordSeconds = Double(c.recordPos) / sr
        if L > 0 { s.position = Double(min(c.playPos, L)) / Double(L) }
        s.canUndo = c.currentLayer >= 0 && c.currentLayerActive
        s.canRedo = c.currentLayer >= 0 && !c.currentLayerActive
        s.inLevel = c.inLevel
        s.outLevel = c.outLevel
        s.waitingQuantize = c.pendingEnd > 0
        s.stopping = c.stopping || c.stopAtWrap
        s.rhythmRunning = c.rhythmRunning
        s.tempo = c.tempo
        s.loopTempo = c.loopTempo
        s.playbackRate = c.playbackRate

        let pattern = RhythmLibrary.pattern(settings.rhythmPattern)
        let beatFrames = 60.0 / max(1, c.tempo) * sr
        let measureFrames = max(1, pattern.beats * beatFrames)
        s.beatsPerMeasure = max(1, Int(pattern.beats.rounded(.up)))
        var pos: Double = 0
        if s.rhythmRunning {
            pos = Double(c.rhythmFrame)
        } else if s.state == .playing || s.state == .overdubbing {
            let srcPos = settings.reverse ? Double(L - c.playPos) : Double(c.playPos)
            pos = c.loopTempo > 0 ? srcPos * c.loopTempo / max(1, c.tempo) : srcPos
        } else if s.state == .recording {
            pos = Double(c.recordPos)
        }
        s.measure = Int(pos / measureFrames) + 1
        s.beat = min(s.beatsPerMeasure, Int(pos.truncatingRemainder(dividingBy: measureFrames) / beatFrames) + 1)
        s.beatPhase = (pos / beatFrames).truncatingRemainder(dividingBy: 1)
        if L > 0 {
            let outFrames = c.loopTempo > 0 ? Double(L) * c.loopTempo / max(1, c.tempo) : Double(L)
            s.totalMeasures = max(1, settings.loopMeasures > 0 ? settings.loopMeasures : Int((outFrames / measureFrames).rounded()))
        }
        if s.state == .armed { s.countdownBeats = Int((Double(c.countdown) / beatFrames).rounded(.up)) }
        if s != snapshot { snapshot = s }

        // New loop just recorded → derive tempo / measure count (RC-5 style)
        if L != lastLoopLength {
            if lastLoopLength == 0 && L > 0 && !loading { newLoopRecorded(length: L, withRhythm: c.recordedWithRhythm) }
            lastLoopLength = L
            needWave = true
        }
        if c.loopGeneration != lastGeneration {
            lastGeneration = c.loopGeneration
            needWave = true
            if !loading { dirty = L > 0 || s.state == .recording }
        }
        tickCount += 1
        let live = s.state == .recording || s.state == .overdubbing
        if (needWave && tickCount % 3 == 0) || (live && tickCount % 6 == 0) {
            needWave = false
            updateWaveform()
        }
        if midiClockOut {
            let running = s.rhythmRunning || s.state == .playing || s.state == .overdubbing || s.state == .recording
            midi.updateClock(running: running, tempo: c.tempo)
        } else if midi.clockRunning {
            midi.updateClock(running: false, tempo: c.tempo)
        }
    }

    private func newLoopRecorded(length L: Int, withRhythm: Bool) {
        let sr = core.sampleRate
        let p = RhythmLibrary.pattern(settings.rhythmPattern)
        if withRhythm {
            let mf = p.beats * 60.0 / settings.tempo * sr
            settings.loopMeasures = max(1, Int((Double(L) / mf).rounded()))
        } else {
            // Like the RC-5: guess a musical tempo from the loop length.
            let secs = Double(L) / sr
            var m = 1
            var t = Double(m) * p.beats * 60.0 / secs
            while t < 75 && m < 64 {
                m += 1
                t = Double(m) * p.beats * 60.0 / secs
            }
            settings.loopMeasures = m
            let derived = (min(300, max(30, t)) * 10).rounded() / 10
            core.loopTempo = 0              // keep playback at 1:1 while both values change
            settings.tempo = derived
        }
        settings.loopTempo = settings.tempo
        core.loopTempo = settings.tempo
    }

    private func updateWaveform() {
        let c = core
        let len: Int
        if c.state == .recording {
            len = max(0, c.recordPos - c.recComp)
        } else {
            len = c.loopLength
        }
        let bins = 240
        guard len > 0 else {
            if !waveform.isEmpty { waveform = [] }
            return
        }
        var out = [Float](repeating: 0, count: bins)
        for b in 0..<bins {
            let s0 = b * len / bins
            let s1 = max(s0 + 1, (b + 1) * len / bins)
            let step = max(1, (s1 - s0) / 64)
            var m: Float = 0
            var j = s0
            while j < s1 && j < len {
                let v = c.peak(at: j)
                if v > m { m = v }
                j += step
            }
            out[b] = min(1, m)
        }
        waveform = out
    }

    func flash(_ text: String) {
        message = text
        messageItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.message = nil }
        messageItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: item)
    }

    // MARK: Memories

    private func waitForCore() {
        var n = 0
        while core.pendingCommands > 0 && n < 100 {
            usleep(3000)
            n += 1
        }
    }

    func selectMemory(_ i: Int) {
        let target = max(0, min(MemoryStore.slotCount - 1, i))
        guard target != memoryIndex else { return }
        if dirty {
            pendingMemorySwitch = target
            return
        }
        loadMemory(target)
    }

    func memoryUp() { selectMemory(memoryIndex == MemoryStore.slotCount - 1 ? 0 : memoryIndex + 1) }
    func memoryDown() { selectMemory(memoryIndex == 0 ? MemoryStore.slotCount - 1 : memoryIndex - 1) }

    func confirmSwitch() {
        guard let t = pendingMemorySwitch else { return }
        pendingMemorySwitch = nil
        loadMemory(t)
    }

    func writeThenSwitch() {
        guard let t = pendingMemorySwitch else { return }
        pendingMemorySwitch = nil
        writeMemory()
        loadMemory(t)
    }

    func cancelSwitch() { pendingMemorySwitch = nil }

    private func loadMemory(_ i: Int) {
        memoryIndex = i
        defaults.set(i, forKey: "lastMemory")
        settings = store.loadSettings(i) ?? MemorySettings.defaults(for: i)
        loadMemoryAudio(i)
    }

    /// Clears the engine and loads the stored WAV of memory `i` (if any).
    private func loadMemoryAudio(_ i: Int) {
        loading = true
        core.send(.clear)
        waitForCore()
        if store.hasAudio(i) {
            do {
                let len = try MemoryStore.readAudio(from: store.audioURL(i), into: core)
                core.loopTempo = settings.loopTempo > 0 ? settings.loopTempo : settings.tempo
                if len > 0 { core.send(.setLoaded(length: len)) }
                waitForCore()
            } catch {
                flash("Could not load memory: \(error.localizedDescription)")
            }
        }
        lastLoopLength = core.loopLength
        lastGeneration = core.loopGeneration
        dirty = false
        loading = false
        needWave = true
    }

    func writeMemory() {
        let i = memoryIndex
        let L = core.loopLength
        var s = settings
        s.savedSeconds = Double(L) / core.sampleRate
        s.loopTempo = L > 0 ? core.loopTempo : 0
        do {
            try FileManager.default.createDirectory(at: store.dir(i), withIntermediateDirectories: true)
            if L > 0 {
                try MemoryStore.writeWAV(to: store.audioURL(i), core: core, length: L)
            } else {
                store.deleteAudio(i)
            }
            try store.saveSettings(s, slot: i)
            memoryInfo[i] = store.info(i)
            dirty = false
            flash("WRITE ✓  Memory \(String(format: "%02d", i + 1))")
        } catch {
            flash("Write failed: \(error.localizedDescription)")
        }
    }

    func deleteMemory() {
        let i = memoryIndex
        store.delete(i)
        core.send(.clear)
        settings = MemorySettings.defaults(for: i)
        memoryInfo[i] = store.info(i)
        dirty = false
        flash("Memory \(String(format: "%02d", i + 1)) deleted")
    }

    func importAudio() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an audio file to load as the loop of the current memory"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loading = true
        core.send(.clear)
        waitForCore()
        do {
            let len = try MemoryStore.readAudio(from: url, into: core)
            if len > 0 {
                core.send(.setLoaded(length: len))
                waitForCore()
                lastLoopLength = core.loopLength
                lastGeneration = core.loopGeneration
                newLoopRecorded(length: len, withRhythm: false)
                if settings.name.hasPrefix("MEMORY") || settings.name == "INIT MEMORY" {
                    settings.name = String(url.deletingPathExtension().lastPathComponent.prefix(24)).uppercased()
                }
                dirty = true
                flash("Imported \(url.lastPathComponent) — press WRITE to store it")
            }
        } catch {
            flash("Import failed: \(error.localizedDescription)")
        }
        loading = false
        needWave = true
    }

    func exportAudio() {
        let L = core.loopLength
        guard L > 0 else { flash("No loop to export"); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        panel.nameFieldStringValue = "\(settings.name).wav"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try MemoryStore.writeWAV(to: url, core: core, length: L)
            flash("Exported \(url.lastPathComponent)")
        } catch {
            flash("Export failed: \(error.localizedDescription)")
        }
    }

    // MARK: MIDI remote control

    private func handleMIDI(_ status: UInt8, _ d1: UInt8, _ d2: UInt8) {
        let type = status & 0xF0
        switch type {
        case 0x90 where d2 > 0:
            switch d1 {
            case 60: pedalDown()
            case 61: stopDown()
            case 62: undoRedo()
            case 63: clear()
            case 64: toggleRhythm()
            case 65: tapTempo()
            case 66: toggleVariation()
            default: break
            }
        case 0x80, 0x90:
            if d1 == 60 { pedalUp() }
            if d1 == 61 { stopUp() }
        case 0xB0:
            let on = d2 >= 64
            switch d1 {
            case 80: if on { pedalDown() } else { pedalUp() }
            case 81: if on { stopDown() } else { stopUp() }
            case 82: if on { undoRedo() }
            case 83: if on { clear() }
            case 84: if on { toggleRhythm() }
            case 85: settings.rhythmVariation = on ? 1 : 0
            case 86: settings.loopLevel = Double(d2) / 127.0 * 2.0
            default: break
            }
        case 0xC0:
            selectMemory(Int(d1))
        default:
            break
        }
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            if event.window?.firstResponder is NSText { return event }       // typing in a text field
            if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return event }
            let down = event.type == .keyDown
            switch event.keyCode {
            case 49:                                    // space = pedal
                if down { if !event.isARepeat { self.pedalDown() } } else { self.pedalUp() }
                return nil
            case 53:                                    // escape = stop
                if down { if !event.isARepeat { self.stopDown() } } else { self.stopUp() }
                return nil
            case 51, 117:                               // delete = clear
                if down && !event.isARepeat { self.clear() }
                return nil
            case 123:                                   // ←
                if down { self.memoryDown() }
                return nil
            case 124:                                   // →
                if down { self.memoryUp() }
                return nil
            default:
                break
            }
            guard down, !event.isARepeat, let ch = event.charactersIgnoringModifiers?.lowercased() else { return event }
            switch ch {
            case "s": self.stopDown(); self.stopUp()
            case "u": self.undoRedo()
            case "r": self.toggleRhythm()
            case "t": self.tapTempo()
            case "b": self.toggleVariation()
            default: return event
            }
            return nil
        }
    }
}
