import Foundation

/// Effect types for the input FX and loop FX slots.
enum FXType: Int, Codable, CaseIterable, Identifiable {
    case filter, delay, reverb, crusher, tapeStop

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .filter: return "Filter"
        case .delay: return "Delay"
        case .reverb: return "Reverb"
        case .crusher: return "Bit Crusher"
        case .tapeStop: return "Tape Stop"
        }
    }

    /// Names of the two knobs.
    var knobs: (String, String) {
        switch self {
        case .filter: return ("Cutoff", "Resonance")
        case .delay: return ("Mix", "Feedback")
        case .reverb: return ("Mix", "Size")
        case .crusher: return ("Mix", "Crush")
        case .tapeStop: return ("Mix", "Time")
        }
    }

    var symbol: String {
        switch self {
        case .filter: return "slider.horizontal.below.square.filled.and.square"
        case .delay: return "repeat"
        case .reverb: return "dot.radiowaves.left.and.right"
        case .crusher: return "square.grid.3x3"
        case .tapeStop: return "recordingtape"
        }
    }
}

/// Delay times (in beats) for the tempo-synced delay.
enum DelayTime: Int, Codable, CaseIterable, Identifiable {
    case sixteenth, eighth, dottedEighth, quarter, dottedQuarter, half
    var id: Int { rawValue }
    var beats: Double {
        switch self {
        case .sixteenth: return 0.25
        case .eighth: return 0.5
        case .dottedEighth: return 0.75
        case .quarter: return 1
        case .dottedQuarter: return 1.5
        case .half: return 2
        }
    }
    var label: String {
        switch self {
        case .sixteenth: return "1/16"
        case .eighth: return "1/8"
        case .dottedEighth: return "1/8."
        case .quarter: return "1/4"
        case .dottedQuarter: return "1/4."
        case .half: return "1/2"
        }
    }
}

/// Stored settings of one FX slot (part of a memory).
struct FXSettings: Codable, Equatable {
    var on = false
    var type: FXType = .filter
    var a = 0.5          // first knob 0…1 (filter: 0.5 = open, left = low-pass, right = high-pass)
    var b = 0.3          // second knob 0…1
    var time: DelayTime = .dottedEighth

    init() {}

    enum CodingKeys: String, CodingKey { case on, type, a, b, time }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        on = (try? c.decode(Bool.self, forKey: .on)) ?? false
        type = (try? c.decode(FXType.self, forKey: .type)) ?? .filter
        a = (try? c.decode(Double.self, forKey: .a)) ?? 0.5
        b = (try? c.decode(Double.self, forKey: .b)) ?? 0.3
        time = (try? c.decode(DelayTime.self, forKey: .time)) ?? .dottedEighth
    }
}

/// One realtime effect slot. Parameters are plain properties written by the UI thread.
/// No allocation after init.
final class FXUnit {
    var on = false
    var type: FXType = .filter
    var a: Float = 0.5
    var b: Float = 0.3
    var delayBeats: Double = 0.75
    var tempo: Double = 120

    private let sr: Double
    private var mix: Float = 0          // smoothed on/off
    private let mixStep: Float

    // filter (TPT state-variable)
    private var ic1L: Float = 0, ic2L: Float = 0, ic1R: Float = 0, ic2R: Float = 0
    private var cut: Float = 0.5

    // delay
    private let dlL: UnsafeMutablePointer<Float>
    private let dlR: UnsafeMutablePointer<Float>
    private let dlLen: Int
    private var dlIdx = 0
    private var dlTime: Float = 0
    private var dlLP: Float = 0, dlLPR: Float = 0

    // reverb
    private let room: RoomReverb
    private var roomSize: Float = -1

    // crusher
    private var holdL: Float = 0, holdR: Float = 0
    private var holdCount: Float = 0

    // tape stop
    private let tsL: UnsafeMutablePointer<Float>
    private let tsR: UnsafeMutablePointer<Float>
    private let tsLen: Int
    private var tsWrite = 0
    private var tsRead: Double = 0
    private var tsSpeed: Double = 1
    private var tsWasOn = false

    init(sampleRate: Double) {
        sr = sampleRate
        mixStep = Float(1.0 / (0.02 * sampleRate))
        let dl = Int(sampleRate * 4.2)
        dlLen = dl
        dlL = .allocate(capacity: dl)
        dlL.initialize(repeating: 0, count: dl)
        dlR = .allocate(capacity: dl)
        dlR.initialize(repeating: 0, count: dl)
        let ts = Int(sampleRate * 6)
        tsLen = ts
        tsL = .allocate(capacity: ts)
        tsL.initialize(repeating: 0, count: ts)
        tsR = .allocate(capacity: ts)
        tsR.initialize(repeating: 0, count: ts)
        room = RoomReverb(sampleRate: sampleRate)
    }

    @inline(__always) func process(_ l: Float, _ r: Float) -> (Float, Float) {
        let target: Float = on ? 1 : 0
        if mix < target { mix = min(target, mix + mixStep) } else if mix > target { mix = max(target, mix - mixStep) }
        if mix == 0 && type != .tapeStop {
            if type == .delay { writeDelay(l * 0, r * 0) }     // let the echo buffer drain silently
            return (l, r)
        }
        switch type {
        case .filter: return filter(l, r)
        case .delay: return delay(l, r)
        case .reverb: return reverb(l, r)
        case .crusher: return crusher(l, r)
        case .tapeStop: return tapeStop(l, r)
        }
    }

    // MARK: Filter: one knob, left = low-pass, right = high-pass, centre = open

    @inline(__always) private func filter(_ l: Float, _ r: Float) -> (Float, Float) {
        cut += (a - cut) * 0.002
        let pos = cut
        let lowpass = pos < 0.5
        let amount = lowpass ? (0.5 - pos) * 2 : (pos - 0.5) * 2         // 0 … 1
        let fc: Float = lowpass ? 18000 * powf(0.0035, amount) : 20 * powf(400, amount)
        let g = tanf(Float.pi * min(fc, Float(sr) * 0.45) / Float(sr))
        let k = 2 - 1.85 * b                                               // resonance
        let a1 = 1 / (1 + g * (g + k))
        let a2 = g * a1
        let a3 = g * a2
        func run(_ x: Float, _ ic1: inout Float, _ ic2: inout Float) -> Float {
            let v3 = x - ic2
            let v1 = a1 * ic1 + a2 * v3
            let v2 = ic2 + a2 * ic1 + a3 * v3
            ic1 = 2 * v1 - ic1
            ic2 = 2 * v2 - ic2
            return lowpass ? v2 : x - k * v1 - v2
        }
        let yl = run(l, &ic1L, &ic2L)
        let yr = run(r, &ic1R, &ic2R)
        let w = mix * min(1, amount * 8)                                   // centre detent = dry
        return (l + (yl - l) * w, r + (yr - r) * w)
    }

    // MARK: Delay: tempo-synced ping-pong

    @inline(__always) private func writeDelay(_ l: Float, _ r: Float) {
        dlL[dlIdx] = l
        dlR[dlIdx] = r
        dlIdx += 1
        if dlIdx >= dlLen { dlIdx = 0 }
    }

    @inline(__always) private func delay(_ l: Float, _ r: Float) -> (Float, Float) {
        let want = Float(min(Double(dlLen - 4), delayBeats * 60 / max(30, tempo) * sr))
        if dlTime == 0 { dlTime = want }
        dlTime += (want - dlTime) * 0.0005
        var rp = Float(dlIdx) - dlTime
        if rp < 0 { rp += Float(dlLen) }
        let i0 = Int(rp)
        let f = rp - Float(i0)
        let i1 = i0 + 1 >= dlLen ? 0 : i0 + 1
        let el = dlL[i0] + (dlL[i1] - dlL[i0]) * f
        let er = dlR[i0] + (dlR[i1] - dlR[i0]) * f
        let fb = min(0.92, b * 0.95)
        dlLP += (el - dlLP) * 0.35
        dlLPR += (er - dlLPR) * 0.35
        // ping-pong: the left echo feeds the right line and vice versa
        let inMono = (l + r) * 0.5 * mix
        writeDelay(inMono + dlLPR * fb, dlLP * fb)
        let wet = a * 1.2
        return (l + el * wet, r + er * wet)
    }

    // MARK: Reverb

    @inline(__always) private func reverb(_ l: Float, _ r: Float) -> (Float, Float) {
        if abs(b - roomSize) > 0.01 {
            roomSize = b
            room.setDecay(0.4 + Double(b) * 3.6)
        }
        let w = room.process((l + r) * 0.5 * mix)
        let wet = a * 1.6
        return (l + w.0 * wet, r + w.1 * wet)
    }

    // MARK: Bit crusher

    @inline(__always) private func crusher(_ l: Float, _ r: Float) -> (Float, Float) {
        let hold = 1 + b * 24
        holdCount += 1
        if holdCount >= hold {
            holdCount -= hold
            let levels = powf(2, 12 - b * 9)
            holdL = (l * levels).rounded() / levels
            holdR = (r * levels).rounded() / levels
        }
        let w = mix * a
        return (l + (holdL - l) * w, r + (holdR - r) * w)
    }

    // MARK: Tape stop: when switched on the sound slows down to a halt; off = back at once

    @inline(__always) private func tapeStop(_ l: Float, _ r: Float) -> (Float, Float) {
        tsL[tsWrite] = l
        tsR[tsWrite] = r
        if on && !tsWasOn {
            tsRead = Double(tsWrite)
            tsSpeed = 1
        }
        tsWasOn = on
        tsWrite += 1
        if tsWrite >= tsLen { tsWrite = 0 }
        guard on else { return (l, r) }
        let time = 0.15 + Double(b) * 2.5
        tsSpeed = max(0, tsSpeed - 1 / (time * sr))
        tsRead += tsSpeed
        if tsRead >= Double(tsLen) { tsRead -= Double(tsLen) }
        let i0 = Int(tsRead)
        let i1 = i0 + 1 >= tsLen ? 0 : i0 + 1
        let f = Float(tsRead - Double(i0))
        let g = Float(min(1, tsSpeed * 3))
        let yl = (tsL[i0] + (tsL[i1] - tsL[i0]) * f) * g
        let yr = (tsR[i0] + (tsR[i1] - tsR[i0]) * f) * g
        let w = max(0.0001, a)
        return (l + (yl - l) * w, r + (yr - r) * w)
    }
}
