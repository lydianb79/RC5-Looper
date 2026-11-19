import Foundation

/// Song mode: plays the memories of `song` one after the other. The next memory is read
/// into the engine's spare buffers during the last repeat of the current one and swapped
/// in exactly at the loop point, so the music never stops.
extension LooperController {
    func addSongStep(memory: Int? = nil) {
        song.steps.append(SongStep(memory: memory ?? memoryIndex, repeats: 2))
    }

    func removeSongStep(_ id: UUID) {
        song.steps.removeAll { $0.id == id }
    }

    func moveSongStep(_ id: UUID, by delta: Int) {
        guard let i = song.steps.firstIndex(where: { $0.id == id }) else { return }
        let j = max(0, min(song.steps.count - 1, i + delta))
        guard i != j else { return }
        let s = song.steps.remove(at: i)
        song.steps.insert(s, at: j)
    }

    private func playable(_ step: Int) -> Bool {
        step >= 0 && step < song.steps.count && store.hasAudio(song.steps[step].memory)
    }

    func startSong(from step: Int = 0) {
        guard let first = (step..<song.steps.count).first(where: { playable($0) }) else {
            flash("Add memories with a loop to the song first")
            return
        }
        let m = song.steps[first].memory
        if m != memoryIndex {
            if dirty {
                flash("Write (⌘S) or clear the current memory before starting the song")
                return
            }
            jumpToMemory(m)
        }
        core.send(.cancelSwap)
        if core.state == .playing || core.state == .overdubbing { core.send(.restart) }
        waitForCore()
        songStep = first
        songRepeat = 0
        songPrepared = false
        songActive = true
        songLastSwap = core.swapGeneration
        if core.state == .stopped { core.send(.play) }
        flash("SONG ▶ \(first + 1): \(settings.name)")
    }

    func stopSong() {
        guard songActive else { return }
        songActive = false
        songPrepared = false
        core.send(.cancelSwap)
        flash("SONG STOPPED")
    }

    private func nextStep(after i: Int) -> Int? {
        var j = i + 1
        var guardCount = 0
        while guardCount <= song.steps.count {
            if j >= song.steps.count {
                guard song.repeatSong else { return nil }
                j = 0
            }
            if playable(j) { return j }
            j += 1
            guardCount += 1
        }
        return nil
    }

    /// Called from the UI timer.
    func songTick() {
        guard songActive else { return }
        let st = core.state
        if st == .stopped || st == .empty {
            if !core.swapPending {
                songActive = false
                songPrepared = false
            }
            return
        }
        // a swap happened at the loop point → the next step is playing now
        if core.swapGeneration != songLastSwap {
            songLastSwap = core.swapGeneration
            if let n = nextStep(after: songStep) {
                songStep = n
                adoptSwappedMemory(song.steps[n].memory)
            }
            songPrepared = false
        }
        guard songStep < song.steps.count else { return }
        let reps = max(1, song.steps[songStep].repeats)
        let rep = min(reps - 1, core.wrapCount)
        if rep != songRepeat { songRepeat = rep }
        // in the last repeat: get the next memory ready (or stop at the end of the song)
        if !songPrepared && core.wrapCount >= reps - 1 {
            songPrepared = true
            if let n = nextStep(after: songStep) {
                preload(memory: song.steps[n].memory)
            } else {
                core.send(.stopAtLoopEnd)
            }
        }
    }

    /// Reads a memory into the spare buffers and arms the swap.
    private func preload(memory m: Int) {
        guard let s = store.loadSettings(m) else { return }
        do {
            let st = core.stack
            let len = try MemoryStore.readAudio(from: store.audioURL(m), left: st.preloadL, right: st.preloadR,
                                                capacity: st.capacity, sampleRate: core.sampleRate)
            var lens = [0, 0]
            for t in 0..<2 where store.hasTrack(m, t) {
                let tr = core.sub(t).stack
                lens[t] = (try? MemoryStore.readAudio(from: store.trackURL(m, t), left: tr.preloadL, right: tr.preloadR,
                                                      capacity: tr.capacity, sampleRate: core.sampleRate)) ?? 0
            }
            var info = SwapInfo()
            info.length = len
            info.trackLengths = (lens[0], lens[1])
            info.loopTempo = s.loopTempo > 0 ? s.loopTempo : s.tempo
            info.tempo = s.tempo
            info.pattern = s.rhythmPattern
            info.variation = s.rhythmVariation
            info.kit = s.rhythmKit
            info.rhythmOn = s.rhythmOn
            core.send(.armSwap(info))
        } catch {
            flash("Song: could not load memory \(m + 1)")
        }
    }

    /// The engine already plays memory `m` (swapped in): take over its settings without reloading audio.
    private func adoptSwappedMemory(_ m: Int) {
        loading = true
        setMemoryIndexForSong(m)
        settings = store.loadSettings(m) ?? MemorySettings.defaults(for: m)
        lastLoopLength = core.loopLength
        lastGeneration = core.loopGeneration
        dirty = false
        needWave = true
        loading = false
    }
}
