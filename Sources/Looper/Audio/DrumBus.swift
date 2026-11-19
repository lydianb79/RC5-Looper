import Foundation

// Drum bus processing. Runs on the realtime audio thread: no allocation after init.

/// Small-room reverb: pre-delay, stereo early reflections and an 8-line feedback delay
/// network (Hadamard mixing, per-line damping). Much smoother and less metallic than a
/// comb-filter reverb, so the kit sounds like it was recorded in a room.
final class RoomReverb {
    private static let lineMs: [Double] = [31.7, 37.3, 41.9, 47.3, 53.1, 59.9, 67.1, 73.3]
    private static let tapMsL: [Double] = [7.1, 11.3, 16.9, 23.7, 31.1, 37.9]
    private static let tapMsR: [Double] = [8.3, 13.7, 19.1, 26.3, 33.5, 41.3]
    private static let tapGain: [Float] = [0.62, -0.5, 0.42, -0.34, 0.28, -0.22]

    private let sr: Double
    private let lines: UnsafeMutablePointer<Float>
    private let lineOff: UnsafeMutablePointer<Int>
    private let lineLen: UnsafeMutablePointer<Int>
    private let lineIdx: UnsafeMutablePointer<Int>
    private let fb: UnsafeMutablePointer<Float>
    private let lp: UnsafeMutablePointer<Float>
    private let pre: UnsafeMutablePointer<Float>
    private let preLen: Int
    private var preIdx = 0
    private let tapL: UnsafeMutablePointer<Int>
    private let tapR: UnsafeMutablePointer<Int>
    private let tapG: UnsafeMutablePointer<Float>
    private let preTap: Int
    private let ap: UnsafeMutablePointer<Float>
    private let apLen: (Int, Int)
    private var apIdx = (0, 0)
    private var inLP: Float = 0
    var damping: Float = 0.38

    init(sampleRate: Double) {
        sr = sampleRate
        let n = RoomReverb.lineMs.count
        let off = UnsafeMutablePointer<Int>.allocate(capacity: n)
        let len = UnsafeMutablePointer<Int>.allocate(capacity: n)
        var total = 0
        for i in 0..<n {
            let l = max(16, Int(RoomReverb.lineMs[i] * 0.001 * sampleRate))
            off[i] = total
            len[i] = l
            total += l
        }
        let buf = UnsafeMutablePointer<Float>.allocate(capacity: total)
        buf.initialize(repeating: 0, count: total)
        func ints(_ c: Int) -> UnsafeMutablePointer<Int> {
            let p = UnsafeMutablePointer<Int>.allocate(capacity: c)
            p.initialize(repeating: 0, count: c)
            return p
        }
        func floats(_ c: Int, _ x: Float = 0) -> UnsafeMutablePointer<Float> {
            let p = UnsafeMutablePointer<Float>.allocate(capacity: c)
            p.initialize(repeating: x, count: c)
            return p
        }
        let pl = Int(0.06 * sampleRate)
        let tl = ints(6), tr = ints(6), tg = floats(6)
        for i in 0..<6 {
            tl[i] = min(pl - 1, Int(RoomReverb.tapMsL[i] * 0.001 * sampleRate))
            tr[i] = min(pl - 1, Int(RoomReverb.tapMsR[i] * 0.001 * sampleRate))
            tg[i] = RoomReverb.tapGain[i]
        }
        let a0 = max(8, Int(0.0047 * sampleRate))
        let a1 = max(8, Int(0.0031 * sampleRate))
        lines = buf
        lineOff = off
        lineLen = len
        lineIdx = ints(n)
        fb = floats(n, 0.7)
        lp = floats(n)
        preLen = pl
        pre = floats(pl)
        tapL = tl
        tapR = tr
        tapG = tg
        preTap = min(pl - 1, Int(0.012 * sampleRate))
        apLen = (a0, a1)
        ap = floats(a0 + a1)
        setDecay(0.6)
    }

    /// Reverb time (RT60) in seconds.
    func setDecay(_ rt60: Double) {
        for i in 0..<RoomReverb.lineMs.count {
            fb[i] = Float(pow(10, -3 * Double(lineLen[i]) / (max(0.1, rt60) * sr)))
        }
    }

    @inline(__always) private func readPre(_ delay: Int) -> Float {
        var j = preIdx - delay
        if j < 0 { j += preLen }
        return pre[j]
    }

    @inline(__always) func process(_ x: Float) -> (Float, Float) {
        // darken the input a little: rooms absorb the top end
        inLP += (x - inLP) * 0.45
        pre[preIdx] = inLP
        var el: Float = 0
        var er: Float = 0
        for i in 0..<6 {
            el += readPre(tapL[i]) * tapG[i]
            er += readPre(tapR[i]) * tapG[i]
        }
        var d = readPre(preTap)
        preIdx += 1
        if preIdx == preLen { preIdx = 0 }

        // two series allpass diffusers
        do {
            let y = ap[apIdx.0]
            let v = d + y * 0.6
            ap[apIdx.0] = v
            d = y - v * 0.6
            apIdx.0 += 1
            if apIdx.0 == apLen.0 { apIdx.0 = 0 }
        }
        do {
            let y = ap[apLen.0 + apIdx.1]
            let v = d + y * 0.6
            ap[apLen.0 + apIdx.1] = v
            d = y - v * 0.6
            apIdx.1 += 1
            if apIdx.1 == apLen.1 { apIdx.1 = 0 }
        }

        // FDN: read, damp, scale
        @inline(__always) func tap(_ i: Int) -> Float {
            let y = lines[lineOff[i] + lineIdx[i]]
            lp[i] = y * (1 - damping) + lp[i] * damping
            return lp[i] * fb[i]
        }
        let s0 = tap(0), s1 = tap(1), s2 = tap(2), s3 = tap(3)
        let s4 = tap(4), s5 = tap(5), s6 = tap(6), s7 = tap(7)
        let outL = s0 + s2 + s4 + s6
        let outR = s1 + s3 + s5 + s7
        // 8-point Hadamard (orthogonal, energy preserving)
        var a0 = s0 + s1, a1 = s0 - s1, a2 = s2 + s3, a3 = s2 - s3
        var a4 = s4 + s5, a5 = s4 - s5, a6 = s6 + s7, a7 = s6 - s7
        let b0 = a0 + a2, b2 = a0 - a2, b1 = a1 + a3, b3 = a1 - a3
        let b4 = a4 + a6, b6 = a4 - a6, b5 = a5 + a7, b7 = a5 - a7
        let k: Float = 0.353_553_4
        a0 = (b0 + b4) * k; a4 = (b0 - b4) * k
        a1 = (b1 + b5) * k; a5 = (b1 - b5) * k
        a2 = (b2 + b6) * k; a6 = (b2 - b6) * k
        a3 = (b3 + b7) * k; a7 = (b3 - b7) * k
        @inline(__always) func write(_ i: Int, _ v: Float) {
            lines[lineOff[i] + lineIdx[i]] = v
            let j = lineIdx[i] + 1
            lineIdx[i] = j == lineLen[i] ? 0 : j
        }
        write(0, a0 + d); write(1, a1 - d); write(2, a2 + d); write(3, a3 - d)
        write(4, a4 + d); write(5, a5 - d); write(6, a6 + d); write(7, a7 - d)
        return (el * 0.5 + outL * 0.32, er * 0.5 + outR * 0.32)
    }
}

/// Gentle stereo-linked glue compressor with soft knee, followed by a soft clipper.
struct BusCompressor {
    private var env: Float = 0
    private var gain: Float = 1
    private let atk: Float
    private let rel: Float
    private let gainAtk: Float
    private let gainRel: Float
    var thresholdDB: Float = -15
    var ratio: Float = 2.6
    var kneeDB: Float = 8
    var makeupDB: Float = 2.5

    init(sampleRate: Double) {
        atk = Float(exp(-1 / (0.0008 * sampleRate)))
        rel = Float(exp(-1 / (0.09 * sampleRate)))
        gainAtk = Float(exp(-1 / (0.006 * sampleRate)))
        gainRel = Float(exp(-1 / (0.14 * sampleRate)))
    }

    @inline(__always) mutating func process(_ l: Float, _ r: Float) -> (Float, Float) {
        let x = max(abs(l), abs(r))
        env = x > env ? atk * env + (1 - atk) * x : rel * env + (1 - rel) * x
        let db = 20 * log10f(env + 1e-9)
        let over = db - thresholdDB
        var reduce: Float = 0
        if over > kneeDB / 2 {
            reduce = over * (1 - 1 / ratio)
        } else if over > -kneeDB / 2 {
            let t = over + kneeDB / 2
            reduce = (1 - 1 / ratio) * t * t / (2 * kneeDB)
        }
        let target = powf(10, (makeupDB - reduce) / 20)
        let c = target < gain ? gainAtk : gainRel
        gain = c * gain + (1 - c) * target
        return (soft(l * gain), soft(r * gain))
    }

    @inline(__always) private func soft(_ x: Float) -> Float {
        let a = abs(x)
        if a <= 0.8 { return x }
        let y = 0.8 + 0.2 * tanhf((a - 0.8) / 0.2)
        return x < 0 ? -y : y
    }
}
