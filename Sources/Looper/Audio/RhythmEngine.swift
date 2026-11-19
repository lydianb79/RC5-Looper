import Foundation

// All classes in this file run on the realtime audio thread: no allocation,
// no locks, no Swift arrays in the per-sample path.

/// Step sequencer that plays the pattern table through the drum synth, like a drummer
/// would: metric accents on the time-keeping parts, small timing and velocity deviations
/// per instrument, bar-to-bar dynamics, varied fills and a crash after each fill.
/// `humanize` = 0 gives the rigid drum-machine grid.
final class RhythmEngine {
    let sampleRate: Double
    let synth: DrumSynth
    let patternCount: Int
    private let table: UnsafeMutablePointer<Float>
    private let steps: UnsafeMutablePointer<Int>
    private let beats: UnsafeMutablePointer<Double>
    private let swing: UnsafeMutablePointer<Double>
    /// 0 = played by a drummer, 1 = programmed (tight timing), 2 = metronome (no humanizing)
    private let feelKind: UnsafeMutablePointer<Int>

    private(set) var frame = 0
    private var stepCount = 0
    private var nextTrigger = 0.0
    private(set) var stepFrames = 1.0
    private(set) var measureFrames = 1.0
    private(set) var beatFrames = 1.0
    private var curTempo = 0.0
    private var curPattern = 0
    private var activeVar = 0
    private var requestedVar = 0

    /// Special phrases (RC-5 style intro / ending).
    enum Mode { case normal, intro, count, ending, finished }
    private(set) var mode: Mode = .normal
    private var endingArmed = false
    /// Set when the ending's final hit has been played (read by LoopCore).
    private(set) var endingDone = false

    // groove
    private var humanize: Float = 0.6
    private var rng: UInt32 = 0x2545_F491
    private var barLevel: Float = 1
    private var barTarget: Float = 1
    private var crashNext = false
    private var fillKind = 0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        synth = DrumSynth(sampleRate: sampleRate)
        let defs = RhythmLibrary.patterns
        let count = RhythmLibrary.patternCount
        patternCount = count
        table = RhythmLibrary.buildTable()
        steps = .allocate(capacity: count)
        beats = .allocate(capacity: count)
        swing = .allocate(capacity: count)
        feelKind = .allocate(capacity: count)
        for i in 0..<count {
            steps[i] = 16
            beats[i] = 4
            swing[i] = 0
            feelKind[i] = 0
        }
        for (i, p) in defs.enumerated() {
            steps[i] = max(1, p.steps)
            beats[i] = p.beats
            swing[i] = p.swing
            feelKind[i] = p.category == "Metronome" ? 2 : (p.category == "Electronic" ? 1 : 0)
        }
        for (slot, u) in UserPatternStore.shared.items.enumerated() {
            guard let u else { continue }
            let i = RhythmLibrary.builtinCount + slot
            steps[i] = max(1, min(kMaxSteps, u.steps))
            beats[i] = max(0.5, u.beats)
            swing[i] = u.swing
        }
        configure(tempo: 120, pattern: 0, variation: 0, kit: 0, reverb: 0.2, humanize: 0.6)
        reset()
    }

    var currentBeatsPerMeasure: Double { beats[curPattern] }

    /// Velocity of one grid cell (read-only table, safe from the main thread).
    func cell(pattern: Int, variation: Int, drum: Int, step: Int) -> Float {
        guard pattern >= 0 && pattern < patternCount, drum >= 0 && drum < kInstrumentCount, step >= 0 && step < kMaxSteps else { return 0 }
        return table[((pattern * 2 + (variation == 0 ? 0 : 1)) * kInstrumentCount + drum) * kMaxSteps + step]
    }

    /// Pattern editor: sets one grid cell (main thread; a single float store is safe for the audio thread).
    func setCell(pattern: Int, variation: Int, drum: Int, step: Int, value: Float) {
        guard pattern >= 0 && pattern < patternCount, drum >= 0 && drum < kInstrumentCount, step >= 0 && step < kMaxSteps else { return }
        table[((pattern * 2 + (variation == 0 ? 0 : 1)) * kInstrumentCount + drum) * kMaxSteps + step] = value
    }

    /// Loads (or clears) a user pattern slot.
    func loadUser(slot: Int, _ u: UserPattern?) {
        let i = RhythmLibrary.builtinCount + slot
        guard i >= RhythmLibrary.builtinCount && i < patternCount else { return }
        let per = kInstrumentCount * kMaxSteps
        if let u {
            RhythmLibrary.writeUser(u, into: table + i * 2 * per)
            steps[i] = max(1, min(kMaxSteps, u.steps))
            beats[i] = max(0.5, u.beats)
            swing[i] = u.swing
        } else {
            (table + i * 2 * per).update(repeating: 0, count: 2 * per)
        }
        if i == curPattern { curTempo = 0 }      // re-derive the step timing on the next configure
    }

    func configure(tempo: Double, pattern: Int, variation: Int, kit: Int, reverb: Float, humanize h: Float = 0.6) {
        synth.prepare()
        humanize = max(0, min(1, h))
        requestedVar = variation == 0 ? 0 : 1
        synth.setKit(kit)
        synth.reverbLevel = reverb
        let p = max(0, min(patternCount - 1, pattern))
        let tp = max(30, min(300, tempo))
        if tp != curTempo || p != curPattern {
            curTempo = tp
            curPattern = p
            beatFrames = 60.0 / tp * sampleRate
            measureFrames = beats[p] * beatFrames
            stepFrames = measureFrames / Double(steps[p])
            stepCount = frame == 0 ? 0 : Int(Double(frame) / stepFrames) + 1
            nextTrigger = triggerFrame(stepCount)
        }
    }

    func reset() {
        frame = 0
        stepCount = 0
        crashNext = false
        barLevel = 1
        barTarget = 1
        activeVar = requestedVar
        nextTrigger = triggerFrame(0)
    }

    @inline(__always) private func triggerFrame(_ s: Int) -> Double {
        let idx = s % steps[curPattern]
        let sw = (idx & 1) == 1 ? swing[curPattern] : 0
        return (Double(s) + sw) * stepFrames
    }

    func startIntro() { mode = .intro }

    /// Metronome count-in (used when the rhythm itself is off).
    func startCount() { mode = .count }

    func requestEnding() {
        guard mode == .normal || mode == .intro else { return }
        mode = .ending
        endingArmed = false
        endingDone = false
    }

    func cancelSpecial() {
        mode = .normal
        endingArmed = false
        endingDone = false
    }

    func consumeEndingDone() -> Bool {
        guard endingDone else { return false }
        endingDone = false
        return true
    }

    // MARK: Groove

    @inline(__always) private func rnd() -> Float {
        rng ^= rng << 13
        rng ^= rng >> 17
        rng ^= rng << 5
        return Float(rng) / Float(UInt32.max)
    }

    /// Roughly normal, mean 0, standard deviation 1.
    @inline(__always) private func gauss() -> Float {
        (rnd() + rnd() + rnd() - 1.5) * 2
    }

    /// Relative strength of a grid position inside the beat (down-beat, off-beat, in-between).
    @inline(__always) private func accent(_ pos: Int, _ spb: Int) -> Float {
        if pos == 0 { return 1 }
        if spb % 3 == 0 && spb / 3 > 0 {
            let third = spb / 3
            if pos % third == 0 { return pos / third == 2 ? 0.86 : 0.76 }
            return 0.7
        }
        if spb % 2 == 0 && pos * 2 == spb { return 0.84 }
        return 0.72
    }

    /// Timing per instrument: (average lateness, spread) in milliseconds at full humanize.
    @inline(__always) private func timing(_ d: Int) -> (Float, Float) {
        switch d {
        case Drum.kick: return (2.5, 1.5)
        case Drum.snare: return (4.0, 2.0)
        case Drum.hatClosed, Drum.hatOpen, Drum.hatPedal, Drum.hatLoose: return (3.0, 2.4)
        case Drum.ride, Drum.rideBell: return (3.0, 2.2)
        case Drum.crash: return (3.0, 2.0)
        case Drum.tomHi, Drum.tomMid, Drum.tomLo: return (3.5, 2.6)
        case Drum.shaker: return (3.0, 3.0)
        default: return (3.0, 1.8)
        }
    }

    /// Plays one hit with the drummer's feel applied.
    private func hit(_ d: Int, _ v: Float, pos: Int, spb: Int, downbeat: Bool = false) {
        let kind = feelKind[curPattern]
        let h: Float = kind == 2 ? 0 : humanize
        var vel = v
        if v >= 0.95 {
            let shape = min(1, h * 1.6)
            switch d {
            case Drum.hatClosed, Drum.hatOpen, Drum.ride, Drum.shaker, Drum.hatPedal:
                vel *= 1 + (accent(pos, spb) - 1) * shape
            case Drum.kick, Drum.snare:
                vel *= downbeat ? 1 : 1 - 0.05 * shape
            default: break
            }
        }
        if vel < 0.4 {
            vel += gauss() * 0.035 * h                 // ghost notes vary a lot in level
        } else {
            vel *= 1 + gauss() * 0.045 * h
        }
        vel *= barLevel
        let (late, spread) = timing(d)
        let ms = h * (kind == 1 ? 0.3 : 1) * (late + gauss() * spread)
        let delay = Int(Double(max(0, min(14, ms))) * 0.001 * sampleRate)
        synth.trigger(d, max(0.02, min(1, vel)), delay: delay)
    }

    /// Drum of a fill template at one of four slots across the last beat.
    @inline(__always) private func fillDrum(_ kind: Int, _ slot: Int) -> Int {
        switch kind {
        case 0: return Drum.snare
        case 1: return slot < 2 ? Drum.snare : (slot == 2 ? Drum.tomHi : Drum.tomMid)
        case 2: return slot == 0 ? Drum.tomHi : (slot == 1 ? Drum.tomMid : Drum.tomLo)
        default: return slot == 0 ? Drum.snare : (slot == 1 ? Drum.tomHi : (slot == 2 ? Drum.tomMid : Drum.tomLo))
        }
    }

    /// One step of a drum fill inside the last beat of the bar (k = step within the beat).
    private func playFill(_ k: Int, _ spb: Int) {
        if k == 0 {
            fillKind = mode == .intro ? 0 : Int(rnd() * 4) % 4
            hit(Drum.kick, 0.85, pos: 0, spb: spb)
        }
        let slot = min(3, k * 4 / max(1, spb))
        let vel = 0.6 + 0.4 * Float(k + 1) / Float(max(1, spb))
        hit(fillDrum(fillKind, slot), vel, pos: k, spb: spb)
        if mode != .ending { crashNext = true }
    }

    private func fire(_ s: Int) {
        let n = steps[curPattern]
        let idx = s % n
        let spb = max(1, Int((Double(n) / max(0.5, beats[curPattern])).rounded()))
        let fillStart = n - spb
        let pos = idx % spb
        if idx == 0 {
            if mode == .ending && endingArmed {
                // final hit on the downbeat, then the rhythm stops
                hit(Drum.crash, 1.0, pos: 0, spb: spb, downbeat: true)
                hit(Drum.kick, 1.0, pos: 0, spb: spb, downbeat: true)
                mode = .finished
                endingDone = true
                return
            }
            activeVar = requestedVar
            barTarget = 1 + gauss() * 0.03 * humanize
        }
        barLevel += (barTarget - barLevel) * 0.2
        if mode == .finished { return }
        if mode == .count {
            // metronome count: accented click on beat 1, softer clicks on the other beats
            if pos == 0 { synth.trigger(Drum.stick, idx == 0 ? 1.0 : 0.62) }
            return
        }
        if mode == .ending { endingArmed = true }
        // fills: intro bar, ending bar, and when switching variation A <-> B
        let wantsFill = mode == .ending || mode == .intro || requestedVar != activeVar
        if wantsFill && spb >= 2 && idx >= fillStart {
            playFill(idx - fillStart, spb)
            return
        }
        if mode == .intro {
            // count-in with sticks and the hi-hat pedal on every beat
            if pos == 0 {
                hit(Drum.stick, idx == 0 ? 1.0 : 0.75, pos: 0, spb: spb)
                hit(Drum.hatPedal, 0.7, pos: 0, spb: spb)
            }
            return
        }
        var crashed = false
        if idx == 0 && crashNext {
            crashNext = false
            crashed = true
            hit(Drum.crash, 0.92, pos: 0, spb: spb, downbeat: true)
        }
        let base = (curPattern * 2 + activeVar) * kInstrumentCount * kMaxSteps
        for d in 0..<kInstrumentCount {
            let v = table[base + d * kMaxSteps + idx]
            if v <= 0 { continue }
            // the crash replaces the time-keeping cymbal on its down-beat
            if crashed && (d == Drum.hatClosed || d == Drum.ride || d == Drum.crash) { continue }
            hit(d, v, pos: pos, spb: spb, downbeat: idx == 0)
        }
        if crashed && table[base + Drum.kick * kMaxSteps] <= 0 {
            hit(Drum.kick, 0.9, pos: 0, spb: spb, downbeat: true)
        }
    }

    /// Advance one sample while the rhythm is running.
    @inline(__always) func tick() -> (Float, Float) {
        while Double(frame) >= nextTrigger {
            fire(stepCount)
            stepCount += 1
            nextTrigger = triggerFrame(stepCount)
        }
        frame += 1
        return synth.next()
    }

    /// Let ringing voices decay while the rhythm is stopped.
    @inline(__always) func tail() -> (Float, Float) {
        synth.next()
    }
}
