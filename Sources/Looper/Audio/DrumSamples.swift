import AVFoundation
import Foundation
import os

// Sample-based drum engine.
//
// Acoustic kits use real multi-mic recordings bundled in Resources/Drums
// (Karoryfer "Big Rusty Drums", CC0): 3 velocity layers x 2 round-robin takes per
// drum, tuned / saturated per kit at load time. Clap, shaker and the Electronic kit
// (and everything, if the recordings are missing) are rendered offline with the
// synthesis below. At playback time the audio thread only mixes samples through a
// 32-voice pool, so cymbals ring out naturally.

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

// MARK: - Recorded samples

enum RecordedDrums {
    /// Bundled recording groups per drum (nil = synthesized).
    static func group(for drum: Int, kit: KitParams) -> String? {
        switch drum {
        case 0: return "kick"
        case 1: return kit.snareSet
        case 2: return kit.hatSet
        case 3: return "hat_open"
        case 4: return "ride"
        case 5: return "crash"
        case 6: return "tom_hi"
        case 7: return "tom_lo"
        case 8: return "sidestick"
        default: return nil
        }
    }

    /// Mix balance of the recordings.
    static let gain: [String: Float] = [
        "kick": 1.0, "snare": 0.85, "snare_rim": 0.85, "snare_brush": 0.95, "sidestick": 0.6,
        "hat_closed": 0.42, "hat_brush": 0.5, "hat_open": 0.4, "ride": 0.38, "crash": 0.45,
        "tom_hi": 0.75, "tom_lo": 0.8,
    ]

    static var directory: URL? {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let res = Bundle.main.resourceURL { candidates.append(res.appendingPathComponent("Drums")) }
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        candidates.append(cwd.appendingPathComponent("Resources/Drums"))
        return candidates.first { fm.fileExists(atPath: $0.appendingPathComponent("kick_v1_rr1.wav").path) }
    }

    /// Loads one take, resampled to `sr` (times `pitch`), with optional saturation.
    static func load(_ dir: URL, group: String, layer: Int, rr: Int, sr: Double, pitch: Double, drive: Double) -> ([Float], [Float])? {
        let url = dir.appendingPathComponent("\(group)_v\(layer + 1)_rr\(rr + 1).wav")
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let fmt = file.processingFormat
        let n = Int(file.length)
        guard n > 0, let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n)),
              (try? file.read(into: buf)) != nil, let ch = buf.floatChannelData else { return nil }
        let frames = Int(buf.frameLength)
        let c0 = ch[0]
        let c1 = fmt.channelCount > 1 ? ch[1] : ch[0]
        let step = fmt.sampleRate / sr * pitch          // source frames per output frame
        let outLen = max(1, Int(Double(frames - 1) / step))
        let g = gain[group] ?? 0.8
        let norm = drive > 1.001 ? Float(1 / tanh(drive)) : 1
        var l = [Float](repeating: 0, count: outLen)
        var r = [Float](repeating: 0, count: outLen)
        for i in 0..<outLen {
            let x = Double(i) * step
            let j = Int(x)
            let j1 = min(j + 1, frames - 1)
            let f = Float(x - Double(j))
            var a = c0[j] + (c0[j1] - c0[j]) * f
            var b = c1[j] + (c1[j1] - c1[j]) * f
            if drive > 1.001 {
                a = tanhf(a * Float(drive)) * norm
                b = tanhf(b * Float(drive)) * norm
            }
            l[i] = a * g
            r[i] = b * g
        }
        return (l, r)
    }
}

// MARK: - Sample bank

/// All drum samples in one contiguous buffer: [kit][drum][velocity layer][round robin].
final class SampleBank {
    static let layers = 3
    static let variants = 2
    let data: UnsafeMutablePointer<Float>
    let offL: UnsafeMutablePointer<Int>
    let offR: UnsafeMutablePointer<Int>
    let len: UnsafeMutablePointer<Int>
    let slots: Int
    let usesRecordings: Bool

    init(sampleRate: Double, kits: [KitParams]) {
        let dir = RecordedDrums.directory
        var unique: [([Float], [Float])] = []      // each distinct take is stored once
        var cache: [String: Int] = [:]
        var slotTake: [Int] = []                   // slot -> index in `unique`
        var recorded = false
        for (k, kit) in kits.enumerated() {
            for d in 0..<kInstrumentCount {
                for layer in 0..<SampleBank.layers {
                    for v in 0..<SampleBank.variants {
                        if kit.sampled, let dir, let group = RecordedDrums.group(for: d, kit: kit) {
                            let tuned = d == 0 || d == 1 || d == 6 || d == 7
                            let driven = d == 0 || d == 1
                            let pitch = tuned ? kit.pitch : 1
                            let drive = driven ? kit.drive : 1
                            let key = "\(group)|\(layer)|\(v)|\(pitch)|\(drive)"
                            if let idx = cache[key] {
                                slotTake.append(idx)
                                recorded = true
                                continue
                            }
                            if let s = RecordedDrums.load(dir, group: group, layer: layer, rr: v, sr: sampleRate,
                                                          pitch: pitch, drive: drive) {
                                unique.append(s)
                                cache[key] = unique.count - 1
                                slotTake.append(unique.count - 1)
                                recorded = true
                                continue
                            }
                        }
                        // synthesized: velocity layers share the two takes, loudness comes from the gain
                        let key = "synth|\(k)|\(d)|\(v)"
                        if let idx = cache[key] {
                            slotTake.append(idx)
                        } else {
                            unique.append(DrumVoices.render(d, kit: kit, sr: sampleRate, variant: v))
                            cache[key] = unique.count - 1
                            slotTake.append(unique.count - 1)
                        }
                    }
                }
            }
        }
        let count = slotTake.count
        let total = unique.reduce(0) { $0 + $1.0.count + $1.1.count }
        let buf = UnsafeMutablePointer<Float>.allocate(capacity: max(1, total))
        var takeL: [Int] = []
        var takeR: [Int] = []
        var takeLen: [Int] = []
        var pos = 0
        for s in unique {
            takeL.append(pos)
            (buf + pos).initialize(from: s.0, count: s.0.count)
            pos += s.0.count
            takeR.append(pos)
            (buf + pos).initialize(from: s.1, count: s.1.count)
            pos += s.1.count
            takeLen.append(min(s.0.count, s.1.count))
        }
        let ol = UnsafeMutablePointer<Int>.allocate(capacity: count)
        let orr = UnsafeMutablePointer<Int>.allocate(capacity: count)
        let ln = UnsafeMutablePointer<Int>.allocate(capacity: count)
        for (i, t) in slotTake.enumerated() {
            ol[i] = takeL[t]
            orr[i] = takeR[t]
            ln[i] = takeLen[t]
        }
        data = buf
        offL = ol
        offR = orr
        len = ln
        slots = count
        usesRecordings = recorded
    }

    static func slot(kit: Int, drum: Int, layer: Int, variant: Int) -> Int {
        ((kit * kInstrumentCount + drum) * layers + layer) * variants + variant
    }
}

// MARK: - Realtime sample player

/// Plays the sample bank on the audio thread (no allocation, no blocking).
final class DrumSynth {
    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private var pendingBank: SampleBank?     // set by the render thread under `lock`
    private var bank: SampleBank?            // audio-thread copy, keeps the memory alive
    private var data: UnsafeMutablePointer<Float>
    private var offL: UnsafeMutablePointer<Int>
    private var offR: UnsafeMutablePointer<Int>
    private var lens: UnsafeMutablePointer<Int>
    private(set) var ready = false

    private let maxVoices = 32
    private let vOn: UnsafeMutablePointer<Int>
    private let vSlot: UnsafeMutablePointer<Int>
    private let vPos: UnsafeMutablePointer<Int>
    private let vInst: UnsafeMutablePointer<Int>
    private let vGain: UnsafeMutablePointer<Float>
    private let vRel: UnsafeMutablePointer<Float>
    private let vRelStep: UnsafeMutablePointer<Float>
    private let panL: UnsafeMutablePointer<Float>
    private let panR: UnsafeMutablePointer<Float>
    private let roundRobin: UnsafeMutablePointer<Int>
    private let roomSend: UnsafeMutablePointer<Float>
    private let sampledKit: UnsafeMutablePointer<Int>
    private let kitCount: Int
    private var kitIndex = 0
    private var rng: UInt32 = 0x1234_5678
    private let chokeStep: Float
    let reverb: Reverb
    var reverbLevel: Float = 0.2

    init(sampleRate: Double) {
        let lk = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        lk.initialize(to: os_unfair_lock())
        lock = lk
        // placeholders until the bank is rendered
        let dummyF = UnsafeMutablePointer<Float>.allocate(capacity: 1)
        dummyF.initialize(to: 0)
        let dummyI = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        dummyI.initialize(to: 0)
        data = dummyF
        offL = dummyI
        offR = dummyI
        lens = dummyI
        func f(_ n: Int) -> UnsafeMutablePointer<Float> {
            let p = UnsafeMutablePointer<Float>.allocate(capacity: n)
            p.initialize(repeating: 0, count: n)
            return p
        }
        func i(_ n: Int) -> UnsafeMutablePointer<Int> {
            let p = UnsafeMutablePointer<Int>.allocate(capacity: n)
            p.initialize(repeating: 0, count: n)
            return p
        }
        vOn = i(32); vSlot = i(32); vPos = i(32); vInst = i(32)
        vGain = f(32); vRel = f(32); vRelStep = f(32)
        panL = f(kInstrumentCount); panR = f(kInstrumentCount)
        roundRobin = i(kInstrumentCount)
        let kits = RhythmLibrary.kits
        kitCount = kits.count
        roomSend = f(kits.count)
        sampledKit = i(kits.count)
        chokeStep = Float(1.0 / (0.012 * sampleRate))
        reverb = Reverb(sampleRate: sampleRate)
        // all stored properties initialised
        let pans: [Float] = [0, 0, 0.28, 0.28, -0.32, 0.35, -0.22, 0.25, 0.05, 0, 0.4]
        for d in 0..<kInstrumentCount {
            panL[d] = 1 - max(0, pans[d])
            panR[d] = 1 + min(0, pans[d])
        }
        for (k, kit) in kits.enumerated() {
            roomSend[k] = Float(kit.room)
            sampledKit[k] = kit.sampled ? 1 : 0
        }

        let sr = sampleRate
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let built = SampleBank(sampleRate: sr, kits: kits)
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
            data = b.data
            offL = b.offL
            offR = b.offR
            lens = b.len
            if !b.usesRecordings {
                for k in 0..<kitCount { sampledKit[k] = 0 }
            }
            ready = true
        }
        os_unfair_lock_unlock(lock)
    }

    func setKit(_ i: Int) { kitIndex = max(0, min(kitCount - 1, i)) }

    @inline(__always) private func random() -> Float {
        rng ^= rng << 13
        rng ^= rng >> 17
        rng ^= rng << 5
        return Float(rng) / Float(UInt32.max)
    }

    func trigger(_ d: Int, _ velocity: Float) {
        guard ready, d >= 0, d < kInstrumentCount else { return }
        // closed hat chokes the open hat
        if d == 2 {
            for v in 0..<maxVoices where vOn[v] != 0 && vInst[v] == 3 && vRelStep[v] == 0 {
                vRelStep[v] = chokeStep
            }
        }
        // free voice, otherwise steal the oldest
        var slot = -1
        var oldest = -1
        var oldestPos = -1
        for v in 0..<maxVoices {
            if vOn[v] == 0 { slot = v; break }
            if vPos[v] > oldestPos { oldestPos = vPos[v]; oldest = v }
        }
        if slot < 0 { slot = max(0, oldest) }
        let variant = roundRobin[d]
        roundRobin[d] = (variant + 1) % SampleBank.variants
        vOn[slot] = 1
        let vel = max(0.05, min(1, velocity))
        let layer = vel < 0.45 ? 0 : (vel < 0.8 ? 1 : 2)
        vSlot[slot] = SampleBank.slot(kit: kitIndex, drum: d, layer: layer, variant: variant)
        vPos[slot] = 0
        vInst[slot] = d
        vRel[slot] = 1
        vRelStep[slot] = 0
        // recorded layers already carry the dynamics; synthesized drums get a velocity curve
        let recordedHit = sampledKit[kitIndex] != 0 && d <= 8
        let nominal: Float = layer == 0 ? 0.4 : (layer == 1 ? 0.7 : 1.0)
        let g = recordedHit ? sqrtf(vel / nominal) : powf(vel, 1.4)
        vGain[slot] = g * (0.95 + 0.1 * random())
    }

    func next() -> (Float, Float) {
        var l: Float = 0
        var r: Float = 0
        var send: Float = 0
        if ready {
            for v in 0..<maxVoices where vOn[v] != 0 {
                let s = vSlot[v]
                let p = vPos[v]
                if p >= lens[s] {
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
                    g *= rel
                }
                let d = vInst[v]
                let xl = data[offL[s] + p] * g
                let xr = data[offR[s] + p] * g
                l += xl * panL[d]
                r += xr * panR[d]
                if d != 0 { send += (xl + xr) * 0.5 }
                vPos[v] = p + 1
            }
        }
        let wet = reverb.process(send * 0.1 * roomSend[kitIndex])
        l += wet.0 * reverbLevel * 1.5
        r += wet.1 * reverbLevel * 1.5
        return (l * 0.85, r * 0.85)
    }
}
