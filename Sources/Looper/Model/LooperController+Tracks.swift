import Foundation

/// Tracks 2 / 3, multi-level undo, ×2, mutes and fade-out.
extension LooperController {
    func trackPress(_ t: Int) {
        guard core.loopLength > 0 else { flash("Record track 1 first"); return }
        guard !settings.reverse else { flash("Tracks 2 and 3 can't record while Reverse is on"); return }
        let st = snapshot.tracks[t].state
        core.send(.trackPress(t))
        dirty = true
        switch st {
        case 0: flash("TRACK \(t + 2) REC")
        case 1: flash("TRACK \(t + 2) closes at the loop end")
        case 2: flash("TRACK \(t + 2) OVERDUB")
        default: flash("TRACK \(t + 2) PLAY")
        }
    }

    func trackUndo(_ t: Int) {
        core.send(.trackUndo(t))
        dirty = true
        flash("TRACK \(t + 2) UNDO")
    }

    func trackRedo(_ t: Int) {
        core.send(.trackRedo(t))
        dirty = true
        flash("TRACK \(t + 2) REDO")
    }

    func trackClear(_ t: Int) {
        core.send(.trackClear(t))
        dirty = true
        flash("TRACK \(t + 2) CLEAR")
    }

    func toggleTrackMute(_ t: Int) {
        trackMuted[t].toggle()
    }

    func setTrackLevel(_ t: Int, _ v: Double) {
        var l = settings.trackLevels
        while l.count < 2 { l.append(1) }
        l[t] = v
        settings.trackLevels = l
    }

    func undo() {
        guard snapshot.undoDepth > 0 else { flash("Nothing to undo"); return }
        core.send(.undo)
        flash("UNDO (\(snapshot.undoDepth - 1) left)")
    }

    func redo() {
        guard snapshot.redoDepth > 0 else { flash("Nothing to redo"); return }
        core.send(.redo)
        flash("REDO")
    }

    /// ×2: doubles the loop length (the loop is copied behind itself) so you can overdub a longer phrase.
    func doubleLoop() {
        let L = core.loopLength
        guard L > 0 else { flash("No loop to double"); return }
        guard L * 2 <= core.capacity else { flash("The loop is too long to double"); return }
        guard snapshot.state != .recording else { return }
        core.send(.doubleLoop)
        if settings.loopMeasures > 0 { settings.loopMeasures *= 2 }
        dirty = true
        flash("×2  LOOP DOUBLED")
    }

    func toggleDrop() {
        allMuted.toggle()
        flash(allMuted ? "LOOP MUTED" : "LOOP BACK")
    }

    func toggleMainMute() { mainMuted.toggle() }

    func fadeOut() {
        guard snapshot.state == .playing || snapshot.state == .overdubbing else { return }
        core.send(.fadeOut)
        flash("FADE OUT")
    }

    /// Waveforms of tracks 2 and 3 (one cycle of each is drawn across its own lane).
    func updateTrackWaves() {
        var waves: [[Float]] = [[], []]
        for t in 0..<2 {
            let tr = core.sub(t)
            let len = tr.state == .recording ? tr.recMaxIdx + 1 : (tr.hasContent ? tr.length : 0)
            guard len > 1 else { continue }
            let bins = 240
            var out = [Float](repeating: 0, count: bins)
            for b in 0..<bins {
                let s0 = b * len / bins
                let s1 = max(s0 + 1, (b + 1) * len / bins)
                let step = max(1, (s1 - s0) / 48)
                var m: Float = 0
                var j = s0
                while j < s1 && j < len {
                    let v = tr.stack.mix(j)
                    m = max(m, abs(v.0), abs(v.1))
                    j += step
                }
                out[b] = min(1, m)
            }
            waves[t] = out
        }
        if waves != trackWaves { trackWaves = waves }
    }
}

/// The on-screen Record button only records; overdub, play and the rest have their own buttons.
/// (R / Return keep the RC-5 pedal behaviour: record → overdub → play.)
extension LooperController {
    var canRecord: Bool {
        switch snapshot.state {
        case .empty, .armed, .autoRecArmed, .recording: return true
        default: return false
        }
    }

    var recordLabel: String {
        switch snapshot.state {
        case .empty: return settings.autoRec ? "Arm auto rec" : "Record"
        case .armed, .autoRecArmed: return "Cancel"
        case .recording:
            return settings.loopLength > 0 ? "Recording…" : "Close loop"
        default: return "Record"
        }
    }

    var recordHint: String {
        switch snapshot.state {
        case .empty: return settings.countIn ? "starts after the count-in" : "R or Return"
        case .armed, .autoRecArmed: return "waiting to start"
        case .recording:
            if settings.loopLength > 0 { return "stops after \(LoopLengthOptions.label(settings.loopLength))" }
            return settings.recAction == .recDubPlay && !settings.oneShot ? "then overdub" : "then play"
        default: return "clear the loop to record a new one"
        }
    }

    func recordOnly() {
        switch core.state {
        case .empty:
            if !inputGranted { flash("No audio input — check microphone permission") }
            core.send(.armRecording)
        case .armed, .autoRecArmed:
            core.send(.cancelArm)
        case .recording:
            let next: LoopState = settings.recAction == .recDubPlay && !settings.oneShot ? .overdubbing : .playing
            core.send(.finishRecording(next: next))
        default:
            flash("Use Overdub to add to the loop, or Clear to record a new one")
        }
    }

    func overdubToggle() {
        switch core.state {
        case .playing: core.send(.startOverdub)
        case .overdubbing: core.send(.stopOverdub)
        case .stopped:
            core.send(.play)
            core.send(.startOverdub)
        default: break
        }
    }
}

extension LooperController {
    func toggleFX(input: Bool) {
        if input { settings.inputFX.on.toggle() } else { settings.loopFX.on.toggle() }
        let f = input ? settings.inputFX : settings.loopFX
        flash("\(input ? "Input" : "Loop") FX \(f.on ? "ON" : "BYPASSED") · \(f.activeCount) active")
    }
}
