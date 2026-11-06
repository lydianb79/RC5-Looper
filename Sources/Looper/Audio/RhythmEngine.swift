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
    var feedback: Float = 0.82
    var damping: Float = 0.25

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

/// Fully synthesized drum kit (no samples needed).
final class DrumSynth {
    private let sr: Float
    private let invSr: Float
    private let n = kInstrumentCount
    private let env, envCoef, pEnv, pCoef, phase, phase2, vel, hpX, hpY, hpX2, hpY2, lp, t, panL, panR: UnsafeMutablePointer<Float>
    private let kits: UnsafeMutablePointer<KitParams>
    private let kitCount: Int
    private var kitIndex = 0
    private var rng: UInt32 = 0x9E3779B9
    let reverb: Reverb
    var reverbLevel: Float = 0.2

    init(sampleRate: Double) {
        sr = Float(sampleRate)
        invSr = 1 / Float(sampleRate)
        func make() -> UnsafeMutablePointer<Float> {
            let p = UnsafeMutablePointer<Float>.allocate(capacity: kInstrumentCount)
            p.initialize(repeating: 0, count: kInstrumentCount)
            return p
        }
        env = make(); envCoef = make(); pEnv = make(); pCoef = make(); phase = make(); phase2 = make()
        vel = make(); hpX = make(); hpY = make(); hpX2 = make(); hpY2 = make(); lp = make(); t = make()
        panL = make(); panR = make()
        let kc = RhythmLibrary.kits.count
        kitCount = kc
        let kp = UnsafeMutablePointer<KitParams>.allocate(capacity: kc)
        kp.initialize(from: RhythmLibrary.kits, count: kc)
        kits = kp
        reverb = Reverb(sampleRate: sampleRate)
        // all stored properties are initialized from here on
        let pans: [Float] = [0, 0, 0.25, 0.25, -0.3, 0.35, -0.25, 0.3, 0.05, 0, 0.4]
        for i in 0..<kInstrumentCount {
            let p = pans[i]
            panL[i] = 1 - max(0, p)
            panR[i] = 1 + min(0, p)
        }
    }

    func setKit(_ i: Int) { kitIndex = max(0, min(kitCount - 1, i)) }

    @inline(__always) private func noise() -> Float {
        rng ^= rng << 13
        rng ^= rng >> 17
        rng ^= rng << 5
        return Float(Int32(bitPattern: rng)) * (1.0 / 2147483648.0)
    }

    @inline(__always) private func hp(_ d: Int, _ x: Float, _ a: Float) -> Float {
        let y = a * (hpY[d] + x - hpX[d])
        hpX[d] = x
        hpY[d] = y
        return y
    }

    @inline(__always) private func hp2(_ d: Int, _ x: Float, _ a: Float) -> Float {
        let y = a * (hpY2[d] + x - hpX2[d])
        hpX2[d] = x
        hpY2[d] = y
        return y
    }

    func trigger(_ d: Int, _ v: Float) {
        guard d >= 0 && d < n else { return }
        let k = kits[kitIndex]
        vel[d] = v
        t[d] = 0
        env[d] = 1
        pEnv[d] = 1
        phase[d] = 0
        phase2[d] = 0
        var decay: Float = 0.1
        var pDecay: Float = 0.05
        switch d {
        case 0: decay = 0.35 * k.kickDecay; pDecay = 0.035
        case 1: decay = 0.16 * k.snareDecay; pDecay = 0.06
        case 2: decay = 0.045 * k.hatDecay; env[3] = 0   // closed hat chokes open hat
        case 3: decay = 0.35 * k.hatDecay
        case 4: decay = 1.1
        case 5: decay = 1.6
        case 6: decay = 0.28; pDecay = 0.08
        case 7: decay = 0.38; pDecay = 0.1
        case 8: decay = 0.018; pDecay = 0.004
        case 9: decay = 0.16
        default: decay = 0.07
        }
        envCoef[d] = expf(-1 / (decay * sr))
        pCoef[d] = expf(-1 / (pDecay * sr))
    }

    @inline(__always) private func osc(_ d: Int, _ f: Float) -> Float {
        var p = phase[d] + f * invSr
        if p >= 1 { p -= 1 }
        phase[d] = p
        return sinf(6.2831853 * p)
    }

    func next() -> (Float, Float) {
        var l: Float = 0
        var r: Float = 0
        var send: Float = 0
        let k = kits[kitIndex]
        let hatA: Float = 0.75 - 0.3 * k.brightness
        for d in 0..<n {
            let e = env[d]
            if e < 0.0002 { continue }
            let pe = pEnv[d]
            var s: Float = 0
            switch d {
            case 0:
                let pe2 = pe * pe
                let pe8 = pe2 * pe2 * pe2 * pe2
                s = osc(d, k.kickPitch * (46 + 150 * pe2)) + k.kickClick * pe8 * noise()
            case 1:
                let tone = osc(d, 185 * k.snareTone) * pe * 0.8
                let nz = hp(d, noise(), 0.7)
                s = tone * (1.1 - k.snareNoise * 0.5) + nz * k.snareNoise
            case 2, 3:
                let x1 = hp(d, noise(), hatA)
                s = hp2(d, x1, hatA) * (d == 2 ? 0.55 : 0.45)
            case 4:
                var p2 = phase2[d] + 4730 * invSr
                if p2 >= 1 { p2 -= 1 }
                phase2[d] = p2
                s = osc(d, 3120) * sinf(6.2831853 * p2) * 0.22 + hp(d, noise(), 0.6) * 0.18
            case 5:
                s = hp(d, noise(), 0.65) * 0.45
            case 6:
                s = osc(d, k.tomPitch * (170 + 110 * pe)) * 0.9
            case 7:
                s = osc(d, k.tomPitch * (95 + 70 * pe)) * 0.9
            case 8:
                s = osc(d, 1750) * 0.6 + noise() * 0.15 * pe
            case 9:
                let nz = hp(d, noise(), 0.75)
                lp[d] += 0.45 * (nz - lp[d])
                let tt = t[d] * invSr
                var gate: Float = 1
                if tt < 0.03 { gate = fmodf(tt, 0.01) < 0.004 ? 1 : 0.2 }
                s = lp[d] * gate * 1.6
            default:
                let att = min(1, t[d] * invSr / 0.012)
                s = hp(d, noise(), 0.5) * att * 0.5
            }
            s *= e * vel[d] * k.level
            env[d] = e * envCoef[d]
            pEnv[d] = pe * pCoef[d]
            t[d] += 1
            l += s * panL[d]
            r += s * panR[d]
            if d != 0 { send += s }
        }
        let wet = reverb.process(send * 0.12)
        l += wet.0 * reverbLevel
        r += wet.1 * reverbLevel
        return (l * 0.7, r * 0.7)
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
