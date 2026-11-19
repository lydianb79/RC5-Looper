import AVFoundation
import Foundation
import os

// Sample-based drum engine.
//
// Acoustic kits use real multi-mic recordings bundled in Resources/Drums
// (Karoryfer "Big Rusty Drums", CC0): up to 7 velocity layers x 4 round-robin takes
// per articulation, listed with their measured loudness in manifest.json. Clap, shaker
// and the Electronic kit (and everything, if the recordings are missing) are rendered
// offline with the synthesis below. At playback time the audio thread mixes the takes
// through a 64-voice pool (see DrumSynth).

// MARK: - Offline DSP helpers

struct Biquad {
    enum Kind { case lowpass, highpass, bandpass }
    private var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    private var z1 = 0.0, z2 = 0.0

    init(_ kind: Kind, _ freq: Double, q: Double = 0.707, sr: Double) {
        let w = 2 * Double.pi * min(freq, sr * 0.45) / sr
        let cw = cos(w)
        let alpha = sin(w) / (2 * q)
        var n0 = 0.0, n1 = 0.0, n2 = 0.0
        switch kind {
        case .lowpass: n0 = (1 - cw) / 2; n1 = 1 - cw; n2 = (1 - cw) / 2
        case .highpass: n0 = (1 + cw) / 2; n1 = -(1 + cw); n2 = (1 + cw) / 2
        case .bandpass: n0 = alpha; n1 = 0; n2 = -alpha
        }
        let a0 = 1 + alpha
        b0 = n0 / a0; b1 = n1 / a0; b2 = n2 / a0
        a1 = -2 * cw / a0; a2 = (1 - alpha) / a0
    }

    mutating func run(_ x: Double) -> Double {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }
}

struct NoiseGen {
    private var s: UInt64
    init(_ seed: UInt64) { s = (seed &* 0x9E37_79B9_7F4A_7C15) | 1 }
    mutating func next() -> Double {
        s ^= s << 13
        s ^= s >> 7
        s ^= s << 17
        return Double(Int64(bitPattern: s)) / Double(Int64.max)
    }
}

/// Six detuned square oscillators (TR-808 style metallic source).
struct MetalSource {
    private var ph: [Double]
    private let inc: [Double]
    init(scale: Double, sr: Double, seed: UInt64) {
        let base = [205.3, 304.4, 369.6, 522.7, 540.0, 800.0]
        var rng = NoiseGen(seed)
        ph = base.map { _ in abs(rng.next()) }
        inc = base.map { $0 * scale / sr }
    }
    mutating func next() -> Double {
        var s = 0.0
        for i in 0..<6 {
            var p = ph[i] + inc[i]
            if p >= 1 { p -= 1 }
            ph[i] = p
            s += p < 0.5 ? 1 : -1
        }
        return s / 6
    }
}

@inline(__always) private func env(_ t: Double, _ attack: Double, _ decay: Double) -> Double {
    (t < attack ? t / attack : 1) * exp(-max(0, t - attack) / decay)
}

// MARK: - Drum voice rendering

enum DrumVoices {
    /// Peak level of each instrument after rendering (sets the kit balance).
    static let targetPeak: [Double] = [0.95, 0.82, 0.40, 0.38, 0.32, 0.45, 0.72, 0.78, 0.55, 0.62, 0.30]

    static func render(_ d: Int, kit k: KitParams, sr: Double, variant: Int) -> ([Float], [Float]) {
        let seed = UInt64(d * 7919 + variant * 104_729 + 17)
        var l: [Double]
        var r: [Double]
        switch d {
        case 0: l = kick(k, sr, seed); r = l
        case 1: l = snare(k, sr, seed); r = l
        case 2: l = hat(k, sr, seed, open: false); r = l
        case 3: (l, r) = stereo { hat(k, sr, seed &+ $0, open: true) }
        case 4: (l, r) = stereo { ride(k, sr, seed &+ $0) }
        case 5: (l, r) = stereo { crash(k, sr, seed &+ $0) }
        case 6, 7: l = tom(k, sr, seed, low: d == 7); r = l
        case 8: l = rim(k, sr, seed); r = l
        case 9: (l, r) = stereo { clap(k, sr, seed &+ $0) }
        default: l = shaker(k, sr, seed); r = l
        }
        return finish(l, r, peak: targetPeak[min(d, targetPeak.count - 1)], sr: sr)
    }

    /// Two decorrelated renders blended into a wide but mono-compatible stereo pair.
    private static func stereo(_ make: (UInt64) -> [Double]) -> ([Double], [Double]) {
        let a = make(0)
        let b = make(9_999_991)
        let n = min(a.count, b.count)
        var l = [Double](repeating: 0, count: n)
        var r = [Double](repeating: 0, count: n)
        for i in 0..<n {
            l[i] = a[i] * 0.78 + b[i] * 0.22
            r[i] = b[i] * 0.78 + a[i] * 0.22
        }
        return (l, r)
    }

    /// Normalise, trim the silent tail and fade the end.
    private static func finish(_ l: [Double], _ r: [Double], peak: Double, sr: Double) -> ([Float], [Float]) {
        var mx = 1e-9
        for i in 0..<l.count { mx = max(mx, abs(l[i]), abs(r[i])) }
        let g = peak / mx
        var end = l.count
        let floor = 0.00008 / g
        while end > 1 && abs(l[end - 1]) < floor && abs(r[end - 1]) < floor { end -= 1 }
        end = min(l.count, end + 16)
        let fade = min(end, Int(0.01 * sr))
        var outL = [Float](repeating: 0, count: end)
        var outR = [Float](repeating: 0, count: end)
        for i in 0..<end {
            var gi = g
            if i >= end - fade { gi *= Double(end - i) / Double(fade) }
            outL[i] = Float(l[i] * gi)
            outR[i] = Float(r[i] * gi)
        }
        return (outL, outR)
    }

    private static func count(_ seconds: Double, _ sr: Double) -> Int { max(16, Int(seconds * sr)) }

    // Kick: pitch-swept sine body + harmonic knock + beater click, saturated.
    private static func kick(_ k: KitParams, _ sr: Double, _ seed: UInt64) -> [Double] {
        let n = count(min(2.5, k.kickDecay * 5 + 0.1), sr)
        var out = [Double](repeating: 0, count: n)
        var noise = NoiseGen(seed)
        var clickBP = Biquad(.bandpass, 3200, q: 0.9, sr: sr)
        var thump = Biquad(.lowpass, 900, q: 0.8, sr: sr)
        let sweepTau = 0.03 + 0.02 * k.analog
        var ph = 0.0
        for i in 0..<n {
            let t = Double(i) / sr
            let f = k.kickFreq * (1 + (k.kickSweep - 1) * exp(-t / sweepTau))
            ph += 2 * Double.pi * f / sr
            let body = sin(ph) * env(t, 0.0015, k.kickDecay)
            let knock = sin(2 * ph) * 0.2 * exp(-t / 0.025)
            let click = clickBP.run(noise.next()) * exp(-t / 0.0045) * k.kickClick * 3 * (1 - 0.7 * k.analog)
            let beater = thump.run(noise.next()) * exp(-t / 0.012) * 0.4 * (1 - k.analog)
            out[i] = tanh(k.kickDrive * (body + knock + click + beater))
        }
        return out
    }

    // Snare: two pitched shell modes + band-limited wire noise + stick crack (or brush swish).
    private static func snare(_ k: KitParams, _ sr: Double, _ seed: UInt64) -> [Double] {
        let brush = k.snareBrush
        let n = count(min(1.4, k.snareDecay * 5 + 0.15), sr)
        var out = [Double](repeating: 0, count: n)
        var noise = NoiseGen(seed)
        var noise2 = NoiseGen(seed &+ 77)
        var hp = Biquad(.highpass, brush > 0.5 ? 900 : 1500, q: 0.7, sr: sr)
        var lp = Biquad(.lowpass, (brush > 0.5 ? 4500 : 6500) + 6000 * k.bright, q: 0.7, sr: sr)
        var crackBP = Biquad(.bandpass, 4800, q: 1.2, sr: sr)
        var p1 = 0.0
        var p2 = 0.0
        let shellTau = 0.06 + 0.05 * k.analog
        for i in 0..<n {
            let t = Double(i) / sr
            let drop = 1 + 0.3 * exp(-t / 0.012)
            p1 += 2 * Double.pi * k.snareTone * drop / sr
            p2 += 2 * Double.pi * k.snareTone * 1.83 * drop / sr
            let shell = (sin(p1) + 0.55 * sin(p2)) * env(t, 0.001, shellTau) * (1 - brush * 0.85)
            let wires = lp.run(hp.run(noise.next()))
            let wireEnv = brush > 0.5
                ? env(t, 0.014, k.snareDecay) * (0.75 + 0.25 * sin(t * 40))
                : env(t, 0.0008, k.snareDecay)
            let crack = crackBP.run(noise2.next()) * exp(-t / 0.006) * (1 - brush)
            let x = shell * (1 - k.snareNoise) * 1.6 + wires * wireEnv * k.snareNoise * 2.4 + crack * 0.9
            out[i] = tanh(1.4 * x)
        }
        return out
    }

    // Hi-hats: metallic squares (+ noise for acoustic kits) through steep high-pass and band-pass.
    private static func hat(_ k: KitParams, _ sr: Double, _ seed: UInt64, open: Bool) -> [Double] {
        let decay = (open ? 0.30 : 0.034) * k.hatDecay
        let n = count(decay * 6 + 0.02, sr)
        var out = [Double](repeating: 0, count: n)
        var metal = MetalSource(scale: k.hatScale * (1 + 0.6 * (1 - k.analog)), sr: sr, seed: seed)
        var noise = NoiseGen(seed &+ 5)
        var hp1 = Biquad(.highpass, 6800, q: 0.7, sr: sr)
        var hp2 = Biquad(.highpass, 6800, q: 0.7, sr: sr)
        var bp = Biquad(.bandpass, 8500 + 3000 * k.bright, q: 0.55, sr: sr)
        let noiseMix = 0.45 * (1 - k.analog)
        for i in 0..<n {
            let t = Double(i) / sr
            let src = metal.next() * (1 - noiseMix) + noise.next() * noiseMix
            let x = bp.run(hp2.run(hp1.run(src)))
            var e = env(t, 0.0004, decay)
            if open { e = 0.85 * e + 0.15 * env(t, 0.0004, decay * 2.5) }
            out[i] = x * e
        }
        return out
    }

    // Ride: metallic shimmer + bell partials + stick ping + noise wash.
    private static func ride(_ k: KitParams, _ sr: Double, _ seed: UInt64) -> [Double] {
        let decay = 1.1 * k.cymbalDecay
        let n = count(min(4, decay * 4), sr)
        var out = [Double](repeating: 0, count: n)
        var metal = MetalSource(scale: 1.35 * k.hatScale, sr: sr, seed: seed)
        var noise = NoiseGen(seed &+ 3)
        var hp = Biquad(.highpass, 4000, q: 0.7, sr: sr)
        var bp = Biquad(.bandpass, 5200 + 1500 * k.bright, q: 0.5, sr: sr)
        var ping = Biquad(.bandpass, 7000, q: 1.5, sr: sr)
        var washHP = Biquad(.highpass, 6000, q: 0.7, sr: sr)
        for i in 0..<n {
            let t = Double(i) / sr
            let body = bp.run(hp.run(metal.next())) * env(t, 0.001, decay)
            let bell = (sin(2 * Double.pi * 2980 * t) + 0.6 * sin(2 * Double.pi * 4470 * t)) * exp(-t / 0.45) * 0.10
            let stick = ping.run(noise.next()) * exp(-t / 0.008) * 0.8
            let wash = washHP.run(noise.next()) * env(t, 0.002, decay * 0.8) * 0.18
            out[i] = body + bell + stick + wash
        }
        return out
    }

    // Crash: noise + metal, bright and long with a two-stage decay.
    private static func crash(_ k: KitParams, _ sr: Double, _ seed: UInt64) -> [Double] {
        let decay = 1.3 * k.cymbalDecay
        let n = count(min(4.5, decay * 3.5), sr)
        var out = [Double](repeating: 0, count: n)
        var metal = MetalSource(scale: 1.9 * k.hatScale, sr: sr, seed: seed)
        var noise = NoiseGen(seed &+ 9)
        var hp = Biquad(.highpass, 2800, q: 0.7, sr: sr)
        var lp = Biquad(.lowpass, 9000 + 6000 * k.bright, q: 0.7, sr: sr)
        for i in 0..<n {
            let t = Double(i) / sr
            let src = metal.next() * 0.45 + noise.next() * 0.65
            let x = lp.run(hp.run(src))
            let e = env(t, 0.004, decay * 0.2) * 0.55 + env(t, 0.006, decay) * 0.45
            out[i] = x * e
        }
        return out
    }

    // Toms: pitch-drop sine with an inharmonic overtone and stick attack.
    private static func tom(_ k: KitParams, _ sr: Double, _ seed: UInt64, low: Bool) -> [Double] {
        let f0 = (low ? 108.0 : 192.0) * k.tomPitch
        let decay = k.tomDecay * (low ? 1.2 : 1.0)
        let n = count(min(2, decay * 5), sr)
        var out = [Double](repeating: 0, count: n)
        var noise = NoiseGen(seed)
        var stickBP = Biquad(.bandpass, 2400, q: 1.0, sr: sr)
        var p1 = 0.0
        var p2 = 0.0
        for i in 0..<n {
            let t = Double(i) / sr
            let f = f0 * (1 + 0.35 * exp(-t / 0.045))
            p1 += 2 * Double.pi * f / sr
            p2 += 2 * Double.pi * f * 1.58 / sr
            let body = sin(p1) * env(t, 0.001, decay)
            let over = sin(p2) * env(t, 0.001, decay * 0.35) * 0.25 * (1 - 0.6 * k.analog)
            let stick = stickBP.run(noise.next()) * exp(-t / 0.006) * 0.6 * (1 - k.analog)
            out[i] = tanh(1.3 * (body + over + stick))
        }
        return out
    }

    // Rim / cross-stick (also the metronome click): resonant wood-like modes excited by a tiny burst.
    private static func rim(_ k: KitParams, _ sr: Double, _ seed: UInt64) -> [Double] {
        let n = count(0.25, sr)
        var out = [Double](repeating: 0, count: n)
        if k.analog > 0.5 {
            var bp = Biquad(.bandpass, 1700, q: 2, sr: sr)
            for i in 0..<n {
                let t = Double(i) / sr
                let x = (sin(2 * Double.pi * 1667 * t) + 0.6 * sin(2 * Double.pi * 455 * t)) * exp(-t / 0.011)
                out[i] = bp.run(x) * 2 + x * 0.3
            }
            return out
        }
        var noise = NoiseGen(seed)
        var r1 = Biquad(.bandpass, 1750, q: 18, sr: sr)
        var r2 = Biquad(.bandpass, 2850, q: 14, sr: sr)
        var r3 = Biquad(.bandpass, 480, q: 4, sr: sr)
        var air = Biquad(.bandpass, 5000, q: 1, sr: sr)
        for i in 0..<n {
            let t = Double(i) / sr
            let exc = noise.next() * exp(-t / 0.0008)
            out[i] = r1.run(exc) * 1.0 + r2.run(exc) * 0.6 + r3.run(exc) * 0.5 + air.run(exc) * 0.3
        }
        return out
    }

    // Clap: four quick band-passed noise bursts followed by a diffuse tail.
    private static func clap(_ k: KitParams, _ sr: Double, _ seed: UInt64) -> [Double] {
        let n = count(0.7, sr)
        var out = [Double](repeating: 0, count: n)
        var noise = NoiseGen(seed)
        var bp = Biquad(.bandpass, 1150, q: 1.3, sr: sr)
        var hp = Biquad(.highpass, 500, q: 0.7, sr: sr)
        let spacing = 0.0095
        let tailTau = 0.10 + 0.05 * k.room
        for i in 0..<n {
            let t = Double(i) / sr
            var e = 0.0
            for b in 0..<4 {
                let tb = t - Double(b) * spacing
                if tb >= 0 { e = max(e, exp(-tb / 0.0035)) }
            }
            let tt = t - 3 * spacing
            if tt >= 0 { e = max(e, 0.75 * exp(-tt / tailTau)) }
            out[i] = hp.run(bp.run(noise.next())) * e
        }
        return out
    }

    // Shaker / brush swish: bright noise with a soft attack.
    private static func shaker(_ k: KitParams, _ sr: Double, _ seed: UInt64) -> [Double] {
        let n = count(0.25, sr)
        var out = [Double](repeating: 0, count: n)
        var noise = NoiseGen(seed)
        var hp = Biquad(.highpass, 4500, q: 0.7, sr: sr)
        var bp = Biquad(.bandpass, 7500 + 2500 * k.bright, q: 0.7, sr: sr)
        for i in 0..<n {
            let t = Double(i) / sr
            let e = t < 0.014 ? t / 0.014 : exp(-(t - 0.014) / 0.045)
            out[i] = bp.run(hp.run(noise.next())) * e
        }
        return out
    }
}

// MARK: - Instruments

/// Instruments 0…10 are the pattern lanes (see RhythmLibrary); 11…14 are extra
/// articulations the groove engine uses for fills, count-ins and accents.
enum Drum {
    static let kick = 0, snare = 1, hatClosed = 2, hatOpen = 3, ride = 4, crash = 5
    static let tomHi = 6, tomLo = 7, stick = 8, clap = 9, shaker = 10
    static let tomMid = 11, hatPedal = 12, rideBell = 13, hatLoose = 14
    static let count = 15
}

// MARK: - Recorded samples

enum RecordedDrums {
    struct Group {
        let layers: Int
        let roundRobins: Int
        let loudness: [Float]     // attack loudness of each layer in dB (loudest = 0)
    }

    /// Recording group of a drum in a kit (nil = synthesized).
    static func group(for drum: Int, kit: KitParams) -> String? {
        switch drum {
        case Drum.kick: return "kick"
        case Drum.snare: return kit.snareSet
        case Drum.hatClosed: return kit.hatSet
        case Drum.hatOpen: return "hat_open"
        case Drum.ride: return "ride"
        case Drum.crash: return "crash"
        case Drum.tomHi: return "tom_hi"
        case Drum.tomLo: return "tom_lo"
        case Drum.stick: return "sidestick"
        case Drum.tomMid: return "tom_mid"
        case Drum.hatPedal: return "hat_pedal"
        case Drum.rideBell: return "ride_bell"
        case Drum.hatLoose: return "hat_loose"
        default: return nil
        }
    }

    /// Mix balance of the recordings.
    static let gain: [String: Float] = [
        "kick": 1.0, "snare": 0.86, "snare_rim": 0.84, "snare_brush": 0.95, "sidestick": 0.62,
        "hat_closed": 0.46, "hat_brush": 0.52, "hat_loose": 0.40, "hat_open": 0.40, "hat_pedal": 0.42,
        "ride": 0.42, "ride_bell": 0.36, "crash": 0.46,
        "tom_hi": 0.74, "tom_mid": 0.76, "tom_lo": 0.80,
    ]

    static var directory: URL? {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let res = Bundle.main.resourceURL { candidates.append(res.appendingPathComponent("Drums")) }
        candidates.append(URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("Resources/Drums"))
        return candidates.first { fm.fileExists(atPath: $0.appendingPathComponent("manifest.json").path) }
    }

    static func manifest(_ dir: URL) -> [String: Group] {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let groups = obj["groups"] as? [String: Any] else { return [:] }
        var out: [String: Group] = [:]
        for (name, any) in groups {
            guard let g = any as? [String: Any],
                  let layers = (g["layers"] as? NSNumber)?.intValue,
                  let rrs = (g["roundRobins"] as? NSNumber)?.intValue,
                  let loud = g["loudness"] as? [NSNumber], loud.count == layers, layers > 0, rrs > 0 else { continue }
            out[name] = Group(layers: min(layers, SampleBank.maxLayers), roundRobins: rrs,
                              loudness: loud.prefix(SampleBank.maxLayers).map { $0.floatValue })
        }
        return out
    }

    /// One take as interleaved 16-bit stereo plus its sample rate.
    static func load(_ dir: URL, group: String, layer: Int, rr: Int) -> ([Int16], Double)? {
        let url = dir.appendingPathComponent("\(group)_v\(layer + 1)_rr\(rr + 1).caf")
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let fmt = file.processingFormat
        let n = Int(file.length)
        guard n > 0, let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n)),
              (try? file.read(into: buf)) != nil, let ch = buf.floatChannelData else { return nil }
        let frames = Int(buf.frameLength)
        let c0 = ch[0]
        let c1 = fmt.channelCount > 1 ? ch[1] : ch[0]
        var out = [Int16](repeating: 0, count: frames * 2)
        for i in 0..<frames {
            out[2 * i] = Int16(max(-32767, min(32767, c0[i] * 32767)))
            out[2 * i + 1] = Int16(max(-32767, min(32767, c1[i] * 32767)))
        }
        return (out, fmt.sampleRate)
    }
}

// MARK: - Sample bank

/// Every drum sound of every kit. Takes are stored once as interleaved 16-bit stereo;
/// a "sound" (kit × drum) points at its velocity layers × round-robin takes and carries
/// the measured loudness of each layer, its tuning, drive and mix gain.
final class SampleBank {
    static let maxLayers = 8
    let pcm: UnsafeMutablePointer<Int16>
    let takeOff: UnsafeMutablePointer<Int>        // first frame of the take in `pcm`
    let takeLen: UnsafeMutablePointer<Int>        // frames
    let takeRate: UnsafeMutablePointer<Double>    // source rate / output rate
    let sTake0: UnsafeMutablePointer<Int>
    let sLayers: UnsafeMutablePointer<Int>
    let sRR: UnsafeMutablePointer<Int>
    let sLoud: UnsafeMutablePointer<Float>
    let sPitch: UnsafeMutablePointer<Float>
    let sGain: UnsafeMutablePointer<Float>
    let sDrive: UnsafeMutablePointer<Float>
    let sSampled: UnsafeMutablePointer<Int>
    let usesRecordings: Bool
    let soundCount: Int

    static func sound(kit: Int, drum: Int) -> Int { kit * Drum.count + drum }

    init(sampleRate sr: Double, kits: [KitParams]) {
        let dir = RecordedDrums.directory
        let groups = dir.map { RecordedDrums.manifest($0) } ?? [:]
        var takes: [([Int16], Double)] = []
        var groupStart: [String: Int] = [:]          // group -> first take index (or -1 if unusable)
        var synthStart: [String: Int] = [:]
        var recorded = false

        struct Sound { var take0 = 0, layers = 1, rrs = 2; var loud: [Float] = [0]
                       var pitch: Float = 1, gain: Float = 1, drive: Float = 1, sampled = false }
        var sounds: [Sound] = []

        func synthTakes(_ k: Int, _ kit: KitParams, _ d: Int) -> Int {
            let key = "\(k)|\(d)"
            if let s = synthStart[key] { return s }
            let start = takes.count
            for v in 0..<2 {
                let (l, r) = DrumVoices.render(d, kit: kit, sr: sr, variant: v)
                let n = min(l.count, r.count)
                var pcm = [Int16](repeating: 0, count: n * 2)
                for i in 0..<n {
                    pcm[2 * i] = Int16(max(-32767, min(32767, l[i] * 32767)))
                    pcm[2 * i + 1] = Int16(max(-32767, min(32767, r[i] * 32767)))
                }
                takes.append((pcm, sr))
            }
            synthStart[key] = start
            return start
        }

        for (k, kit) in kits.enumerated() {
            for d in 0..<Drum.count {
                var s = Sound()
                if kit.sampled, let dir, let name = RecordedDrums.group(for: d, kit: kit), let g = groups[name] {
                    var start = groupStart[name]
                    if start == nil {
                        let first = takes.count
                        var ok = true
                        loop: for layer in 0..<g.layers {
                            for rr in 0..<g.roundRobins {
                                guard let t = RecordedDrums.load(dir, group: name, layer: layer, rr: rr) else { ok = false; break loop }
                                takes.append(t)
                            }
                        }
                        if !ok { takes.removeSubrange(first...) }
                        start = ok ? first : -1
                        groupStart[name] = start
                    }
                    if let st = start, st >= 0 {
                        recorded = true
                        let tuned = d == Drum.kick || d == Drum.snare || d == Drum.tomHi || d == Drum.tomMid || d == Drum.tomLo
                        let driven = d == Drum.kick || d == Drum.snare
                        s = Sound(take0: st, layers: g.layers, rrs: g.roundRobins, loud: g.loudness,
                                  pitch: tuned ? Float(kit.pitch) : 1, gain: RecordedDrums.gain[name] ?? 0.8,
                                  drive: driven ? Float(kit.drive) : 1, sampled: true)
                        sounds.append(s)
                        continue
                    }
                }
                // synthesized (extra articulations reuse a related sound)
                var base = d, pitch: Float = 1, gain: Float = 1
                switch d {
                case Drum.tomMid: base = Drum.tomHi; pitch = 0.8
                case Drum.hatPedal: base = Drum.hatClosed; gain = 0.5
                case Drum.rideBell: base = Drum.ride; pitch = 1.12; gain = 0.9
                case Drum.hatLoose: base = Drum.hatOpen; gain = 0.8
                default: break
                }
                s.take0 = synthTakes(k, kit, base)
                s.pitch = pitch
                s.gain = gain
                sounds.append(s)
            }
        }

        let frames = takes.reduce(0) { $0 + $1.0.count / 2 }
        let buf = UnsafeMutablePointer<Int16>.allocate(capacity: max(2, frames * 2))
        let to = UnsafeMutablePointer<Int>.allocate(capacity: max(1, takes.count))
        let tl = UnsafeMutablePointer<Int>.allocate(capacity: max(1, takes.count))
        let tr = UnsafeMutablePointer<Double>.allocate(capacity: max(1, takes.count))
        var pos = 0
        for (i, t) in takes.enumerated() {
            (buf + pos * 2).initialize(from: t.0, count: t.0.count)
            to[i] = pos
            tl[i] = t.0.count / 2
            tr[i] = t.1 / sr
            pos += t.0.count / 2
        }
        let n = sounds.count
        func ints(_ f: (Sound) -> Int) -> UnsafeMutablePointer<Int> {
            let p = UnsafeMutablePointer<Int>.allocate(capacity: max(1, n))
            for (i, s) in sounds.enumerated() { p[i] = f(s) }
            return p
        }
        func floats(_ f: (Sound) -> Float) -> UnsafeMutablePointer<Float> {
            let p = UnsafeMutablePointer<Float>.allocate(capacity: max(1, n))
            for (i, s) in sounds.enumerated() { p[i] = f(s) }
            return p
        }
        let loud = UnsafeMutablePointer<Float>.allocate(capacity: max(1, n * SampleBank.maxLayers))
        loud.initialize(repeating: 0, count: max(1, n * SampleBank.maxLayers))
        for (i, s) in sounds.enumerated() {
            for (j, x) in s.loud.prefix(SampleBank.maxLayers).enumerated() { loud[i * SampleBank.maxLayers + j] = x }
        }
        pcm = buf
        takeOff = to
        takeLen = tl
        takeRate = tr
        sTake0 = ints { $0.take0 }
        sLayers = ints { $0.layers }
        sRR = ints { $0.rrs }
        sSampled = ints { $0.sampled ? 1 : 0 }
        sPitch = floats { $0.pitch }
        sGain = floats { $0.gain }
        sDrive = floats { $0.drive }
        sLoud = loud
        soundCount = n
        usesRecordings = recorded
    }
}

// MARK: - Realtime sample player

@inline(__always) private func hermite(_ xm1: Float, _ x0: Float, _ x1: Float, _ x2: Float, _ t: Float) -> Float {
    let c = (x1 - xm1) * 0.5
    let v = x0 - x1
    let w = c + v
    let a = w + v + (x2 - x0) * 0.5
    let b = w + a
    return (((a * t) - b) * t + c) * t + x0
}

/// Plays the sample bank on the audio thread (no allocation, no blocking).
///
/// - velocity picks the recorded layer whose measured loudness is closest to the target
///   level and trims the rest with gain, so timbre follows dynamics like a real drum;
/// - round robins are chosen at random (never the same take twice in a row);
/// - a new hit damps the previous ring of the same drum, the hi-hat pedal chokes open hats
///   and cymbals keep ringing under new hits up to a few voices;
/// - kick / snare / toms are tuned per kit by playing them back faster or slower
///   (4-point Hermite interpolation, which also converts 44.1 kHz recordings to the device rate);
/// - everything goes through a room (early reflections + 8-line feedback delay network)
///   and a gentle bus compressor.
final class DrumSynth {
    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private var pendingBank: SampleBank?
    private var bank: SampleBank?
    private var pcm: UnsafeMutablePointer<Int16>
    private var takeOff: UnsafeMutablePointer<Int>
    private var takeLen: UnsafeMutablePointer<Int>
    private var takeRate: UnsafeMutablePointer<Double>
    private(set) var ready = false

    private let maxVoices = 64
    private let vOn: UnsafeMutablePointer<Int>
    private let vTake: UnsafeMutablePointer<Int>
    private let vInst: UnsafeMutablePointer<Int>
    private let vDelay: UnsafeMutablePointer<Int>
    private let vAge: UnsafeMutablePointer<Int>
    private let vPos: UnsafeMutablePointer<Double>
    private let vRate: UnsafeMutablePointer<Double>
    private let vGain: UnsafeMutablePointer<Float>
    private let vDrive: UnsafeMutablePointer<Float>
    private let vRel: UnsafeMutablePointer<Float>
    private let vRelStep: UnsafeMutablePointer<Float>
    private let balL: UnsafeMutablePointer<Float>
    private let balR: UnsafeMutablePointer<Float>
    private let sendAmt: UnsafeMutablePointer<Float>
    private let lastTake: UnsafeMutablePointer<Int>
    private let roomSend: UnsafeMutablePointer<Float>
    private let roomTime: UnsafeMutablePointer<Double>
    private let kitCount: Int
    private var kitIndex = 0
    private var reverbKit = -1
    private var ageCounter = 0
    private var rng: UInt32 = 0x1234_5678
    private let sr: Double
    private let reverb: RoomReverb
    private var comp: BusCompressor
    var reverbLevel: Float = 0.2

    init(sampleRate: Double) {
        sr = sampleRate
        let lk = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        lk.initialize(to: os_unfair_lock())
        lock = lk
        let dummy16 = UnsafeMutablePointer<Int16>.allocate(capacity: 2)
        dummy16.initialize(repeating: 0, count: 2)
        let dummyI = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        dummyI.initialize(to: 0)
        let dummyD = UnsafeMutablePointer<Double>.allocate(capacity: 1)
        dummyD.initialize(to: 1)
        pcm = dummy16
        takeOff = dummyI
        takeLen = dummyI
        takeRate = dummyD
        func f(_ n: Int, _ x: Float = 0) -> UnsafeMutablePointer<Float> {
            let p = UnsafeMutablePointer<Float>.allocate(capacity: n)
            p.initialize(repeating: x, count: n)
            return p
        }
        func i(_ n: Int, _ x: Int = 0) -> UnsafeMutablePointer<Int> {
            let p = UnsafeMutablePointer<Int>.allocate(capacity: n)
            p.initialize(repeating: x, count: n)
            return p
        }
        func d(_ n: Int) -> UnsafeMutablePointer<Double> {
            let p = UnsafeMutablePointer<Double>.allocate(capacity: n)
            p.initialize(repeating: 0, count: n)
            return p
        }
        let mv = 64
        vOn = i(mv); vTake = i(mv); vInst = i(mv); vDelay = i(mv); vAge = i(mv)
        vPos = d(mv); vRate = d(mv)
        vGain = f(mv); vDrive = f(mv, 1); vRel = f(mv, 1); vRelStep = f(mv)
        balL = f(Drum.count, 1); balR = f(Drum.count, 1); sendAmt = f(Drum.count, 1)
        let kits = RhythmLibrary.kits
        kitCount = kits.count
        lastTake = i(kits.count * Drum.count, -1)
        roomSend = f(kits.count)
        roomTime = d(kits.count)
        reverb = RoomReverb(sampleRate: sampleRate)
        comp = BusCompressor(sampleRate: sampleRate)
        // stereo placement (drummer's perspective) and room send per drum
        //                     K     S    HC     HO    R     C     T1    T3    Stk  Clap  Shk   T2   Ped  Bell  HL
        let pans: [Float] = [0, 0, -0.35, -0.35, 0.35, -0.25, -0.2, 0.35, 0, 0, 0.3, 0.08, -0.35, 0.35, -0.35]
        let sends: [Float] = [0.3, 1.0, 0.45, 0.55, 0.5, 0.6, 0.9, 0.9, 0.8, 0.9, 0.5, 0.9, 0.4, 0.5, 0.5]
        for dr in 0..<Drum.count {
            balL[dr] = 1 - max(0, pans[dr])
            balR[dr] = 1 + min(0, pans[dr])
            sendAmt[dr] = sends[dr]
        }
        for (k, kit) in kits.enumerated() {
            roomSend[k] = Float(kit.room)
            roomTime[k] = 0.42 + 0.22 * kit.room
        }
        let rate = sampleRate
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let built = SampleBank(sampleRate: rate, kits: kits)
            guard let self else { return }
            os_unfair_lock_lock(self.lock)
            self.pendingBank = built
            os_unfair_lock_unlock(self.lock)
        }
    }

    /// Called once per audio callback: picks up the rendered bank when it is ready.
    func prepare() {
        guard !ready, os_unfair_lock_trylock(lock) else { return }
        if let b = pendingBank {
            bank = b
            pcm = b.pcm
            takeOff = b.takeOff
            takeLen = b.takeLen
            takeRate = b.takeRate
            ready = true
        }
        os_unfair_lock_unlock(lock)
    }

    func setKit(_ i: Int) {
        kitIndex = max(0, min(kitCount - 1, i))
        if kitIndex != reverbKit {
            reverbKit = kitIndex
            reverb.setDecay(roomTime[kitIndex])
        }
    }

    @inline(__always) private func random() -> Float {
        rng ^= rng << 13
        rng ^= rng >> 17
        rng ^= rng << 5
        return Float(rng) / Float(UInt32.max)
    }

    private func release(where match: (Int) -> Bool, seconds: Double) {
        let step = Float(1.0 / max(1, seconds * sr))
        for v in 0..<maxVoices where vOn[v] != 0 && match(vInst[v]) {
            if vRelStep[v] == 0 || vRelStep[v] < step { vRelStep[v] = step }
        }
    }

    /// Plays drum `d` at `velocity` (0…1), `delay` samples from now.
    func trigger(_ d: Int, _ velocity: Float, delay: Int = 0) {
        guard ready, let bank, d >= 0, d < Drum.count else { return }
        // natural damping / choking
        switch d {
        case Drum.hatClosed, Drum.hatPedal:
            release(where: { $0 == Drum.hatOpen || $0 == Drum.hatLoose }, seconds: 0.035)
            release(where: { $0 == d }, seconds: 0.08)
        case Drum.hatLoose:
            release(where: { $0 == Drum.hatOpen || $0 == Drum.hatLoose }, seconds: 0.06)
        case Drum.hatOpen:
            release(where: { $0 == Drum.hatOpen || $0 == Drum.hatLoose }, seconds: 0.12)
        case Drum.kick: release(where: { $0 == Drum.kick }, seconds: 0.15)
        case Drum.snare: release(where: { $0 == Drum.snare }, seconds: 0.12)
        case Drum.tomHi, Drum.tomMid, Drum.tomLo: release(where: { $0 == d }, seconds: 0.2)
        case Drum.stick, Drum.clap, Drum.shaker: release(where: { $0 == d }, seconds: 0.06)
        case Drum.ride, Drum.crash, Drum.rideBell:
            // cymbals wash on, but keep only the newest few rings
            var n = 0
            var oldest = -1
            var oldestAge = Int.max
            for v in 0..<maxVoices where vOn[v] != 0 && vInst[v] == d && vRelStep[v] == 0 {
                n += 1
                if vAge[v] < oldestAge { oldestAge = vAge[v]; oldest = v }
            }
            if n >= 3 && oldest >= 0 { vRelStep[oldest] = Float(1.0 / (0.4 * sr)) }
        default: break
        }

        let s = SampleBank.sound(kit: kitIndex, drum: d)
        guard s < bank.soundCount else { return }
        let layers = bank.sLayers[s]
        let rrs = bank.sRR[s]
        let vel = max(0.02, min(1, velocity))
        // target level: full velocity = 0 dB, ghost notes (0.3) ≈ -20 dB
        let target = -30 * powf(1 - vel, 1.1)
        var layer = 0
        var gainDB: Float
        if bank.sSampled[s] != 0 && layers > 1 {
            let aim = target + (random() - 0.5) * 3
            var best = Float.greatestFiniteMagnitude
            for j in 0..<layers {
                let dist = abs(bank.sLoud[s * SampleBank.maxLayers + j] - aim)
                if dist < best { best = dist; layer = j }
            }
            gainDB = max(-18, min(4, target - bank.sLoud[s * SampleBank.maxLayers + layer]))
        } else {
            gainDB = target * 0.8
        }
        var rr = Int(random() * Float(rrs)) % max(1, rrs)
        var take = bank.sTake0[s] + layer * rrs + rr
        if take == lastTake[s] && rrs > 1 {
            rr = (rr + 1) % rrs
            take = bank.sTake0[s] + layer * rrs + rr
        }
        lastTake[s] = take

        // free voice, otherwise steal the oldest
        var slot = -1
        var oldest = 0
        var oldestAge = Int.max
        for v in 0..<maxVoices {
            if vOn[v] == 0 { slot = v; break }
            if vAge[v] < oldestAge { oldestAge = vAge[v]; oldest = v }
        }
        if slot < 0 { slot = oldest }
        ageCounter += 1
        vOn[slot] = 1
        vTake[slot] = take
        vInst[slot] = d
        vDelay[slot] = max(0, delay)
        vAge[slot] = ageCounter
        vPos[slot] = 0
        vRate[slot] = takeRate[take] * Double(bank.sPitch[s]) * Double(1 + (random() - 0.5) * 0.004)
        vGain[slot] = powf(10, gainDB / 20) * bank.sGain[s]
        vDrive[slot] = bank.sDrive[s]
        vRel[slot] = 1
        vRelStep[slot] = 0
    }

    func next() -> (Float, Float) {
        var l: Float = 0
        var r: Float = 0
        var send: Float = 0
        if ready {
            let scale: Float = 1.0 / 32768
            for v in 0..<maxVoices where vOn[v] != 0 {
                if vDelay[v] > 0 {
                    vDelay[v] -= 1
                    continue
                }
                let t = vTake[v]
                let len = takeLen[t]
                let pos = vPos[v]
                let i = Int(pos)
                if i >= len - 1 {
                    vOn[v] = 0
                    continue
                }
                var g = vGain[v]
                if vRelStep[v] > 0 {
                    let rel = vRel[v] - vRelStep[v]
                    if rel <= 0 {
                        vOn[v] = 0
                        continue
                    }
                    vRel[v] = rel
                    g *= rel * rel
                }
                let base = pcm + takeOff[t] * 2
                let frac = Float(pos - Double(i))
                var xl: Float
                var xr: Float
                if frac == 0 {
                    xl = Float(base[2 * i])
                    xr = Float(base[2 * i + 1])
                } else {
                    let im1 = i > 0 ? i - 1 : 0
                    let i2 = i + 2 < len ? i + 2 : len - 1
                    xl = hermite(Float(base[2 * im1]), Float(base[2 * i]), Float(base[2 * i + 2]), Float(base[2 * i2]), frac)
                    xr = hermite(Float(base[2 * im1 + 1]), Float(base[2 * i + 1]), Float(base[2 * i + 3]), Float(base[2 * i2 + 1]), frac)
                }
                xl *= scale * g
                xr *= scale * g
                let dr = vDrive[v]
                if dr > 1.001 {
                    let norm = 1 / tanhf(dr)
                    xl = tanhf(xl * dr) * norm
                    xr = tanhf(xr * dr) * norm
                }
                let d = vInst[v]
                xl *= balL[d]
                xr *= balR[d]
                l += xl
                r += xr
                send += (xl + xr) * 0.5 * sendAmt[d]
                vPos[v] = pos + vRate[v]
            }
        }
        let wet = reverb.process(send * roomSend[kitIndex])
        l += wet.0 * reverbLevel * 0.9
        r += wet.1 * reverbLevel * 0.9
        return comp.process(l * 0.8, r * 0.8)
    }
}
