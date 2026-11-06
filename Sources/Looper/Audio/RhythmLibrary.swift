import Foundation

/// Drum instruments of the built-in rhythm generator.
/// Letters used in pattern strings:
/// K kick, S snare, H closed hat, O open hat, R ride, C crash,
/// T high tom, L low tom, P rim/click, A clap, Z shaker/brush
let kInstrumentCount = 11
let kMaxSteps = 48

enum DrumLetter {
    static let map: [Character: Int] = [
        "K": 0, "S": 1, "H": 2, "O": 3, "R": 4, "C": 5,
        "T": 6, "L": 7, "P": 8, "A": 9, "Z": 10,
    ]
}

struct PatternDef {
    let name: String
    let category: String
    let signature: String
    let beats: Double      // measure length in quarter notes
    let steps: Int         // grid steps per measure
    let tempo: Double      // suggested tempo
    let swing: Double      // 0 … 0.5 (delay of odd steps, in steps)
    let a: [String: String]
    let b: [String: String]?

    init(_ name: String, _ category: String, sig: String = "4/4", beats: Double = 4, steps: Int = 16,
         tempo: Double = 120, swing: Double = 0, _ a: [String: String], b: [String: String]? = nil) {
        self.name = name
        self.category = category
        self.signature = sig
        self.beats = beats
        self.steps = min(steps, kMaxSteps)
        self.tempo = tempo
        self.swing = swing
        self.a = a
        self.b = b
    }
}

/// Drum kit voicing parameters, used to pre-render the kit's samples (see DrumSamples.swift).
struct KitParams {
    var kickFreq: Double      // fundamental (Hz)
    var kickSweep: Double     // start pitch multiplier of the pitch drop
    var kickDecay: Double     // body decay (s)
    var kickClick: Double     // beater click 0…1
    var kickDrive: Double     // saturation 1…3
    var snareTone: Double     // shell tone (Hz)
    var snareDecay: Double    // wire / noise decay (s)
    var snareNoise: Double    // 0 = all shell, 1 = all wires
    var snareBrush: Double    // 0 = stick, 1 = brush
    var hatScale: Double      // metallic frequency scale
    var hatDecay: Double      // hi-hat decay multiplier
    var bright: Double        // 0…1 top-end brightness
    var tomPitch: Double      // tom tuning multiplier
    var tomDecay: Double      // tom decay (s)
    var cymbalDecay: Double   // ride/crash decay multiplier
    var room: Double          // reverb send multiplier
    var analog: Double        // 0 = acoustic voicing, 1 = drum-machine voicing
}

enum RhythmLibrary {
    static let kitNames = ["Studio", "Live", "Light", "Heavy", "Rock", "Metal", "Electronic"]

    static let kits: [KitParams] = [
        // Studio – tight, punchy, dry
        KitParams(kickFreq: 52, kickSweep: 3.0, kickDecay: 0.30, kickClick: 0.55, kickDrive: 1.7,
                  snareTone: 185, snareDecay: 0.17, snareNoise: 0.62, snareBrush: 0,
                  hatScale: 1.0, hatDecay: 1.0, bright: 0.70, tomPitch: 1.0, tomDecay: 0.42,
                  cymbalDecay: 1.0, room: 0.8, analog: 0),
        // Live – open, roomy, longer decays
        KitParams(kickFreq: 50, kickSweep: 2.8, kickDecay: 0.42, kickClick: 0.35, kickDrive: 1.3,
                  snareTone: 175, snareDecay: 0.25, snareNoise: 0.66, snareBrush: 0,
                  hatScale: 0.95, hatDecay: 1.25, bright: 0.60, tomPitch: 0.95, tomDecay: 0.60,
                  cymbalDecay: 1.3, room: 1.7, analog: 0),
        // Light – soft kick, brushes on the snare, darker cymbals (jazz / ballads)
        KitParams(kickFreq: 62, kickSweep: 2.2, kickDecay: 0.22, kickClick: 0.12, kickDrive: 1.05,
                  snareTone: 200, snareDecay: 0.30, snareNoise: 0.85, snareBrush: 1,
                  hatScale: 0.9, hatDecay: 0.8, bright: 0.40, tomPitch: 1.12, tomDecay: 0.38,
                  cymbalDecay: 1.1, room: 1.0, analog: 0),
        // Heavy – big low kick, fat snare, dark and wide
        KitParams(kickFreq: 46, kickSweep: 3.4, kickDecay: 0.50, kickClick: 0.60, kickDrive: 2.6,
                  snareTone: 165, snareDecay: 0.30, snareNoise: 0.70, snareBrush: 0,
                  hatScale: 0.9, hatDecay: 1.1, bright: 0.55, tomPitch: 0.85, tomDecay: 0.70,
                  cymbalDecay: 1.4, room: 1.4, analog: 0),
        // Rock – beater attack, cracking snare, bright crash
        KitParams(kickFreq: 50, kickSweep: 3.2, kickDecay: 0.36, kickClick: 0.75, kickDrive: 2.0,
                  snareTone: 195, snareDecay: 0.22, snareNoise: 0.70, snareBrush: 0,
                  hatScale: 1.0, hatDecay: 1.0, bright: 0.75, tomPitch: 0.95, tomDecay: 0.55,
                  cymbalDecay: 1.2, room: 1.1, analog: 0),
        // Metal – clicky tight kick, high snappy snare, bright hats
        KitParams(kickFreq: 58, kickSweep: 3.6, kickDecay: 0.20, kickClick: 1.0, kickDrive: 2.2,
                  snareTone: 230, snareDecay: 0.15, snareNoise: 0.65, snareBrush: 0,
                  hatScale: 1.1, hatDecay: 0.8, bright: 0.90, tomPitch: 1.05, tomDecay: 0.40,
                  cymbalDecay: 1.0, room: 0.7, analog: 0),
        // Electronic – 808 boom kick, 909-style snare, analog metallic hats
        KitParams(kickFreq: 45, kickSweep: 2.3, kickDecay: 0.85, kickClick: 0.25, kickDrive: 1.4,
                  snareTone: 200, snareDecay: 0.18, snareNoise: 0.55, snareBrush: 0,
                  hatScale: 1.0, hatDecay: 0.8, bright: 0.80, tomPitch: 1.15, tomDecay: 0.60,
                  cymbalDecay: 0.9, room: 0.6, analog: 1),
    ]

    /// 57 patterns, each with an A and a B variation (B is derived automatically if not given).
    static let patterns: [PatternDef] = [
        // Rock
        PatternDef("Rock 1", "Rock", tempo: 110, ["K": "x.......x.......", "S": "....x.......x...", "H": "x."]),
        PatternDef("Rock 2", "Rock", tempo: 118, ["K": "x.....x.x.......", "S": "....x.......x...", "H": "x."]),
        PatternDef("Rock 16th", "Rock", tempo: 100, ["K": "x......x..x.....", "S": "....x.......x..g", "H": "xo"]),
        PatternDef("Rock Ride", "Rock", tempo: 124, ["K": "x.......x.x.....", "S": "....x.......x...", "R": "x.o."]),
        PatternDef("Hard Rock", "Rock", tempo: 132, ["K": "x.x...x.x.x...x.", "S": "....x.......x...", "H": "x.", "C": "x..............."]),
        PatternDef("Punk", "Rock", tempo: 180, ["K": "x...", "S": "..x.", "H": "x."]),
        PatternDef("Half Time", "Rock", tempo: 140, ["K": "x......x.x......", "S": "........x.......", "H": "x."]),
        PatternDef("Rock Shuffle", "Rock", steps: 12, tempo: 120, ["K": "x.....x.....", "S": "...x.....x..", "H": "x.x"]),
        // Pop
        PatternDef("Pop 1", "Pop", tempo: 104, ["K": "x.....x.x.......", "S": "....x.......x...", "H": "xo"]),
        PatternDef("Pop 2", "Pop", tempo: 112, ["K": "x.......x..x....", "S": "....x.......x...", "A": "....x.......x...", "H": "x."]),
        PatternDef("Ballad", "Pop", tempo: 72, ["K": "x.......x.......", "P": "....x.......x...", "H": "x."]),
        PatternDef("Pop 16th", "Pop", tempo: 96, ["K": "x..x..x...x.....", "S": "....x.......x...", "Z": "xo", "H": "x."]),
        PatternDef("Disco", "Pop", tempo: 120, ["K": "x...", "S": "....x.......x...", "H": "x...", "O": "..x."]),
        PatternDef("Motown", "Pop", tempo: 132, ["K": "x.......x.......", "S": "x...", "A": "....x.......x...", "H": "x."]),
        // Funk
        PatternDef("Funk 1", "Funk", tempo: 100, ["K": "x.x...x...x.....", "S": "....x..g.g..x..g", "H": "xo"]),
        PatternDef("Funk 2", "Funk", tempo: 96, ["K": "x......x.x....x.", "S": "....x.......x...", "H": "x.x.x.x..xx.x.x.", "O": ".......x........"]),
        PatternDef("Funk Ghost", "Funk", tempo: 92, ["K": "x..x..x...x..x..", "S": "..g.x.g..g..x.g.", "H": "xo"]),
        PatternDef("Linear Funk", "Funk", tempo: 98, ["K": "x..x....x..x....", "S": "....x.......x...", "H": ".xx..xx..xx..xx."]),
        PatternDef("Go-Go", "Funk", tempo: 96, swing: 0.2, ["K": "x.....x...x.....", "S": "....x..g.x..x...", "H": "x.", "P": "x..x..x...x.x..."]),
        // Blues
        PatternDef("Shuffle 1", "Blues", steps: 12, tempo: 120, ["K": "x.....x.....", "S": "...x.....x..", "H": "x.x"]),
        PatternDef("Shuffle 2", "Blues", steps: 12, tempo: 132, ["K": "x..x..x..x..", "S": "...x.....x..", "R": "x.x"]),
        PatternDef("Slow Blues", "Blues", sig: "12/8", steps: 12, tempo: 60, ["K": "x.....x.....", "S": "...x.....x..", "H": "xoo"]),
        PatternDef("Texas Shuffle", "Blues", steps: 12, tempo: 140, ["K": "x.....x.....", "S": "..x..x..x..x", "H": "x..x..x..x.."]),
        // Jazz
        PatternDef("Swing", "Jazz", steps: 12, tempo: 140, ["R": "x..x.xx..x.x", "H": "...x.....x..", "K": "g.....g....."]),
        PatternDef("Fast Swing", "Jazz", steps: 12, tempo: 220, ["R": "x..x.xx..x.x", "H": "...x.....x..", "S": "........g..."]),
        PatternDef("Jazz Waltz", "Jazz", sig: "3/4", beats: 3, steps: 9, tempo: 150, ["R": "x..x.xx..", "H": "...x..x..", "K": "g........"]),
        PatternDef("Brush Ballad", "Jazz", steps: 12, tempo: 66, ["Z": "x.x", "S": "...o.....o..", "K": "g.....g....."]),
        // Latin
        PatternDef("Bossa Nova", "Latin", tempo: 130, ["K": "x..xx..xx..xx..x", "P": "x..x..x...x..x..", "H": "o."]),
        PatternDef("Samba", "Latin", tempo: 100, ["K": "x..xx..xx..xx..x", "Z": "xooo", "P": "x.x..x.x.x..x.x."]),
        PatternDef("Rumba", "Latin", tempo: 110, ["P": "x..x...x..x.x...", "K": "x..x....x..x....", "L": "......x.......x."]),
        PatternDef("Cha-Cha", "Latin", tempo: 120, ["K": "x.......x.......", "R": "x.", "T": "............x.x.", "L": "........x...x..."]),
        PatternDef("Songo", "Latin", tempo: 110, ["K": "...x..x....x..x.", "S": "..g.g..x.g..x..g", "R": "x.", "L": "......x.......x."]),
        PatternDef("Reggaeton", "Latin", tempo: 95, ["K": "x...", "S": "...x..x....x..x.", "H": "x."]),
        // Reggae
        PatternDef("One Drop", "Reggae", steps: 12, tempo: 75, ["K": "......x.....", "P": "......x.....", "H": "x.x"]),
        PatternDef("Rockers", "Reggae", tempo: 80, ["K": "x.......x.......", "S": "....x.......x...", "H": "x.o."]),
        PatternDef("Steppers", "Reggae", tempo: 80, ["K": "x...", "P": "........x.......", "H": "..x."]),
        // Metal
        PatternDef("Double Kick", "Metal", tempo: 140, ["K": "x", "S": "....x.......x...", "C": "x..."]),
        PatternDef("Thrash", "Metal", tempo: 190, ["K": "x.", "S": "..x.", "H": "x."]),
        PatternDef("Djent", "Metal", tempo: 120, ["K": "x.xx..x.x..xx.x.", "S": "........x.......", "C": "x..."]),
        PatternDef("Blast Beat", "Metal", tempo: 200, ["K": "x.", "S": ".x", "C": "x."]),
        // Electronic
        PatternDef("House", "Electronic", tempo: 124, ["K": "x...", "A": "....x.......x...", "O": "..x.", "Z": "go"]),
        PatternDef("Techno", "Electronic", tempo: 132, ["K": "x...", "H": "..x.", "A": "....x.......x...", "P": "x..x..x..x..x.x."]),
        PatternDef("Boom Bap", "Electronic", tempo: 90, swing: 0.25, ["K": "x......x..x.....", "S": "....x.......x...", "H": "x."]),
        PatternDef("Trap", "Electronic", tempo: 140, ["K": "x......x..x.....", "A": "........x.......", "H": "x.x.x.x.x.xxx.x."]),
        PatternDef("Drum & Bass", "Electronic", tempo: 172, ["K": "x.........x.....", "S": "....x.......x...", "H": "x."]),
        PatternDef("Breakbeat", "Electronic", tempo: 130, ["K": "x.x.......xx....", "S": "....x..x.x..x..x", "H": "x."]),
        // Country
        PatternDef("Train Beat", "Country", tempo: 150, ["K": "x.......x.......", "S": "ggggxgggggggxggg"]),
        PatternDef("Two-Step", "Country", tempo: 160, swing: 0.2, ["K": "x.......x.......", "P": "....x.......x...", "H": "x."]),
        PatternDef("Country Shuffle", "Country", steps: 12, tempo: 120, ["K": "x.....x.....", "S": "...x.....x..", "Z": "x.x"]),
        // Odd meters
        PatternDef("6/8 Ballad", "Odd Meter", sig: "6/8", beats: 3, steps: 12, tempo: 60, ["K": "x...........", "S": "......x.....", "H": "x."]),
        PatternDef("Waltz", "Odd Meter", sig: "3/4", beats: 3, steps: 12, tempo: 140, ["K": "x...........", "S": "....x...x...", "H": "x."]),
        PatternDef("5/4 Groove", "Odd Meter", sig: "5/4", beats: 5, steps: 20, tempo: 110, ["K": "x.......x.x.........", "S": "....x.......x...x...", "H": "x."]),
        PatternDef("7/8 Groove", "Odd Meter", sig: "7/8", beats: 3.5, steps: 14, tempo: 120, ["K": "x.......x.....", "S": "....x.....x...", "H": "x."]),
        // Metronome
        PatternDef("Metronome 4/4", "Metronome", steps: 8, tempo: 120, ["P": "x.o.o.o."], b: ["P": "x.o.o.o.", "Z": "go"]),
        PatternDef("Metronome 3/4", "Metronome", sig: "3/4", beats: 3, steps: 6, tempo: 120, ["P": "x.o.o."], b: ["P": "x.o.o.", "Z": "go"]),
        PatternDef("Metronome 2/4", "Metronome", sig: "2/4", beats: 2, steps: 4, tempo: 120, ["P": "x.o."], b: ["P": "x.o.", "Z": "go"]),
        PatternDef("Metronome 6/8", "Metronome", sig: "6/8", beats: 3, steps: 6, tempo: 90, ["P": "xooxoo"], b: ["P": "xooxoo", "Z": "g"]),
    ]

    static var categories: [String] {
        var seen = Set<String>()
        return patterns.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }

    static func pattern(_ i: Int) -> PatternDef {
        patterns[max(0, min(patterns.count - 1, i))]
    }

    // MARK: Table building

    private static func value(_ c: Character) -> Float {
        switch c {
        case "x", "X": return 1.0
        case "o": return 0.6
        case "g": return 0.3
        default: return 0
        }
    }

    /// Writes one variation grid (instrument x step) into `dst`.
    private static func fill(_ dst: UnsafeMutablePointer<Float>, lines: [String: String], steps: Int) {
        for (key, line) in lines {
            guard let letter = key.first, let inst = DrumLetter.map[letter] else { continue }
            let chars = Array(line)
            guard !chars.isEmpty else { continue }
            let tile = steps % chars.count == 0
            for s in 0..<steps {
                let c: Character
                if tile { c = chars[s % chars.count] } else { c = s < chars.count ? chars[s] : "." }
                dst[inst * kMaxSteps + s] = value(c)
            }
        }
    }

    /// Builds a flat table: [pattern][variation][instrument][step].
    static func buildTable() -> UnsafeMutablePointer<Float> {
        let per = kInstrumentCount * kMaxSteps
        let table = UnsafeMutablePointer<Float>.allocate(capacity: patterns.count * 2 * per)
        table.initialize(repeating: 0, count: patterns.count * 2 * per)
        for (i, p) in patterns.enumerated() {
            let a = table + (i * 2) * per
            let b = table + (i * 2 + 1) * per
            fill(a, lines: p.a, steps: p.steps)
            if let bl = p.b {
                fill(b, lines: bl, steps: p.steps)
            } else {
                // Derived B variation: busier ending of the bar.
                b.update(from: a, count: per)
                let n = p.steps
                if n >= 8 {
                    let hatRow = 2 * kMaxSteps
                    let hasHat = (0..<n).contains { a[hatRow + $0] > 0 }
                    if hasHat {
                        b[hatRow + n - 2] = 0
                        b[3 * kMaxSteps + n - 2] = 0.8     // open hat
                    }
                    if b[0 * kMaxSteps + n - 3] == 0 { b[0 * kMaxSteps + n - 3] = 0.7 }   // extra kick
                    if b[1 * kMaxSteps + n - 1] == 0 { b[1 * kMaxSteps + n - 1] = 0.3 }   // ghost snare
                    if b[6 * kMaxSteps + n - 2] == 0 && p.category != "Jazz" { b[6 * kMaxSteps + n - 2] = 0.5 }
                }
            }
        }
        return table
    }
}
