import Foundation
import os

/// Commands sent from the UI thread to the audio thread.
enum LoopCommand {
    case armRecording
    case cancelArm
    case finishRecording(next: LoopState)
    case startOverdub
    case stopOverdub
    case abortOverdub
    case play
    case restart
    case stop
    case toggleUndo
    case clear
    case setLoaded(length: Int)
    case resetRhythm
    case rhythmStart     // play the rhythm on its own (no loop yet)
    case rhythmStop
    case undo
    case redo
    case doubleLoop
    case fadeOut
    case trackPress(Int)             // extra tracks 0…3 (tracks 2–5 in the UI)
    case trackUndo(Int)
    case trackRedo(Int)
    case trackClear(Int)
    case trackStopDub(Int)
    case trackSetLoaded(Int, length: Int)
    case trackPrepareLoad(Int)       // finish pending jobs so the base can be filled
    case stopAtLoopEnd
    case armSwap(SwapInfo)
    case cancelSwap
}

/// A preloaded memory that replaces the current one at the next loop point (song mode).
struct SwapInfo {
    var length = 0
    var trackLengths: [Int] = []
    var loopTempo: Double = 0
    var tempo: Double = 120
    var pattern = 0
    var variation = 0
    var kit = 0
    var rhythmOn = false
}

/// The realtime looper engine.
///
/// * Track 1 (the main loop) lives in `stack` (base recording + undoable overdub layers,
///   see LayerStack). Tracks 2–5 (`subs`) are synced to it (see SubTrack).
/// * Input FX process the input before it is recorded; loop FX process the loop playback.
final class LoopCore {
    let sampleRate: Double
    let capacity: Int

    let stack: LayerStack
    /// Tracks 2…5.
    static let subCount = 4
    let subs: [SubTrack]
    let inputFX: FXChain
    let loopFX: FXChain
    var baseL: UnsafeMutablePointer<Float> { stack.baseL }
    var baseR: UnsafeMutablePointer<Float> { stack.baseR }
    func sub(_ t: Int) -> SubTrack { subs[max(0, min(LoopCore.subCount - 1, t))] }

    let rhythm: RhythmEngine

    // MARK: Parameters (written by the UI thread, read by the audio thread)
    var loopLevel: Float = 1
    var rhythmLevel: Float = 0.7
    var inputMonitor = false
    var monoInput = true
    var dubMode: DubMode = .overdub
    var reverse = false
    var oneShot = false
    var quantize = true
    var countIn = false
    var rhythmIntro = false
    var rhythmEnding = false
    var autoRec = false
    var autoRecThreshold: Float = 0.05
    var startMode: StartMode = .immediate
    var stopMode: StopMode = .immediate
    var fadeSeconds: Double = 2
    var latencyFrames = 0
    var rhythmOn = false
    var tempo: Double = 120
    var patternIndex = 0
    var variation = 0
    var kitIndex = 0
    var reverbLevel: Float = 0.2
    var humanize: Float = 0.6
    /// Fixed loop length in bars (0 = free). Recording then ends by itself after that many bars.
    var fixedBars = 0
    /// Count-in length in bars (1 or 2).
    var countBars = 1
    /// Metronome click when the rhythm is off: 0 = only for the count-in, 1 = also while recording / overdubbing, 2 = always.
    var clickMode = 0
    /// What follows a fixed-length recording (overdub or play).
    var fixedNext: LoopState = .playing
    var inputSampleRate: Double = 0
    var inputLeftChannel = 0
    var inputRightChannel = 1
    /// Tempo the loop was recorded at. Playback rate = tempo / loopTempo (RC-5 style live tempo).
    var loopTempo: Double = 0
    var stretchMode: StretchMode = .keepPitch
    /// Track 1 mute and the global loop mute ("drop").
    var mainMuted = false
    var allMuted = false
    /// What follows a recording on tracks 2 / 3.
    var trackDubAfterRecord = false

    // MARK: Published state (written by the audio thread)
    private(set) var state: LoopState = .empty
    private(set) var loopLength = 0
    private(set) var playPos = 0
    private(set) var recordPos = 0
    private(set) var recComp = 0
    private(set) var countdown = 0
    private(set) var pendingEnd = 0
    private(set) var stopping = false
    private(set) var stopAtWrap = false
    private(set) var endingPending = false
    /// The rhythm plays on its own while no loop exists (started with Space / Play, stopped with Space / Stop).
    private(set) var rhythmPreview = false
    /// Main-loop cycle counter (+1 per forward wrap, -1 per reverse wrap): keeps tracks 2 / 3 in sync.
    private(set) var masterCycle = 0
    /// Number of loop wraps since play started (song mode counts repeats with it).
    private(set) var wrapCount = 0
    private(set) var swapGeneration = 0
    private var pendingSwap: SwapInfo?
    var swapPending: Bool { pendingSwap != nil }
    var undoDepth: Int { stack.undoDepth }
    var redoDepth: Int { stack.redoDepth }
    private(set) var rhythmRunning = false
    private(set) var recordedWithRhythm = false
    /// The current loop was recorded after a count-in (its tempo is the count tempo).
    private(set) var recordedWithCount = false
    private var countingIn = false
    private(set) var inLevel: Float = 0
    private(set) var inLevelL: Float = 0
    private(set) var inLevelR: Float = 0
    private(set) var outLevel: Float = 0
    private(set) var loopGeneration = 0
    var rhythmFrame: Int { rhythm.frame }
    var measureFrames: Double { rhythm.measureFrames }

    // MARK: Internal realtime state
    private var pendingNext: LoopState = .playing
    private var tailNext = 0
    private var tailRemaining = 0
    private var gain: Float = 1
    private var gainTarget: Float = 1
    private var gainStep: Float = 0.001
    private var jobDelay = 0
    /// Per-callback flags so idle tracks cost nothing per sample.
    private var anySubContent = false
    private var anySubWriting = false
    private var mainGain: Float = 1
    private var allGain: Float = 1
    private var muteStep: Float = 0.001

    // Time-stretch state (granular overlap-add, Hann windows at 50 % overlap)
    private let grainHop: Int
    private let grainLen: Int
    private let window: UnsafeMutablePointer<Float>
    private let rgStart: UnsafeMutablePointer<Int>
    private let rgJ: UnsafeMutablePointer<Int>
    private let rgOn: UnsafeMutablePointer<Int>
    private let wgStart: UnsafeMutablePointer<Int>
    private let wgJ: UnsafeMutablePointer<Int>
    private let wgOn: UnsafeMutablePointer<Int>
    private let writerGrains = 8
    private var readerTimer = 0
    private var writerTimer: Double = 0
    private var vPos: Double = 0
    private var vLastWrite = -1
    private var needStretchInit = true
    private var writerReset = true
    private var wasStretched = false
    private(set) var playbackRate: Double = 1

    // Input ring buffer (sink node -> source node)
    private let ringMask: Int
    private let ringL: UnsafeMutablePointer<Float>
    private let ringR: UnsafeMutablePointer<Float>
    private var ringWrite = 0
    private var ringRead = 0
    private var srcT: Double = 0
    private var srcPrevL: Float = 0
    private var srcPrevR: Float = 0

    // Command queue
    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private let cmdBuf: UnsafeMutablePointer<LoopCommand>
    private let cmdCap = 128
    private var cmdCount = 0
    /// True while an audio thread is pulling `render`. When false, commands run immediately.
    var hostRunning = false
    var pendingCommands: Int { cmdCount }

    init(sampleRate: Double, capacityFrames: Int) {
        self.sampleRate = sampleRate
        let cap = max(Int(sampleRate * 2), capacityFrames)
        capacity = cap
        // calloc'd memory is lazily committed by macOS, so a large capacity only
        // costs physical RAM for what is actually recorded.
        func buffer(_ n: Int) -> UnsafeMutablePointer<Float> {
            calloc(n, MemoryLayout<Float>.size)!.assumingMemoryBound(to: Float.self)
        }
        stack = LayerStack(capacity: cap)
        subs = (0..<LoopCore.subCount).map { _ in SubTrack(capacity: cap, sampleRate: sampleRate) }
        inputFX = FXChain(sampleRate: sampleRate)
        loopFX = FXChain(sampleRate: sampleRate)
        muteStep = Float(1.0 / (0.012 * sampleRate))
        ringL = buffer(1 << 15); ringR = buffer(1 << 15)
        ringMask = (1 << 15) - 1
        func ints(_ count: Int = 2) -> UnsafeMutablePointer<Int> {
            let p = UnsafeMutablePointer<Int>.allocate(capacity: count)
            p.initialize(repeating: 0, count: count)
            return p
        }
        let hop = max(256, Int(0.021 * sampleRate))
        grainHop = hop
        grainLen = hop * 2
        let win = UnsafeMutablePointer<Float>.allocate(capacity: hop * 2)
        for j in 0..<(hop * 2) {
            win[j] = Float(0.5 - 0.5 * cos(2 * Double.pi * Double(j) / Double(hop * 2)))
        }
        window = win
        rgStart = ints(); rgJ = ints(); rgOn = ints()
        wgStart = ints(8); wgJ = ints(8); wgOn = ints(8)
        let lk = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        lk.initialize(to: os_unfair_lock())
        lock = lk
        let cb = UnsafeMutablePointer<LoopCommand>.allocate(capacity: 128)
        cb.initialize(repeating: .clear, count: 128)
        cmdBuf = cb
        rhythm = RhythmEngine(sampleRate: sampleRate)
    }

    // MARK: Commands

    func send(_ c: LoopCommand) {
        os_unfair_lock_lock(lock)
        if cmdCount < cmdCap {
            cmdBuf[cmdCount] = c
            cmdCount += 1
        }
        if !hostRunning { drainLocked() }
        os_unfair_lock_unlock(lock)
    }

    private func drainLocked() {
        var i = 0
        while i < cmdCount {
            handle(cmdBuf[i])
            i += 1
        }
        cmdCount = 0
    }

    private func handle(_ c: LoopCommand) {
        switch c {
        case .armRecording: armRecording()
        case .cancelArm:
            if state == .armed || state == .autoRecArmed {
                state = .empty
                countingIn = false
                rhythm.cancelSpecial()
            }
        case .finishRecording(let next): finishRecording(next)
        case .startOverdub:
            if state == .playing && loopLength > 0 && !stopping { beginDub() }
        case .stopOverdub:
            if state == .overdubbing { state = .playing }
        case .abortOverdub: abortDub()
        case .play:
            if state == .stopped && loopLength > 0 { startPlay() }
        case .restart:
            if loopLength > 0 {
                if state == .stopped { startPlay() }
                else if state == .playing || state == .overdubbing {
                    playPos = reverse ? loopLength - 1 : 0
                    masterCycle = 0
                    wrapCount = 0
                    syncStretch()
                    rhythm.reset()
                }
            }
        case .stop: requestStop()
        case .toggleUndo: toggleUndo()
        case .undo:
            if state == .overdubbing { state = .playing }
            stack.undo()
            loopGeneration &+= 1
        case .redo:
            stack.redo()
            loopGeneration &+= 1
        case .doubleLoop: doubleLoop()
        case .fadeOut:
            if state == .playing || state == .overdubbing {
                if state == .overdubbing { state = .playing }
                stopping = true
                gainTarget = 0
                gainStep = Float(1.0 / (max(0.05, fadeSeconds) * sampleRate))
            }
        case .trackPress(let t):
            guard loopLength > 0, !reverse else { break }
            if state == .stopped { startPlay() }
            guard state == .playing || state == .overdubbing else { break }
            sub(t).press(cycle: masterCycle, position: playPos, mainLength: loopLength, dubAfterRecord: trackDubAfterRecord)
        case .trackUndo(let t): sub(t).undo()
        case .trackRedo(let t): sub(t).redo()
        case .trackClear(let t): sub(t).clear()
        case .trackStopDub(let t): sub(t).stopOverdub()
        case .trackSetLoaded(let t, let len): sub(t).setLoaded(length: len, mainLength: loopLength)
        case .trackPrepareLoad(let t): sub(t).stack.finishAllJobs()
        case .stopAtLoopEnd:
            if state == .playing || state == .overdubbing {
                if state == .overdubbing { state = .playing }
                stopAtWrap = true
            }
        case .armSwap(let info):
            pendingSwap = info
            if state != .playing && state != .overdubbing { applySwap() }
        case .cancelSwap: pendingSwap = nil
        case .clear: clearAll()
        case .resetRhythm: rhythm.reset()
        case .rhythmStart:
            if rhythmOn && (state == .empty || state == .autoRecArmed) {
                rhythm.reset()
                rhythm.cancelSpecial()
                rhythmPreview = true
            }
        case .rhythmStop:
            rhythmPreview = false
        case .setLoaded(let len):
            if state == .empty {
                loopLength = max(0, min(len, capacity))
                state = loopLength > 0 ? .stopped : .empty
                playPos = 0
                masterCycle = 0
                syncStretch()
                stack.clearAll()
                tailRemaining = 0
                loopGeneration &+= 1
            }
        }
    }

    // MARK: Transport logic (audio thread)

    private func armRecording() {
        guard state == .empty else { return }
        let mf = rhythm.measureFrames
        if countIn || rhythmIntro {
            // One bar before recording starts. With the rhythm on: the pattern (or the intro fill);
            // with the rhythm off: a metronome count (accented click on beat 1).
            rhythm.reset()
            rhythm.cancelSpecial()
            if rhythmOn {
                if rhythmIntro { rhythm.startIntro() }
            } else {
                rhythm.startCount()
            }
            countingIn = true
            countdown = Int((mf * Double(max(1, min(2, countBars)))).rounded())
            state = .armed
            return
        }
        if rhythmOn {
            if quantize && rhythmPreview {
                // The rhythm is already playing: start on the next bar line.
                let pos = Double(rhythm.frame).truncatingRemainder(dividingBy: mf)
                let remaining = Int((mf - pos).rounded())
                if pos < 64 || remaining < 64 { beginRecording() } else {
                    countdown = remaining
                    state = .armed
                }
                return
            }
            beginRecording()
            return
        }
        if autoRec {
            state = .autoRecArmed
            return
        }
        beginRecording()
    }

    private func beginRecording() {
        state = .recording
        recordPos = 0
        pendingEnd = 0
        tailRemaining = 0
        recComp = latencyFrames
        recordedWithRhythm = rhythmOn
        recordedWithCount = countingIn || (clickMode > 0 && !rhythmOn)
        countingIn = false
        loopLength = 0
        stack.clearAll()
        stopping = false
        stopAtWrap = false
        rhythm.reset()
        rhythm.cancelSpecial()
        if fixedBars > 0 {
            pendingEnd = max(Int(0.25 * sampleRate), min(capacity, Int((Double(fixedBars) * rhythm.measureFrames).rounded())))
            pendingNext = fixedNext
        }
        loopGeneration &+= 1
    }

    private func finishRecording(_ next: LoopState) {
        guard state == .recording else { return }
        if pendingEnd > 0 {
            pendingNext = next
            return
        }
        if recordPos < Int(0.25 * sampleRate) {
            clearAll()
            return
        }
        if quantize && recordedWithRhythm && rhythmOn {
            let mf = rhythm.measureFrames
            let bars = max(1.0, (Double(recordPos) / mf).rounded())
            let target = min(capacity, Int((bars * mf).rounded()))
            if target > recordPos {
                pendingEnd = target
                pendingNext = next
                return
            }
            finalize(length: target, next: next)
        } else {
            finalize(length: recordPos, next: next)
        }
    }

    private func finalize(length: Int, next: LoopState) {
        let L = max(1, min(length, capacity))
        loopLength = L
        // Latency compensation: the last `recComp` samples of the loop arrive
        // after the loop point; capture them while the loop starts playing.
        tailNext = max(0, recordPos - recComp)
        tailRemaining = max(0, L - tailNext)
        pendingEnd = 0
        playPos = reverse ? L - 1 : 0
        masterCycle = 0
        wrapCount = 0
        loopTempo = tempo
        syncStretch()
        state = .playing
        stopping = false
        stopAtWrap = false
        gain = 1
        gainTarget = 1
        rhythm.reset()
        loopGeneration &+= 1
        switch next {
        case .overdubbing: beginDub()
        case .stopped: enterStopped()
        default: break
        }
    }

    private func beginDub() {
        guard stack.beginDub(length: loopLength) else { return }
        writerReset = true
        // Grace period: lets a double-press / long-press cancel this dub
        // before older layers are committed.
        jobDelay = Int(2.5 * sampleRate)
        state = .overdubbing
        loopGeneration &+= 1
    }

    private func abortDub() {
        guard state == .overdubbing else { return }
        if jobDelay > 0 { _ = stack.abortDub() }
        state = .playing
        loopGeneration &+= 1
    }

    private func toggleUndo() {
        guard stack.hasLayers && loopLength > 0 else { return }
        if state == .overdubbing {
            state = .playing
            stack.undo()
        } else {
            stack.toggleUndo()
        }
        loopGeneration &+= 1
    }

    /// ×2: the loop is copied behind itself; tracks 2 / 3 follow.
    private func doubleLoop() {
        let L = loopLength
        guard L > 0, L * 2 <= capacity, tailRemaining == 0, state != .recording, !stack.doubling else { return }
        if state == .overdubbing { state = .playing }
        guard stack.startDouble(length: L) else { return }
        for tr in subs { tr.mainDoubled(oldMainLength: L) }
        let odd = ((masterCycle % 2) + 2) % 2 == 1
        if odd {
            playPos += L
            vPos += Double(L)
        }
        masterCycle = Int((Double(masterCycle) / 2).rounded(.down))
        loopLength = L * 2
        needStretchInit = true
        loopGeneration &+= 1
    }

    /// Swaps in a preloaded memory (song mode). Called at a loop point or while stopped.
    private func applySwap() {
        guard let info = pendingSwap else { return }
        pendingSwap = nil
        stack.swapPreloaded()
        loopLength = max(0, min(info.length, capacity))
        loopTempo = info.loopTempo
        tempo = info.tempo
        patternIndex = info.pattern
        variation = info.variation
        kitIndex = info.kit
        rhythmOn = info.rhythmOn
        playPos = reverse ? max(0, loopLength - 1) : 0
        masterCycle = 0
        wrapCount = 0
        syncStretch()
        let lens = info.trackLengths
        for t in 0..<LoopCore.subCount {
            let tr = sub(t)
            if t < lens.count && lens[t] > 0 {
                tr.stack.swapPreloaded()
                tr.setLoaded(length: lens[t], mainLength: loopLength)
            } else {
                tr.clear()
            }
        }
        if loopLength == 0 { state = .empty }
        rhythm.reset()
        swapGeneration &+= 1
        loopGeneration &+= 1
    }

    private func startPlay() {
        state = .playing
        stopping = false
        stopAtWrap = false
        playPos = reverse ? loopLength - 1 : 0
        masterCycle = 0
        wrapCount = 0
        syncStretch()
        gain = 0
        gainTarget = 1
        let secs = startMode == .fadeIn ? max(0.05, fadeSeconds) : 0.004
        gainStep = Float(1.0 / (secs * sampleRate))
        endingPending = false
        rhythm.reset()
        rhythm.cancelSpecial()
    }

    private func requestStop() {
        switch state {
        case .recording:
            finishRecording(.stopped)
        case .stopped:
            pendingSwap = nil
        case .armed, .autoRecArmed:
            state = .empty
            countingIn = false
            rhythmPreview = false
            rhythm.cancelSpecial()
        case .empty:
            rhythmPreview = false
        case .playing, .overdubbing:
            if state == .overdubbing { state = .playing }
            if stopping || stopAtWrap || endingPending {             // second stop = stop now
                rhythm.cancelSpecial()
                enterStopped()
                return
            }
            if rhythmEnding && rhythmOn {
                // RC-5 style ending: fill to the next bar line, final hit, then stop
                endingPending = true
                rhythm.requestEnding()
                return
            }
            switch stopMode {
            case .immediate:
                stopping = true
                gainTarget = 0
                gainStep = Float(1.0 / (0.01 * sampleRate))
            case .fadeOut:
                stopping = true
                gainTarget = 0
                gainStep = Float(1.0 / (max(0.05, fadeSeconds) * sampleRate))
            case .loopEnd:
                stopAtWrap = true
            }
        }
    }

    private func enterStopped() {
        for tr in subs { tr.mainStopped(mainLength: loopLength) }
        if pendingSwap != nil { applySwap() }
        masterCycle = 0
        endingPending = false
        rhythmPreview = false
        state = .stopped
        stopping = false
        stopAtWrap = false
        gain = 0
        gainTarget = 0
        playPos = reverse ? max(0, loopLength - 1) : 0
        syncStretch()
    }

    private func clearAll() {
        stack.clearAll()
        for tr in subs { tr.clear() }
        pendingSwap = nil
        masterCycle = 0
        jobDelay = 0
        state = .empty
        loopLength = 0
        loopTempo = 0
        endingPending = false
        countingIn = false
        rhythmPreview = false
        rhythm.cancelSpecial()
        playPos = 0
        syncStretch()
        recordPos = 0
        pendingEnd = 0
        tailRemaining = 0
        stopping = false
        stopAtWrap = false
        gain = 1
        gainTarget = 1
        loopGeneration &+= 1
    }

    private func loopWrapped() {
        playPos = reverse ? loopLength - 1 : 0
        onWrap()
    }

    private func onWrap() {
        masterCycle += reverse ? -1 : 1
        wrapCount &+= 1
        for tr in subs { tr.mainWrapped(cycle: masterCycle, mainLength: loopLength) }
        if pendingSwap != nil {
            applySwap()
            return
        }
        rhythm.reset()
        if oneShot || stopAtWrap { enterStopped() }
    }

    private func syncStretch() {
        vPos = Double(playPos)
        needStretchInit = true
        writerReset = true
    }

    // MARK: Playback paths

    /// Main cycle that main-loop index `i` belongs to (grains may straddle the loop point).
    @inline(__always) private func cycleOf(_ i: Int, _ L: Int) -> Int {
        let h = playPos
        if i - h > L / 2 { return masterCycle - 1 }
        if h - i > L / 2 { return masterCycle + 1 }
        return masterCycle
    }

    /// All tracks at main-loop index `i` (track levels and mutes applied).
    @inline(__always) private func mix(_ i: Int, main: Bool = true) -> (Float, Float) {
        var l: Float = 0
        var r: Float = 0
        if main {
            let m = stack.mix(i)
            l = m.0 * mainGain
            r = m.1 * mainGain
        }
        let L = loopLength
        if anySubContent {
            let c = cycleOf(i, L)
            var k = 0
            while k < LoopCore.subCount {
                let a = subs[k].read(cycle: c, index: i, mainLength: L)
                l += a.0
                r += a.1
                k += 1
            }
        }
        return (l, r)
    }

    /// Input for tracks 2 / 3 (they record and overdub while the main loop plays).
    @inline(__always) private func writeSubs(_ w: Int, _ L: Int, _ inL: Float, _ inR: Float, stretched: Bool) {
        guard anySubWriting else { return }
        let c = cycleOf(w, L)
        var k = 0
        while k < LoopCore.subCount {
            let tr = subs[k]
            if tr.state == .recording || tr.state == .overdubbing {
                tr.write(cycle: c, index: w, mainLength: L, inL, inR, fillGaps: stretched)
            }
            k += 1
        }
    }

    @inline(__always) private func wrapIndex(_ x: Int, _ L: Int) -> Int {
        var i = x % L
        if i < 0 { i += L }
        return i
    }

    /// Original-tempo playback (sample exact).
    @inline(__always) private func renderDirect(_ L: Int, _ st: LoopState, _ inL: Float, _ inR: Float) -> (Float, Float) {
        let p = min(max(0, playPos), L - 1)
        let replacing = st == .overdubbing && dubMode == .replace && !stopping
        let s = mix(p, main: !replacing)
        if tailRemaining == 0 && !stopping {
            let comp = min(latencyFrames, L / 2)
            var w = reverse ? p + comp : p - comp
            if w >= L { w -= L } else if w < 0 { w += L }
            if st == .overdubbing { stack.write(w, inL, inR, replace: dubMode == .replace) }
            writeSubs(w, L, inL, inR, stretched: false)
        }
        if reverse {
            playPos = p - 1
            if playPos < 0 { loopWrapped() }
        } else {
            playPos = p + 1
            if playPos >= L { loopWrapped() }
        }
        return s
    }

    private func initStretch(_ L: Int, _ rate: Double, _ dir: Int) {
        let H = Double(grainHop)
        let d = Double(dir)
        rgOn[0] = 1
        rgJ[0] = grainHop
        rgStart[0] = wrapIndex(Int((vPos + d * ((rate - 1) * H - H)).rounded()), L)
        rgOn[1] = 1
        rgJ[1] = 0
        rgStart[1] = wrapIndex(Int((vPos + d * (rate - 1) * H).rounded()), L)
        readerTimer = grainHop
        writerReset = true
        needStretchInit = false
    }

    /// Tempo-changed playback: granular time-stretch (keep pitch) or varispeed.
    @inline(__always) private func renderStretched(_ L: Int, _ st: LoopState, _ inL: Float, _ inR: Float, _ rate: Double) -> (Float, Float) {
        let dir = reverse ? -1 : 1
        let G = grainLen
        if vPos >= Double(L) || vPos < 0 || vPos.isNaN { vPos = 0 }
        if needStretchInit { initStretch(L, rate, dir) }
        var sL: Float = 0
        var sR: Float = 0
        if stretchMode == .keepPitch {
            if readerTimer <= 0 {
                let slot = rgOn[0] == 0 ? 0 : (rgOn[1] == 0 ? 1 : 0)
                rgOn[slot] = 1
                rgJ[slot] = 0
                rgStart[slot] = wrapIndex(Int((vPos + Double(dir) * (rate - 1) * Double(grainHop)).rounded()), L)
                readerTimer += grainHop
            }
            readerTimer -= 1
            for g in 0..<2 where rgOn[g] != 0 {
                let j = rgJ[g]
                let m = mix(wrapIndex(rgStart[g] + dir * j, L))
                let w = window[j]
                sL += m.0 * w
                sR += m.1 * w
                if j + 1 >= G { rgOn[g] = 0 } else { rgJ[g] = j + 1 }
            }
        } else {
            let i0 = min(L - 1, Int(vPos))
            let i1 = wrapIndex(i0 + 1, L)
            let f = Float(vPos - Double(i0))
            let a = mix(i0)
            let b = mix(i1)
            sL = a.0 + (b.0 - a.0) * f
            sR = a.1 + (b.1 - a.1) * f
        }
        if st == .overdubbing && dubMode == .replace && !stopping {
            // replace mode: only the other tracks keep sounding
            sL = 0
            sR = 0
            if anySubContent {
                let m = mix(min(L - 1, max(0, Int(vPos))), main: false)
                sL = m.0
                sR = m.1
            }
        }
        if !stopping && tailRemaining == 0 {
            if st == .overdubbing { stretchedWrite(L, rate, dir, inL, inR) }
            let comp = Double(min(latencyFrames, L / 2))
            writeSubs(wrapIndex(Int((vPos - Double(dir) * rate * comp).rounded(.down)), L), L, inL, inR, stretched: true)
        }
        vPos += Double(dir) * rate
        var wrapped = false
        if vPos >= Double(L) {
            vPos -= Double(L)
            wrapped = true
        } else if vPos < 0 {
            vPos += Double(L)
            wrapped = true
        }
        playPos = min(L - 1, max(0, Int(vPos)))
        if wrapped { onWrap() }
        return (sL, sR)
    }

    /// Overdub while the tempo differs from the recorded tempo.
    /// Keep pitch: input is laid into the loop as overlapping windowed grains (inverse of the reader),
    /// so the overdub keeps its pitch and lines up when played back at the original tempo too.
    /// Varispeed: input is resampled into the loop (pitch follows the tempo, like tape).
    @inline(__always) private func stretchedWrite(_ L: Int, _ rate: Double, _ dir: Int, _ inL: Float, _ inR: Float) {
        if writerReset {
            for g in 0..<writerGrains { wgOn[g] = 0 }
            writerTimer = 0
            vLastWrite = -1
            writerReset = false
        }
        let comp = Double(min(latencyFrames, L / 2))
        if stretchMode == .keepPitch {
            let G = grainLen
            if writerTimer <= 0 {
                var slot = 0
                for g in 0..<writerGrains where wgOn[g] == 0 {
                    slot = g
                    break
                }
                wgOn[slot] = 1
                wgJ[slot] = 0
                wgStart[slot] = wrapIndex(Int((vPos + Double(dir) * ((rate - 1) * Double(grainHop) - rate * comp)).rounded()), L)
                writerTimer += Double(grainHop) / rate
            }
            writerTimer -= 1
            for g in 0..<writerGrains where wgOn[g] != 0 {
                let j = wgJ[g]
                let idx = wrapIndex(wgStart[g] + dir * j, L)
                let w = window[j]
                if dubMode == .overdub {
                    stack.write(idx, inL * w, inR * w, replace: false)
                } else if w >= 0.5 {
                    stack.write(idx, inL, inR, replace: true)
                }
                if j + 1 >= G { wgOn[g] = 0 } else { wgJ[g] = j + 1 }
            }
        } else {
            let target = wrapIndex(Int((vPos - Double(dir) * rate * comp).rounded(.down)), L)
            if vLastWrite < 0 {
                stack.write(target, inL, inR, replace: dubMode == .replace)
            } else {
                var d = (target - vLastWrite) * dir
                if d < 0 { d += L }
                if d > 16 {
                    stack.write(target, inL, inR, replace: dubMode == .replace)
                } else {
                    var k = 1
                    while k <= d {
                        stack.write(wrapIndex(vLastWrite + dir * k, L), inL, inR, replace: dubMode == .replace)
                        k += 1
                    }
                }
            }
            vLastWrite = target
        }
    }

    // MARK: Audio I/O (audio threads)

    /// Called from the input sink node. Converts to the engine sample rate and stores in the ring.
    func capture(frames n: Int, ch0: UnsafePointer<Float>, ch1: UnsafePointer<Float>?, stride: Int) {
        let step = inputSampleRate > 0 ? inputSampleRate / sampleRate : 1
        let mono = monoInput || ch1 == nil
        var w = ringWrite
        var i = 0
        while i < n {
            let xl = ch0[i * stride]
            let xr = mono ? xl : ch1![i * stride]
            if step == 1 {
                ringL[w & ringMask] = xl
                ringR[w & ringMask] = xr
                w += 1
            } else {
                while srcT < 1 {
                    let t = Float(srcT)
                    ringL[w & ringMask] = srcPrevL + (xl - srcPrevL) * t
                    ringR[w & ringMask] = srcPrevR + (xr - srcPrevR) * t
                    w += 1
                    srcT += step
                }
                srcT -= 1
                srcPrevL = xl
                srcPrevR = xr
            }
            i += 1
        }
        ringWrite = w
    }

    /// Called from the output source node.
    func render(frames n: Int, outL: UnsafeMutablePointer<Float>, outR: UnsafeMutablePointer<Float>) {
        if os_unfair_lock_trylock(lock) {
            drainLocked()
            os_unfair_lock_unlock(lock)
        }
        if jobDelay > 0 {
            jobDelay -= n
            if stack.doubling { stack.processJobs(budget: 1 << 17) }
        } else if stack.hasJobs {
            stack.processJobs(budget: 1 << 17)
        }
        anySubContent = false
        anySubWriting = false
        for tr in subs {
            if tr.stack.hasJobs { tr.stack.processJobs(budget: 1 << 15) }
            if tr.hasContent { anySubContent = true }
            if tr.state == .recording || tr.state == .overdubbing { anySubWriting = true }
        }
        if inputFX.tempo != tempo { inputFX.tempo = tempo }
        if loopFX.tempo != tempo { loopFX.tempo = tempo }
        rhythm.configure(tempo: tempo, pattern: patternIndex, variation: variation, kit: kitIndex, reverb: reverbLevel, humanize: humanize)
        if !rhythmOn && rhythmPreview { rhythmPreview = false }

        let wEnd = ringWrite
        if wEnd - ringRead > n + 4096 || wEnd < ringRead { ringRead = max(0, wEnd - n) }

        var rate = 1.0
        if loopLength > 0 && loopTempo > 0 { rate = min(2, max(0.5, tempo / loopTempo)) }
        let stretched = abs(rate - 1) > 0.002
        if stretched != wasStretched {
            if stretched { syncStretch() }
            wasStretched = stretched
        }
        playbackRate = stretched ? rate : 1

        let lvl = loopLevel
        let rl = rhythmLevel
        let mainTarget: Float = mainMuted ? 0 : 1
        let allTarget: Float = allMuted ? 0 : 1
        let mon = inputMonitor
        var inPk: Float = 0
        var inPkL: Float = 0
        var inPkR: Float = 0
        var outPk: Float = 0
        var rhythmWasRunning = false

        for i in 0..<n {
            var inL: Float = 0
            var inR: Float = 0
            if ringRead < wEnd {
                inL = ringL[ringRead & ringMask]
                inR = ringR[ringRead & ringMask]
                ringRead += 1
            }
            let ifx = inputFX.process(inL, inR)
            inL = ifx.0
            inR = ifx.1
            // track gains (smoothed mutes)
            if mainGain != mainTarget * lvl {
                let t = mainTarget * lvl
                mainGain = mainGain < t ? min(t, mainGain + muteStep) : max(t, mainGain - muteStep)
            }
            if allGain != allTarget { allGain = allGain < allTarget ? min(allTarget, allGain + muteStep) : max(allTarget, allGain - muteStep) }
            if anySubContent {
                var k = 0
                while k < LoopCore.subCount {
                    subs[k].tickGain()
                    k += 1
                }
            }
            let aL = abs(inL)
            let aR = abs(inR)
            if aL > inPkL { inPkL = aL }
            if aR > inPkR { inPkR = aR }
            let ia = max(aL, aR)
            if ia > inPk { inPk = ia }

            // Waiting states
            if state == .armed {
                countdown -= 1
                if countdown <= 0 { beginRecording() }
            } else if state == .autoRecArmed {
                if ia >= autoRecThreshold { beginRecording() }
            }

            var lpL: Float = 0
            var lpR: Float = 0
            let st = state
            if st == .recording {
                let w = recordPos - recComp
                if w >= 0 && w < capacity {
                    baseL[w] = inL
                    baseR[w] = inR
                }
                recordPos += 1
                if pendingEnd > 0 {
                    if recordPos >= pendingEnd { finalize(length: pendingEnd, next: pendingNext) }
                } else if recordPos >= capacity {
                    finalize(length: capacity, next: .playing)
                }
            } else if (st == .playing || st == .overdubbing) && loopLength > 0 {
                let L = loopLength
                let sm = stretched ? renderStretched(L, st, inL, inR, rate) : renderDirect(L, st, inL, inR)
                lpL = sm.0 * gain
                lpR = sm.1 * gain
                // fades
                if state == .playing || state == .overdubbing {
                    if gain != gainTarget {
                        if gain < gainTarget { gain = min(gainTarget, gain + gainStep) }
                        else { gain = max(gainTarget, gain - gainStep) }
                    } else if stopping && gain <= 0 {
                        enterStopped()
                    }
                }
            }

            // Tail capture after the first recording (latency compensation)
            if tailRemaining > 0 {
                if tailNext < loopLength {
                    baseL[tailNext] = inL
                    baseR[tailNext] = inR
                }
                tailNext += 1
                tailRemaining -= 1
            }

            // Rhythm
            // the rhythm engine also runs for the metronome count-in when the rhythm itself is off
            // Without a loop the rhythm only plays when started (rhythmPreview); with a loop it follows the transport.
            let waiting = state == .empty || state == .autoRecArmed
            var click = false
            if !rhythmOn && clickMode > 0 {
                click = state == .recording || state == .overdubbing || (clickMode == 2 && state == .playing)
                if click && rhythm.mode != .count { rhythm.startCount() }
            }
            let rActive = (rhythmOn && state != .stopped && (!waiting || rhythmPreview)) || (state == .armed && countingIn) || click
            let rs: (Float, Float) = rActive ? rhythm.tick() : rhythm.tail()
            if rActive { rhythmWasRunning = true }
            if endingPending && rhythm.consumeEndingDone() {
                // the ending's final hit just played: stop the loop with a short fade
                endingPending = false
                stopping = true
                gainTarget = 0
                gainStep = Float(1.0 / (0.012 * sampleRate))
            }
            var rg: Float = (state == .playing || state == .overdubbing) ? gain : 1
            if click { rg *= 0.55 }

            var lfL = lpL * allGain
            var lfR = lpR * allGain
            let fx = loopFX.process(lfL, lfR)
            lfL = fx.0
            lfR = fx.1
            var oL = lfL + rs.0 * rl * rg
            var oR = lfR + rs.1 * rl * rg
            if mon {
                oL += inL
                oR += inR
            }
            oL = max(-1, min(1, oL))
            oR = max(-1, min(1, oR))
            outL[i] = oL
            outR[i] = oR
            let oa = max(abs(oL), abs(oR))
            if oa > outPk { outPk = oa }
        }
        rhythmRunning = rhythmWasRunning
        inLevel = max(inPk, inLevel * 0.85)
        inLevelL = max(inPkL, inLevelL * 0.85)
        inLevelR = max(inPkR, inLevelR * 0.85)
        outLevel = max(outPk, outLevel * 0.85)
    }

    // MARK: Read access for UI / file export (main or background thread)

    func readMix(start: Int, count: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        stack.readMix(start: start, count: count, left: left, right: right)
    }

    func lanePeaks(at j: Int) -> (base: Float, dub: Float) { stack.lanePeaks(at: j) }

    @inline(__always) func peak(at j: Int) -> Float {
        guard j >= 0 && j < capacity else { return 0 }
        let m = stack.mix(j)
        return max(abs(m.0), abs(m.1))
    }
}
