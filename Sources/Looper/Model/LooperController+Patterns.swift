import Foundation

/// Pattern editor: user patterns are editable copies of built-in patterns.
extension LooperController {
    var currentIsUserPattern: Bool { RhythmLibrary.isUser(settings.rhythmPattern) }

    /// Copies the current pattern into a free user slot and selects it. Returns the new pattern index.
    @discardableResult
    func forkPattern(named name: String? = nil) -> Int? {
        guard let slot = UserPatternStore.shared.freeSlot else {
            flash("All \(UserPatternStore.slots) user pattern slots are used")
            return nil
        }
        let src = settings.rhythmPattern
        let p = RhythmLibrary.pattern(src)
        let steps = max(1, min(kMaxSteps, p.steps))
        func grid(_ v: Int) -> [[Float]] {
            (0..<kInstrumentCount).map { d in (0..<steps).map { core.rhythm.cell(pattern: src, variation: v, drum: d, step: $0) } }
        }
        let u = UserPattern(name: name ?? "\(p.name) (edit)", signature: p.signature, beats: p.beats, steps: steps,
                            tempo: p.tempo, swing: p.swing, a: grid(0), b: grid(1))
        UserPatternStore.shared.set(slot, u)
        core.rhythm.loadUser(slot: slot, u)
        let idx = RhythmLibrary.builtinCount + slot
        settings.rhythmPattern = idx
        patternsVersion += 1
        flash("New pattern: \(u.name)")
        return idx
    }

    /// Cycles one step: off → accent → normal → ghost → off. Editing a built-in pattern makes a copy first.
    func toggleCell(drum: Int, step: Int) {
        var idx = settings.rhythmPattern
        if !RhythmLibrary.isUser(idx) {
            guard let n = forkPattern() else { return }
            idx = n
        }
        let slot = idx - RhythmLibrary.builtinCount
        guard var u = UserPatternStore.shared.items[slot], drum < kInstrumentCount, step < u.steps else { return }
        let v = settings.rhythmVariation == 0 ? 0 : 1
        var g = v == 0 ? u.a : u.b
        while g.count < kInstrumentCount { g.append(Array(repeating: 0, count: u.steps)) }
        if g[drum].count < u.steps { g[drum] += Array(repeating: 0, count: u.steps - g[drum].count) }
        let cur = g[drum][step]
        let next: Float = cur <= 0 ? 1.0 : (cur >= 0.9 ? 0.6 : (cur >= 0.5 ? 0.3 : 0))
        g[drum][step] = next
        if v == 0 { u.a = g } else { u.b = g }
        UserPatternStore.shared.set(slot, u)
        core.rhythm.setCell(pattern: idx, variation: v, drum: drum, step: step, value: next)
        patternsVersion += 1
    }

    /// Clears the current variation of a user pattern.
    func clearPatternVariation() {
        let idx = settings.rhythmPattern
        guard RhythmLibrary.isUser(idx) else { return }
        let slot = idx - RhythmLibrary.builtinCount
        guard var u = UserPatternStore.shared.items[slot] else { return }
        let empty = Array(repeating: Array(repeating: Float(0), count: u.steps), count: kInstrumentCount)
        if settings.rhythmVariation == 0 { u.a = empty } else { u.b = empty }
        UserPatternStore.shared.set(slot, u)
        core.rhythm.loadUser(slot: slot, u)
        patternsVersion += 1
    }

    func renameUserPattern(_ idx: Int, to name: String) {
        let slot = idx - RhythmLibrary.builtinCount
        guard RhythmLibrary.isUser(idx), var u = UserPatternStore.shared.items[slot] else { return }
        let t = name.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        u.name = String(t.prefix(40))
        UserPatternStore.shared.set(slot, u)
        patternsVersion += 1
    }

    func deleteUserPattern(_ idx: Int) {
        let slot = idx - RhythmLibrary.builtinCount
        guard RhythmLibrary.isUser(idx) else { return }
        let name = UserPatternStore.shared.items[slot]?.name ?? ""
        UserPatternStore.shared.set(slot, nil)
        core.rhythm.loadUser(slot: slot, nil)
        if settings.rhythmPattern == idx { settings.rhythmPattern = 0 }
        patternsVersion += 1
        flash("Deleted \(name)")
    }
}
