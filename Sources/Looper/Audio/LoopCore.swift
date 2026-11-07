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
}

/// The realtime looper engine.
///
/// Audio layout: the loop is `base + layerA + layerB`.
/// * The first recording is written into `base`.
/// * Each overdub goes into its own layer, so the latest overdub can be
///   undone / redone by muting the layer (like the RC-5's UNDO/REDO).
/// * When a new overdub starts, the previous layer is merged into `base`
///   incrementally on the audio thread (a few hundred thousand samples per
///   callback) so no large copy ever blocks the audio thread.
/// * Replace mode stores `input - (base + other)` in the layer, so even
///   replacing is undoable.
final class LoopCore {
    let sampleRate: Double
    let capacity: Int

    let baseL: UnsafeMutablePointer<Float>
    let baseR: UnsafeMutablePointer<Float>
    private let layAL: UnsafeMutablePointer<Float>
    private let layAR: UnsafeMutablePointer<Float>
    private let layBL: UnsafeMutablePointer<Float>
    private let layBR: UnsafeMutablePointer<Float>

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
    var inputSampleRate: Double = 0
    var inputLeftChannel = 0
    var inputRightChannel = 1
    /// Tempo the loop was recorded at. Playback rate = tempo / loopTempo (RC-5 style live tempo).
    var loopTempo: Double = 0
    var stretchMode: StretchMode = .keepPitch

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
    private(set) var currentLayer = -1
    private(set) var currentLayerActive = false
    private(set) var rhythmRunning = false
    private(set) var recordedWithRhythm = false
    private(set) var inLevel: Float = 0
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
    private var g0: Float = 0
    private var g1: Float = 0
    private var dubPrevLayer = -1
    private var dubPrevActive = false
    private var jobDelay = 0
    private let jobActive: UnsafeMutablePointer<Int>
    private let jobMerge: UnsafeMutablePointer<Int>
    private let jobCursor: UnsafeMutablePointer<Int>
    private let jobEnd: UnsafeMutablePointer<Int>
    private let usedLen: UnsafeMutablePointer<Int>

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
        baseL = buffer(cap); baseR = buffer(cap)
        layAL = buffer(cap); layAR = buffer(cap)
        layBL = buffer(cap); layBR = buffer(cap)
        ringL = buffer(1 << 15); ringR = buffer(1 << 15)
        ringMask = (1 << 15) - 1
        func ints(_ count: Int = 2) -> UnsafeMutablePointer<Int> {
            let p = UnsafeMutablePointer<Int>.allocate(capacity: count)
            p.initialize(repeating: 0, count: count)
            return p
        }
        jobActive = ints(); jobMerge = ints(); jobCursor = ints(); jobEnd = ints(); usedLen = ints()
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
            if state == .armed || state == .autoRecArmed { state = .empty }
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
                    syncStretch()
                    rhythm.reset()
                }
            }
        case .stop: requestStop()
        case .toggleUndo: toggleUndo()
        case .clear: clearAll()
        case .resetRhythm: rhythm.reset()
        case .setLoaded(let len):
            if state == .empty {
                loopLength = max(0, min(len, capacity))
                state = loopLength > 0 ? .stopped : .empty
                playPos = 0
                syncStretch()
                currentLayer = -1
                currentLayerActive = false
                tailRemaining = 0
                updateGains()
                loopGeneration &+= 1
            }
        }
    }

    // MARK: Transport logic (audio thread)

    private func armRecording() {
        guard state == .empty else { return }
        if rhythmOn {
            let mf = rhythm.measureFrames
            if countIn || rhythmIntro {
                rhythm.reset()
                rhythm.cancelSpecial()
                if rhythmIntro { rhythm.startIntro() }
                countdown = Int(mf.rounded())
                state = .armed
                return
            }
            if quantize {
                // Rhythm is free running in the empty state: start on the next bar line.
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
        loopLength = 0
        currentLayer = -1
        currentLayerActive = false
        stopping = false
        stopAtWrap = false
        updateGains()
        rhythm.reset()
        rhythm.cancelSpecial()
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
        let L = loopLength
        dubPrevLayer = currentLayer
        dubPrevActive = currentLayerActive
        if currentLayer >= 0 {
            // Commit (or throw away, if it was undone) the previous overdub.
            scheduleJob(currentLayer, merge: currentLayerActive, end: L)
        }
        let next = currentLayer == 0 ? 1 : 0
        if jobActive[next] != 0 { finishJob(next) }
        currentLayer = next
        currentLayerActive = true
        usedLen[next] = L
        writerReset = true
        // Grace period: lets a double-press / long-press cancel this dub
        // before the previous layer is committed.
        jobDelay = Int(2.5 * sampleRate)
        state = .overdubbing
        updateGains()
        loopGeneration &+= 1
    }

    private func abortDub() {
        guard state == .overdubbing else { return }
        let prev = dubPrevLayer
        let prevUntouched = prev < 0 || (jobActive[prev] != 0 && jobCursor[prev] == 0)
        if jobDelay > 0 && prevUntouched {
            if prev >= 0 { jobActive[prev] = 0 }
            let newLayer = currentLayer
            currentLayer = prev
            currentLayerActive = dubPrevActive
            if newLayer >= 0 { scheduleJob(newLayer, merge: false, end: loopLength) }
        }
        state = .playing
        updateGains()
        loopGeneration &+= 1
    }

    private func toggleUndo() {
        guard currentLayer >= 0 && loopLength > 0 else { return }
        if state == .overdubbing {
            state = .playing
            currentLayerActive = false
        } else {
            currentLayerActive.toggle()
        }
        updateGains()
        loopGeneration &+= 1
    }

    private func startPlay() {
        state = .playing
        stopping = false
        stopAtWrap = false
        playPos = reverse ? loopLength - 1 : 0
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
        case .armed, .autoRecArmed:
            state = .empty
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
        default:
            break
        }
    }

    private func enterStopped() {
        endingPending = false
        state = .stopped
        stopping = false
        stopAtWrap = false
        gain = 0
        gainTarget = 0
        playPos = reverse ? max(0, loopLength - 1) : 0
        syncStretch()
    }

    private func clearAll() {
        for li in 0..<2 {
            if jobActive[li] != 0 {
                jobMerge[li] = 0
                jobEnd[li] = max(jobEnd[li], usedLen[li])
            } else if usedLen[li] > 0 {
                jobActive[li] = 1
                jobMerge[li] = 0
                jobCursor[li] = 0
                jobEnd[li] = usedLen[li]
            }
        }
        jobDelay = 0
        currentLayer = -1
        currentLayerActive = false
        state = .empty
        loopLength = 0
        loopTempo = 0
        endingPending = false
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
        updateGains()
        loopGeneration &+= 1
    }

    private func loopWrapped() {
        playPos = reverse ? loopLength - 1 : 0
        onWrap()
    }

    private func onWrap() {
        rhythm.reset()
        if oneShot || stopAtWrap { enterStopped() }
    }

    private func syncStretch() {
        vPos = Double(playPos)
        needStretchInit = true
        writerReset = true
    }

    // MARK: Playback paths

    @inline(__always) private func mix(_ i: Int) -> (Float, Float) {
        var l = baseL[i]
        var r = baseR[i]
        if g0 != 0 { l += layAL[i]; r += layAR[i] }
        if g1 != 0 { l += layBL[i]; r += layBR[i] }
        return (l, r)
    }

    @inline(__always) private func wrapIndex(_ x: Int, _ L: Int) -> Int {
        var i = x % L
        if i < 0 { i += L }
        return i
    }

    /// Original-tempo playback (sample exact).
    @inline(__always) private func renderDirect(_ L: Int, _ st: LoopState, _ inL: Float, _ inR: Float) -> (Float, Float) {
        let p = min(max(0, playPos), L - 1)
        var s = mix(p)
        if st == .overdubbing && dubMode == .replace && !stopping { s = (0, 0) }
        if st == .overdubbing && !stopping && tailRemaining == 0 {
            let comp = min(latencyFrames, L / 2)
            var w = reverse ? p + comp : p - comp
            if w >= L { w -= L } else if w < 0 { w += L }
            writeDub(w, inL, inR)
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
            sL = 0
            sR = 0
        }
        if st == .overdubbing && !stopping && tailRemaining == 0 {
            stretchedWrite(L, rate, dir, inL, inR)
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
                    writeDub(idx, inL * w, inR * w)
                } else if w >= 0.5 {
                    writeDub(idx, inL, inR)
                }
                if j + 1 >= G { wgOn[g] = 0 } else { wgJ[g] = j + 1 }
            }
        } else {
            let target = wrapIndex(Int((vPos - Double(dir) * rate * comp).rounded(.down)), L)
            if vLastWrite < 0 {
                writeDub(target, inL, inR)
            } else {
                var d = (target - vLastWrite) * dir
                if d < 0 { d += L }
                if d > 16 {
                    writeDub(target, inL, inR)
                } else {
                    var k = 1
                    while k <= d {
                        writeDub(wrapIndex(vLastWrite + dir * k, L), inL, inR)
                        k += 1
                    }
                }
            }
            vLastWrite = target
        }
    }

    // MARK: Layer jobs

    private func updateGains() {
        g0 = ((currentLayer == 0 && currentLayerActive) || (jobActive[0] != 0 && jobMerge[0] != 0)) ? 1 : 0
        g1 = ((currentLayer == 1 && currentLayerActive) || (jobActive[1] != 0 && jobMerge[1] != 0)) ? 1 : 0
    }

    private func scheduleJob(_ li: Int, merge: Bool, end: Int) {
        if jobActive[li] != 0 { finishJob(li) }
        jobActive[li] = 1
        jobMerge[li] = merge ? 1 : 0
        jobCursor[li] = 0
        jobEnd[li] = end
        updateGains()
    }

    @discardableResult
    private func runJob(_ li: Int, budget: Int) -> Int {
        let start = jobCursor[li]
        let end = min(jobEnd[li], start + budget)
        let l = li == 0 ? layAL : layBL
        let r = li == 0 ? layAR : layBR
        var j = start
        if jobMerge[li] != 0 {
            while j < end {
                baseL[j] += l[j]
                baseR[j] += r[j]
                l[j] = 0
                r[j] = 0
                j += 1
            }
        } else {
            while j < end {
                l[j] = 0
                r[j] = 0
                j += 1
            }
        }
        jobCursor[li] = end
        if end >= jobEnd[li] {
            jobActive[li] = 0
            usedLen[li] = 0
            updateGains()
        }
        return end - start
    }

    private func finishJob(_ li: Int) {
        while jobActive[li] != 0 { runJob(li, budget: Int.max / 4) }
    }

    private func processJobs(budget: Int) {
        var b = budget
        for li in 0..<2 where jobActive[li] != 0 && b > 0 {
            b -= runJob(li, budget: b)
        }
    }

    @inline(__always) private func writeDub(_ w: Int, _ xl: Float, _ xr: Float) {
        let cl = currentLayer == 0 ? layAL : layBL
        let cr = currentLayer == 0 ? layAR : layBR
        if dubMode == .overdub {
            cl[w] += xl
            cr[w] += xr
        } else {
            let og: Float = currentLayer == 0 ? g1 : g0
            let ol = currentLayer == 0 ? layBL : layAL
            let orr = currentLayer == 0 ? layBR : layAR
            cl[w] = xl - (baseL[w] + og * ol[w])
            cr[w] = xr - (baseR[w] + og * orr[w])
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
        } else if jobActive[0] != 0 || jobActive[1] != 0 {
            processJobs(budget: 1 << 17)
        }
        rhythm.configure(tempo: tempo, pattern: patternIndex, variation: variation, kit: kitIndex, reverb: reverbLevel)

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
        let mon = inputMonitor
        var inPk: Float = 0
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
            let ia = max(abs(inL), abs(inR))
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
            let rActive = rhythmOn && state != .stopped
            let rs: (Float, Float) = rActive ? rhythm.tick() : rhythm.tail()
            if rActive { rhythmWasRunning = true }
            if endingPending && rhythm.consumeEndingDone() {
                // the ending's final hit just played: stop the loop with a short fade
                endingPending = false
                stopping = true
                gainTarget = 0
                gainStep = Float(1.0 / (0.012 * sampleRate))
            }
            let rg: Float = (state == .playing || state == .overdubbing) ? gain : 1

            var oL = lpL * lvl + rs.0 * rl * rg
            var oR = lpR * lvl + rs.1 * rl * rg
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
        outLevel = max(outPk, outLevel * 0.85)
    }

    // MARK: Read access for UI / file export (main or background thread)

    func readMix(start: Int, count: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        let a0 = g0
        let a1 = g1
        var i = 0
        while i < count {
            let j = start + i
            if j < capacity {
                left[i] = baseL[j] + a0 * layAL[j] + a1 * layBL[j]
                right[i] = baseR[j] + a0 * layAR[j] + a1 * layBR[j]
            } else {
                left[i] = 0
                right[i] = 0
            }
            i += 1
        }
    }

    @inline(__always) func peak(at j: Int) -> Float {
        guard j >= 0 && j < capacity else { return 0 }
        let l = baseL[j] + g0 * layAL[j] + g1 * layBL[j]
        let r = baseR[j] + g0 * layAR[j] + g1 * layBR[j]
        return max(abs(l), abs(r))
    }
}
