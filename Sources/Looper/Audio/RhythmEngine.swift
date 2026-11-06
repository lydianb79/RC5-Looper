import Foundation

// All classes in this file run on the realtime audio thread: no allocation,
// no locks, no Swift arrays in the per-sample path.

/// Small Schroeder/Freeverb style stereo reverb used for the rhythm part.
final class Reverb {
    private let buf: UnsafeMutablePointer<Float>
    private let off: UnsafeMutablePointer<Int>
    private let len: UnsafeMutablePointer<Int>
    private let idx: UnsafeMutablePointer<Int>
    private let damp: UnsafeMutablePointer<Float>
    // 12 delay lines: 4 comb L, 4 comb R, 2 allpass L, 2 allpass R
    var feedback: Float = 0.84
    var damping: Float = 0.3

    init(sampleRate: Double) {
        let scale = sampleRate / 44100.0
        let base = [1116, 1188, 1277, 1356, 1116 + 23, 1188 + 23, 1277 + 23, 1356 + 23, 556, 441, 556 + 23, 441 + 23]
        let count = base.count
        let o = UnsafeMutablePointer<Int>.allocate(capacity: count)
        let l = UnsafeMutablePointer<Int>.allocate(capacity: count)
        let ix = UnsafeMutablePointer<Int>.allocate(capacity: count)
        let dp = UnsafeMutablePointer<Float>.allocate(capacity: count)
        var total = 0
        for i in 0..<count {
            let n = max(8, Int(Double(base[i]) * scale))
            o[i] = total
            l[i] = n
            ix[i] = 0
            dp[i] = 0
            total += n
        }
        let b = UnsafeMutablePointer<Float>.allocate(capacity: total)
        b.initialize(repeating: 0, count: total)
        off = o
        len = l
        idx = ix
        damp = dp
        buf = b
    }

    @inline(__always) private func comb(_ c: Int, _ x: Float) -> Float {
        let i = idx[c]
        let p = off[c] + i
        let y = buf[p]
        damp[c] = y * (1 - damping) + damp[c] * damping
        buf[p] = x + damp[c] * feedback
        idx[c] = (i + 1 == len[c]) ? 0 : i + 1
        return y
    }

    @inline(__always) private func allpass(_ a: Int, _ x: Float) -> Float {
        let i = idx[a]
        let p = off[a] + i
        let y = buf[p]
        buf[p] = x + y * 0.5
        idx[a] = (i + 1 == len[a]) ? 0 : i + 1
        return y - x
    }

    @inline(__always) func process(_ x: Float) -> (Float, Float) {
        var l: Float = 0
        var r: Float = 0
        l += comb(0, x); l += comb(1, x); l += comb(2, x); l += comb(3, x)
        r += comb(4, x); r += comb(5, x); r += comb(6, x); r += comb(7, x)
        l = allpass(8, l); l = allpass(9, l)
        r = allpass(10, r); r = allpass(11, r)
        return (l * 0.25, r * 0.25)
    }
}

/// Step sequencer that plays the pattern table through the drum synth.
final class RhythmEngine {
    let sampleRate: Double
    let synth: DrumSynth
    let patternCount: Int
    private let table: UnsafeMutablePointer<Float>
    private let steps: UnsafeMutablePointer<Int>
    private let beats: UnsafeMutablePointer<Double>
    private let swing: UnsafeMutablePointer<Double>

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

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        synth = DrumSynth(sampleRate: sampleRate)
        let defs = RhythmLibrary.patterns
        patternCount = defs.count
        table = RhythmLibrary.buildTable()
        steps = .allocate(capacity: defs.count)
        beats = .allocate(capacity: defs.count)
        swing = .allocate(capacity: defs.count)
        for (i, p) in defs.enumerated() {
            steps[i] = max(1, p.steps)
            beats[i] = p.beats
            swing[i] = p.swing
        }
        configure(tempo: 120, pattern: 0, variation: 0, kit: 0, reverb: 0.2)
        reset()
    }

    var currentBeatsPerMeasure: Double { beats[curPattern] }

    func configure(tempo: Double, pattern: Int, variation: Int, kit: Int, reverb: Float) {
        synth.prepare()
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
        activeVar = requestedVar
        nextTrigger = triggerFrame(0)
    }

    @inline(__always) private func triggerFrame(_ s: Int) -> Double {
        let idx = s % steps[curPattern]
        let sw = (idx & 1) == 1 ? swing[curPattern] : 0
        return (Double(s) + sw) * stepFrames
    }

    private func fire(_ s: Int) {
        let idx = s % steps[curPattern]
        if idx == 0 { activeVar = requestedVar }
        let base = (curPattern * 2 + activeVar) * kInstrumentCount * kMaxSteps
        for d in 0..<kInstrumentCount {
            let v = table[base + d * kMaxSteps + idx]
            if v > 0 { synth.trigger(d, v) }
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
