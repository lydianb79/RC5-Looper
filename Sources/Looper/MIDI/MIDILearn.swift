import Foundation

/// Actions that can be assigned to any MIDI note, CC or program change ("MIDI learn").
enum MIDIAction: String, CaseIterable, Identifiable, Codable {
    case recordDub, playStop, stop, undo, redo, clear, rhythm, tap, variation
    case memoryUp, memoryDown, track2, track3, track4, track5, mute, fadeOut, double, write, song

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recordDub: return "Record / Overdub (pedal)"
        case .playStop: return "Play / Stop"
        case .stop: return "Stop"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .clear: return "Clear loop"
        case .rhythm: return "Rhythm on / off"
        case .tap: return "Tap tempo"
        case .variation: return "Rhythm variation A / B"
        case .memoryUp: return "Next memory"
        case .memoryDown: return "Previous memory"
        case .track2: return "Track 2 record / overdub"
        case .track3: return "Track 3 record / overdub"
        case .track4: return "Track 4 record / overdub"
        case .track5: return "Track 5 record / overdub"
        case .mute: return "Mute loop (drop)"
        case .fadeOut: return "Fade out"
        case .double: return "×2 loop length"
        case .write: return "Write memory"
        case .song: return "Song start / stop"
        }
    }
}

/// A learned MIDI message.
struct MIDIBinding: Codable, Equatable {
    enum Kind: String, Codable { case note, cc, program }
    var kind: Kind
    var channel: Int          // 0…15
    var number: Int

    var label: String {
        switch kind {
        case .note: return "Note \(number) · ch \(channel + 1)"
        case .cc: return "CC \(number) · ch \(channel + 1)"
        case .program: return "PC \(number) · ch \(channel + 1)"
        }
    }

    /// The binding a message would create (note on, CC press or program change), if any.
    static func from(status: UInt8, _ d1: UInt8, _ d2: UInt8) -> MIDIBinding? {
        let ch = Int(status & 0x0F)
        switch status & 0xF0 {
        case 0x90 where d2 > 0: return MIDIBinding(kind: .note, channel: ch, number: Int(d1))
        case 0xB0 where d2 >= 64: return MIDIBinding(kind: .cc, channel: ch, number: Int(d1))
        case 0xC0: return MIDIBinding(kind: .program, channel: ch, number: Int(d1))
        default: return nil
        }
    }

    /// Whether a message is the press (true) or release (false) of this binding; nil = not ours.
    func match(status: UInt8, _ d1: UInt8, _ d2: UInt8) -> Bool? {
        guard Int(status & 0x0F) == channel, Int(d1) == number else { return nil }
        switch (kind, status & 0xF0) {
        case (.note, 0x90): return d2 > 0
        case (.note, 0x80): return false
        case (.cc, 0xB0): return d2 >= 64
        case (.program, 0xC0): return true
        default: return nil
        }
    }

    static func loadAll() -> [String: MIDIBinding] {
        guard let data = UserDefaults.standard.data(forKey: "midiBindings"),
              let m = try? JSONDecoder().decode([String: MIDIBinding].self, from: data) else { return [:] }
        return m
    }

    static func saveAll(_ m: [String: MIDIBinding]) {
        if let data = try? JSONEncoder().encode(m) { UserDefaults.standard.set(data, forKey: "midiBindings") }
    }
}
