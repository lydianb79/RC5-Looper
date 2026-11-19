import Foundation

/// Audio storage of one loop track: a base recording plus a stack of overdub layers.
///
/// * Every overdub goes into its own layer buffer, so the last `maxUndo` overdubs can be
///   undone and redone one by one (multi-level undo history).
/// * Layers that fall out of the history are merged into `base`, and discarded layers are
///   zeroed, incrementally on the audio thread ("jobs"), so no large copy ever blocks it.
///   While a layer is being merged, base + layer stays constant, so playback is unaffected.
/// * Replace-mode overdubs store `input - (everything else)`, so even replacing is undoable.
/// * `startDouble` copies the loop behind itself (×2) in chunks; reads in the not yet copied
///   half are mapped to the first half meanwhile.
/// * A second base buffer can be filled in the background (`preloadL/R`) and swapped in at a
///   loop boundary (seamless memory switching in song mode).
///
/// All mutating methods run on the audio thread (or while no audio thread is running).
final class LayerStack {
    static let bufferCount = 7
    static let maxUndo = 5

    let capacity: Int
    private(set) var baseL: UnsafeMutablePointer<Float>
    private(set) var baseR: UnsafeMutablePointer<Float>
    private(set) var preloadL: UnsafeMutablePointer<Float>
    private(set) var preloadR: UnsafeMutablePointer<Float>
    private let layL: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    private let layR: UnsafeMutablePointer<UnsafeMutablePointer<Float>>

    // per layer buffer
    private let gain: UnsafeMutablePointer<Float>
    private let used: UnsafeMutablePointer<Int>        // samples that may be non-zero
    private let jobKind: UnsafeMutablePointer<Int>     // 0 none, 1 merge into base, 2 zero
    private let jobCursor: UnsafeMutablePointer<Int>
    private let jobEnd: UnsafeMutablePointer<Int>
    private let act: UnsafeMutablePointer<Int>         // layers that currently sound
    private var actCount = 0

    // history, oldest first; the top `undone` entries are muted (redo-able)
    private let hist: UnsafeMutablePointer<Int>
    private(set) var histCount = 0
    private(set) var undone = 0
    private(set) var current = -1

    // snapshot for aborting a just-started overdub
    private let snapHist: UnsafeMutablePointer<Int>
    private var snapCount = 0
    private var snapUndone = 0
    private var snapCurrent = -1
    private let beginJobs: UnsafeMutablePointer<Int>
    private var beginJobCount = 0

    // base zeroing (track clear) and ×2 copy
    private var baseZeroCursor = 0
    private var baseZeroEnd = 0
    private(set) var doubling = false
    private var doubleSrc = 0
    private var doubleCursor = 0

    var undoDepth: Int { histCount - undone }
    var redoDepth: Int { undone }
    var hasLayers: Bool { histCount > 0 }
    var busy: Bool { doubling || baseZeroCursor < baseZeroEnd }

    init(capacity cap: Int) {
        capacity = cap
        func buffer() -> UnsafeMutablePointer<Float> {
            calloc(cap, MemoryLayout<Float>.size)!.assumingMemoryBound(to: Float.self)
        }
        func ints(_ n: Int, _ v: Int = 0) -> UnsafeMutablePointer<Int> {
            let p = UnsafeMutablePointer<Int>.allocate(capacity: n)
            p.initialize(repeating: v, count: n)
            return p
        }
        let n = LayerStack.bufferCount
        let ll = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: n)
        let lr = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: n)
        for k in 0..<n {
            (ll + k).initialize(to: buffer())
            (lr + k).initialize(to: buffer())
        }
        baseL = buffer()
        baseR = buffer()
        preloadL = buffer()
        preloadR = buffer()
        layL = ll
        layR = lr
        let g = UnsafeMutablePointer<Float>.allocate(capacity: n)
        g.initialize(repeating: 0, count: n)
        gain = g
        used = ints(n)
        jobKind = ints(n)
        jobCursor = ints(n)
        jobEnd = ints(n)
        act = ints(n)
        hist = ints(n, -1)
        snapHist = ints(n, -1)
        beginJobs = ints(n, -1)
    }

    // MARK: Reading

    @inline(__always) func mix(_ i: Int) -> (Float, Float) {
        var j = i
        if doubling && j >= doubleSrc + doubleCursor { j -= doubleSrc }
        var l = baseL[j]
        var r = baseR[j]
        var k = 0
        while k < actCount {
            let li = act[k]
            l += layL[li][j]
            r += layR[li][j]
            k += 1
        }
        return (l, r)
    }

    /// Peaks for the timeline lanes: committed audio, and the undoable overdubs.
    func lanePeaks(at j: Int) -> (base: Float, dub: Float) {
        guard j >= 0 && j < capacity else { return (0, 0) }
        var l = baseL[j]
        var r = baseR[j]
        var dl: Float = 0
        var dr: Float = 0
        for li in 0..<LayerStack.bufferCount {
            if inHistory(li) {
                if isActive(li) {
                    dl += layL[li][j]
                    dr += layR[li][j]
                }
            } else if jobKind[li] == 1 {
                l += layL[li][j]
                r += layR[li][j]
            }
        }
        return (max(abs(l), abs(r)), max(abs(dl), abs(dr)))
    }

    func readMix(start: Int, count: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        var i = 0
        while i < count {
            let j = start + i
            if j < capacity {
                let m = mix(j)
                left[i] = m.0
                right[i] = m.1
            } else {
                left[i] = 0
                right[i] = 0
            }
            i += 1
        }
    }

    private func inHistory(_ li: Int) -> Bool {
        for h in 0..<histCount where hist[h] == li { return true }
        return false
    }

    private func isActive(_ li: Int) -> Bool {
        for h in 0..<(histCount - undone) where hist[h] == li { return true }
        return false
    }

    // MARK: Writing

    /// Adds (overdub) or replaces input at `i` in the current layer.
    @inline(__always) func write(_ i: Int, _ xl: Float, _ xr: Float, replace: Bool) {
        let c = current
        guard c >= 0, i >= 0, i < capacity else { return }
        if replace {
            var ol = baseL[i]
            var orr = baseR[i]
            var k = 0
            while k < actCount {
                let li = act[k]
                if li != c {
                    ol += layL[li][i]
                    orr += layR[li][i]
                }
                k += 1
            }
            layL[c][i] = xl - ol
            layR[c][i] = xr - orr
        } else {
            layL[c][i] += xl
            layR[c][i] += xr
        }
    }

    // MARK: History

    func updateGains() {
        for li in 0..<LayerStack.bufferCount { gain[li] = jobKind[li] == 1 ? 1 : 0 }
        for h in 0..<(histCount - undone) { gain[hist[h]] = 1 }
        actCount = 0
        for li in 0..<LayerStack.bufferCount where gain[li] != 0 {
            act[actCount] = li
            actCount += 1
        }
    }

    private func schedule(_ li: Int, kind: Int) {
        if jobKind[li] != 0 { finishJob(li) }
        guard used[li] > 0 else { return }
        jobKind[li] = kind
        jobCursor[li] = 0
        jobEnd[li] = used[li]
        if beginJobCount < LayerStack.bufferCount {
            beginJobs[beginJobCount] = li
            beginJobCount += 1
        }
    }

    /// Starts a new overdub layer for a loop of `length` samples. Returns false if no layer is free.
    @discardableResult
    func beginDub(length: Int) -> Bool {
        // snapshot for abort
        for h in 0..<LayerStack.bufferCount { snapHist[h] = hist[h] }
        snapCount = histCount
        snapUndone = undone
        snapCurrent = current
        beginJobCount = 0
        // a new overdub discards the redo-able (undone) layers
        while undone > 0 {
            histCount -= 1
            undone -= 1
            schedule(hist[histCount], kind: 2)
        }
        // history full: the oldest layer becomes part of the base
        if histCount >= LayerStack.maxUndo {
            schedule(hist[0], kind: 1)
            for h in 1..<histCount { hist[h - 1] = hist[h] }
            histCount -= 1
        }
        // a free buffer (not in the history; finish its pending job if needed)
        var free = -1
        for li in 0..<LayerStack.bufferCount where !inHistory(li) && jobKind[li] == 0 && used[li] == 0 {
            free = li
            break
        }
        if free < 0 {
            for li in 0..<LayerStack.bufferCount where !inHistory(li) && !isBeginJob(li) {
                finishJob(li)
                free = li
                break
            }
        }
        if free < 0 {
            for li in 0..<LayerStack.bufferCount where !inHistory(li) {
                finishJob(li)
                free = li
                break
            }
        }
        guard free >= 0 else { return false }
        if used[free] > 0 { zeroNow(free) }
        hist[histCount] = free
        histCount += 1
        current = free
        used[free] = max(length, 1)
        updateGains()
        return true
    }

    private func isBeginJob(_ li: Int) -> Bool {
        for k in 0..<beginJobCount where beginJobs[k] == li { return true }
        return false
    }

    /// Cancels the overdub that was just started (only while its jobs have not touched anything).
    func abortDub() -> Bool {
        for k in 0..<beginJobCount {
            let li = beginJobs[k]
            if jobKind[li] != 0 && jobCursor[li] > 0 { return false }
        }
        let newLayer = current
        for k in 0..<beginJobCount { jobKind[beginJobs[k]] = 0 }
        for h in 0..<LayerStack.bufferCount { hist[h] = snapHist[h] }
        histCount = snapCount
        undone = snapUndone
        current = snapCurrent
        beginJobCount = 0
        if newLayer >= 0 && !inHistory(newLayer) { schedule(newLayer, kind: 2) }
        beginJobCount = 0
        updateGains()
        return true
    }

    func undo() {
        guard undoDepth > 0 else { return }
        undone += 1
        updateGains()
    }

    func redo() {
        guard undone > 0 else { return }
        undone -= 1
        updateGains()
    }

    /// Pedal-style undo / redo of the newest step.
    func toggleUndo() {
        if undone > 0 { redo() } else { undo() }
    }

    /// Discards every layer (and zeroes the base up to `baseLength` if asked, for track clears).
    func clearAll(baseLength: Int = 0) {
        for li in 0..<LayerStack.bufferCount {
            if jobKind[li] != 0 {
                jobKind[li] = 2
                jobEnd[li] = max(jobEnd[li], used[li])
            } else if used[li] > 0 {
                jobKind[li] = 2
                jobCursor[li] = 0
                jobEnd[li] = used[li]
            }
        }
        histCount = 0
        undone = 0
        current = -1
        beginJobCount = 0
        doubling = false
        if baseLength > 0 {
            baseZeroCursor = 0
            baseZeroEnd = min(capacity, max(baseZeroEnd, baseLength))
        }
        updateGains()
    }

    // MARK: Jobs (audio thread, a slice per callback)

    @discardableResult
    private func runJob(_ li: Int, budget: Int) -> Int {
        let start = jobCursor[li]
        let end = min(jobEnd[li], start + budget)
        let l = layL[li]
        let r = layR[li]
        var j = start
        if jobKind[li] == 1 {
            while j < end {
                baseL[j] += l[j]
                baseR[j] += r[j]
                l[j] = 0
                r[j] = 0
                j += 1
            }
        } else if end > start {
            (l + start).update(repeating: 0, count: end - start)
            (r + start).update(repeating: 0, count: end - start)
        }
        jobCursor[li] = end
        if end >= jobEnd[li] {
            jobKind[li] = 0
            used[li] = 0
            updateGains()
        }
        return end - start
    }

    private func finishJob(_ li: Int) {
        while jobKind[li] != 0 { runJob(li, budget: Int.max / 4) }
    }

    private func zeroNow(_ li: Int) {
        let n = min(capacity, used[li])
        layL[li].update(repeating: 0, count: n)
        layR[li].update(repeating: 0, count: n)
        used[li] = 0
    }

    func finishAllJobs() {
        for li in 0..<LayerStack.bufferCount { finishJob(li) }
        if baseZeroCursor < baseZeroEnd {
            (baseL + baseZeroCursor).update(repeating: 0, count: baseZeroEnd - baseZeroCursor)
            (baseR + baseZeroCursor).update(repeating: 0, count: baseZeroEnd - baseZeroCursor)
            baseZeroCursor = baseZeroEnd
        }
        while doubling { processDouble(budget: Int.max / 4) }
    }

    var hasJobs: Bool {
        if baseZeroCursor < baseZeroEnd || doubling { return true }
        for li in 0..<LayerStack.bufferCount where jobKind[li] != 0 { return true }
        return false
    }

    func processJobs(budget: Int) {
        var b = budget
        if doubling { b -= processDouble(budget: b) }
        if baseZeroCursor < baseZeroEnd && b > 0 {
            let n = min(b, baseZeroEnd - baseZeroCursor)
            (baseL + baseZeroCursor).update(repeating: 0, count: n)
            (baseR + baseZeroCursor).update(repeating: 0, count: n)
            baseZeroCursor += n
            b -= n
        }
        for li in 0..<LayerStack.bufferCount where jobKind[li] != 0 && b > 0 {
            b -= runJob(li, budget: b)
        }
    }

    // MARK: ×2

    /// Doubles a loop of `length` samples by copying it behind itself (finish all jobs first).
    func startDouble(length: Int) -> Bool {
        guard length > 0, length * 2 <= capacity else { return false }
        finishAllJobs()
        doubleSrc = length
        doubleCursor = 0
        doubling = true
        for li in 0..<LayerStack.bufferCount where used[li] > 0 { used[li] = length * 2 }
        return true
    }

    @discardableResult
    private func processDouble(budget: Int) -> Int {
        let n = min(budget, doubleSrc - doubleCursor)
        if n > 0 {
            let s = doubleCursor
            let d = doubleSrc + doubleCursor
            (baseL + d).update(from: baseL + s, count: n)
            (baseR + d).update(from: baseR + s, count: n)
            for li in 0..<LayerStack.bufferCount where used[li] > 0 {
                (layL[li] + d).update(from: layL[li] + s, count: n)
                (layR[li] + d).update(from: layR[li] + s, count: n)
            }
            doubleCursor += n
        }
        if doubleCursor >= doubleSrc { doubling = false }
        return max(0, n) * 2
    }

    // MARK: Preloaded base (song mode)

    /// Swaps in the preloaded base; all layers are discarded.
    func swapPreloaded() {
        clearAll()
        baseZeroCursor = baseZeroEnd          // the new base is complete; never zero it
        let l = baseL
        let r = baseR
        baseL = preloadL
        baseR = preloadR
        preloadL = l
        preloadR = r
    }

    /// Wrap-adds `count` samples starting at `from` onto the start of the base (recording overflow).
    func foldBase(from: Int, count: Int) {
        guard count > 0, from + count <= capacity else { return }
        for j in 0..<count {
            baseL[j] += baseL[from + j]
            baseR[j] += baseR[from + j]
        }
    }
}
