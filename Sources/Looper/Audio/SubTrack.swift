import Foundation

/// An extra loop track (tracks 2 and 3), synced to the main loop like on the RC-505.
///
/// Its length is always a whole number of main-loop cycles. Its play position is derived
/// from the main loop: index = (main cycle × main length + main position) mod track length,
/// so all tracks stay locked together through tempo changes, restarts, reverse and ×2.
/// Recording starts right away and, when stopped, runs on to the end of the current main
/// cycle (or, if stopped just after a loop point, ends at once and folds the overhang onto
/// the start). Runs on the audio thread except where noted.
final class SubTrack {
    enum State: Int { case empty, recording, playing, overdubbing }

    let stack: LayerStack
    private(set) var state: State = .empty
    private(set) var length = 0
    private(set) var cycles = 0
    /// UI parameters
    var level: Float = 1
    var muted = false
    var replaceMode = false
    private var muteGain: Float = 1
    private var muteStep: Float = 0.001
    private(set) var gainNow: Float = 1

    // recording
    private var recStartCycle = 0
    private(set) var recMaxIdx = 0
    private(set) var stopRequested = false
    private var nextAfterRec: State = .playing
    private var lastAbs = Int.min
    private(set) var generation = 0

    init(capacity: Int, sampleRate: Double) {
        stack = LayerStack(capacity: capacity)
        muteStep = Float(1.0 / (0.012 * sampleRate))
    }

    var hasContent: Bool { length > 0 && (state == .playing || state == .overdubbing) }

    /// Called once per sample by the core: smooths mute / level.
    @inline(__always) func tickGain() {
        let target: Float = muted ? 0 : 1
        if muteGain < target { muteGain = min(target, muteGain + muteStep) }
        else if muteGain > target { muteGain = max(target, muteGain - muteStep) }
        gainNow = muteGain * level
    }

    @inline(__always) private func mod(_ a: Int, _ m: Int) -> Int {
        let r = a % m
        return r < 0 ? r + m : r
    }

    /// Sample of the track for main-loop index `i` in main cycle `cycle`.
    @inline(__always) func read(cycle: Int, index i: Int, mainLength L: Int) -> (Float, Float) {
        guard hasContent, gainNow > 0 else { return (0, 0) }
        let idx = mod(cycle * L + i, length)
        let m = stack.mix(idx)
        return (m.0 * gainNow, m.1 * gainNow)
    }

    /// Writes input that belongs to main-loop index `i` in main cycle `cycle`.
    @inline(__always) func write(cycle: Int, index i: Int, mainLength L: Int, _ xl: Float, _ xr: Float, fillGaps: Bool) {
        switch state {
        case .recording:
            let rel = (cycle - recStartCycle) * L + i
            guard rel >= 0 && rel < stack.capacity else { return }
            if fillGaps && lastAbs != Int.min && rel > lastAbs + 1 && rel - lastAbs < 16 {
                var k = lastAbs + 1
                while k < rel {
                    stack.baseL[k] = xl
                    stack.baseR[k] = xr
                    k += 1
                }
            }
            if fillGaps && rel == lastAbs { return }
            stack.baseL[rel] = xl
            stack.baseR[rel] = xr
            lastAbs = rel
            if rel > recMaxIdx { recMaxIdx = rel }
        case .overdubbing:
            let abs = cycle * L + i
            if fillGaps && abs == lastAbs { return }
            if fillGaps && lastAbs != Int.min && abs > lastAbs + 1 && abs - lastAbs < 16 {
                var k = lastAbs + 1
                while k < abs {
                    stack.write(mod(k, length), xl, xr, replace: replaceMode)
                    k += 1
                }
            }
            stack.write(mod(abs, length), xl, xr, replace: replaceMode)
            lastAbs = abs
        default:
            break
        }
    }

    // MARK: Transport (audio thread)

    /// Record → (overdub or play) → overdub ↔ play, like the main pedal.
    func press(cycle: Int, position m: Int, mainLength L: Int, dubAfterRecord: Bool) {
        switch state {
        case .empty:
            stack.finishAllJobs()
            if m > 0 {
                stack.baseL.update(repeating: 0, count: min(m, stack.capacity))
                stack.baseR.update(repeating: 0, count: min(m, stack.capacity))
            }
            recStartCycle = cycle
            recMaxIdx = 0
            lastAbs = Int.min
            stopRequested = false
            state = .recording
            generation &+= 1
        case .recording:
            nextAfterRec = dubAfterRecord ? .overdubbing : .playing
            let elapsed = cycle - recStartCycle
            if elapsed >= 1 && m < L / 10 {
                // just past a loop point: end now, fold the overhang onto the start
                stack.foldBase(from: elapsed * L, count: m)
                finish(cycles: elapsed, mainLength: L)
            } else {
                stopRequested = true
            }
        case .playing:
            if stack.beginDub(length: length) {
                lastAbs = Int.min
                state = .overdubbing
                generation &+= 1
            }
        case .overdubbing:
            state = .playing
            generation &+= 1
        }
    }

    /// The main loop wrapped to `cycle`.
    func mainWrapped(cycle: Int, mainLength L: Int) {
        if state == .recording && stopRequested {
            finish(cycles: max(1, cycle - recStartCycle), mainLength: L)
        }
    }

    /// The main loop stopped or was cleared while recording: keep what was recorded.
    func mainStopped(mainLength L: Int) {
        if state == .recording {
            let c = max(1, (recMaxIdx + L - 1) / max(1, L))
            finish(cycles: c, mainLength: L)
        }
        if state == .overdubbing { state = .playing }
    }

    private func finish(cycles c: Int, mainLength L: Int) {
        cycles = max(1, c)
        length = min(stack.capacity, cycles * L)
        stopRequested = false
        state = .playing
        generation &+= 1
        if nextAfterRec == .overdubbing && stack.beginDub(length: length) {
            lastAbs = Int.min
            state = .overdubbing
        }
    }

    func stopOverdub() {
        if state == .overdubbing {
            state = .playing
            generation &+= 1
        }
    }

    func undo() {
        stopOverdub()
        stack.undo()
        generation &+= 1
    }

    func redo() {
        stack.redo()
        generation &+= 1
    }

    func clear() {
        stack.clearAll(baseLength: max(length, recMaxIdx + 1))
        state = .empty
        length = 0
        cycles = 0
        recMaxIdx = 0
        stopRequested = false
        generation &+= 1
    }

    /// ×2 of the main loop (old main length `L`, new = 2 × L).
    func mainDoubled(oldMainLength L: Int) {
        if state == .recording { mainStopped(mainLength: L) }
        stopOverdub()
        guard hasContent else { return }
        if cycles % 2 == 1 {
            if stack.startDouble(length: length) {
                length *= 2
            }
        } else {
            cycles /= 2
        }
        generation &+= 1
    }

    /// A stored track was loaded into the base (or the preloaded base was swapped in).
    func setLoaded(length len: Int, mainLength L: Int) {
        guard len > 0, L > 0 else {
            clear()
            return
        }
        cycles = max(1, Int((Double(len) / Double(L)).rounded()))
        length = min(stack.capacity, cycles * L)
        state = .playing
        stopRequested = false
        generation &+= 1
    }

    /// Recording progress in main cycles (for the UI).
    func recordedCycles(mainLength L: Int) -> Double {
        state == .recording && L > 0 ? Double(recMaxIdx) / Double(L) : 0
    }
}
