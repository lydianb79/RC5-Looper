import Foundation

/// Transport state of the looper (lives on the audio thread, mirrored to the UI).
enum LoopState: Int {
    case empty          // no loop recorded
    case armed          // waiting for count-in / next measure before recording
    case autoRecArmed   // waiting for input signal (Auto Rec)
    case recording
    case playing
    case overdubbing
    case stopped        // loop exists but is stopped

    var label: String {
        switch self {
        case .empty: return "EMPTY"
        case .armed: return "STANDBY"
        case .autoRecArmed: return "AUTO REC"
        case .recording: return "REC"
        case .playing: return "PLAY"
        case .overdubbing: return "DUB"
        case .stopped: return "STOP"
        }
    }
}

enum RecAction: Int, Codable, CaseIterable, Identifiable {
    case recDubPlay, recPlayDub
    var id: Int { rawValue }
    var label: String { self == .recDubPlay ? "REC → DUB → PLAY" : "REC → PLAY → DUB" }
}

enum DubMode: Int, Codable, CaseIterable, Identifiable {
    case overdub, replace
    var id: Int { rawValue }
    var label: String { self == .overdub ? "Overdub" : "Replace" }
}

enum StartMode: Int, Codable, CaseIterable, Identifiable {
    case immediate, fadeIn
    var id: Int { rawValue }
    var label: String { self == .immediate ? "Immediate" : "Fade in" }
}

enum StopMode: Int, Codable, CaseIterable, Identifiable {
    case immediate, fadeOut, loopEnd
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .immediate: return "Immediate"
        case .fadeOut: return "Fade out"
        case .loopEnd: return "Loop end"
        }
    }
}

enum StretchMode: Int, Codable, CaseIterable, Identifiable {
    case keepPitch, varispeed
    var id: Int { rawValue }
    var label: String { self == .keepPitch ? "Keep pitch" : "Varispeed (pitch follows)" }
}

/// Everything that is stored together with a phrase memory (like the RC-5).
struct MemorySettings: Codable, Equatable {
    var name = "INIT MEMORY"
    var recAction = RecAction.recDubPlay
    var dubMode = DubMode.overdub
    var quantize = true
    var autoRec = false
    var countIn = false
    var startMode = StartMode.immediate
    var stopMode = StopMode.immediate
    var fadeSeconds = 2.0
    var oneShot = false
    var reverse = false
    var loopLevel = 1.0          // 0 ... 2 (0–200 %)
    var rhythmOn = false
    var rhythmPattern = 0
    var rhythmVariation = 0      // 0 = A, 1 = B
    var rhythmKit = 0
    var rhythmLevel = 0.7
    var rhythmReverb = 0.2
    var rhythmIntro = false      // one-bar intro (count + fill) before recording
    var rhythmEnding = false     // fill + final hit when stopping
    var tempo = 120.0
    var loopTempo = 0.0          // tempo the loop audio was recorded at (0 = same as tempo)
    var stretchMode = StretchMode.keepPitch
    var loopMeasures = 0
    var savedSeconds = 0.0

    enum CodingKeys: String, CodingKey {
        case name, recAction, dubMode, quantize, autoRec, countIn, startMode, stopMode, fadeSeconds
        case oneShot, reverse, loopLevel, rhythmOn, rhythmPattern, rhythmVariation, rhythmKit
        case rhythmLevel, rhythmReverb, rhythmIntro, rhythmEnding, tempo, loopTempo, stretchMode, loopMeasures, savedSeconds
    }

    static func defaults(for slot: Int) -> MemorySettings {
        var s = MemorySettings()
        s.name = String(format: "MEMORY %02d", slot + 1)
        return s
    }
}

extension MemorySettings {
    /// Tolerant decoding: missing keys fall back to defaults so older files keep loading.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        name = v(.name, name)
        recAction = v(.recAction, recAction)
        dubMode = v(.dubMode, dubMode)
        quantize = v(.quantize, quantize)
        autoRec = v(.autoRec, autoRec)
        countIn = v(.countIn, countIn)
        startMode = v(.startMode, startMode)
        stopMode = v(.stopMode, stopMode)
        fadeSeconds = v(.fadeSeconds, fadeSeconds)
        oneShot = v(.oneShot, oneShot)
        reverse = v(.reverse, reverse)
        loopLevel = v(.loopLevel, loopLevel)
        rhythmOn = v(.rhythmOn, rhythmOn)
        rhythmPattern = v(.rhythmPattern, rhythmPattern)
        rhythmVariation = v(.rhythmVariation, rhythmVariation)
        rhythmKit = v(.rhythmKit, rhythmKit)
        rhythmLevel = v(.rhythmLevel, rhythmLevel)
        rhythmReverb = v(.rhythmReverb, rhythmReverb)
        rhythmIntro = v(.rhythmIntro, rhythmIntro)
        rhythmEnding = v(.rhythmEnding, rhythmEnding)
        tempo = v(.tempo, tempo)
        loopTempo = v(.loopTempo, loopTempo)
        stretchMode = v(.stretchMode, stretchMode)
        loopMeasures = v(.loopMeasures, loopMeasures)
        savedSeconds = v(.savedSeconds, savedSeconds)
    }
}

/// UI snapshot of the realtime state, refreshed ~30x per second.
struct Snapshot: Equatable {
    var state: LoopState = .empty
    var position: Double = 0
    var loopSeconds: Double = 0
    var recordSeconds: Double = 0
    var measure = 1
    var beat = 1
    var beatsPerMeasure = 4
    var totalMeasures = 0
    var beatPhase: Double = 0
    var countdownBeats = 0
    var canUndo = false
    var canRedo = false
    var inLevel: Float = 0
    var outLevel: Float = 0
    var waitingQuantize = false
    var stopping = false
    var rhythmRunning = false
    var tempo: Double = 120
    var loopTempo: Double = 0
    var playbackRate: Double = 1
}

struct MemoryInfo: Identifiable, Equatable {
    let id: Int
    var name: String
    var seconds: Double?
}
