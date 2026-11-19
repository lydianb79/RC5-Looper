import AVFoundation

/// 99 phrase memories stored in ~/Library/Application Support/Looper/Memories/NN/
/// Each memory = loop.wav (32-bit float stereo) + settings.json (rhythm, kit, tempo, modes…)
final class MemoryStore {
    static let slotCount = 99
    let root: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = support.appendingPathComponent("Looper/Memories", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func dir(_ i: Int) -> URL { root.appendingPathComponent(String(format: "%02d", i + 1), isDirectory: true) }
    func audioURL(_ i: Int) -> URL { dir(i).appendingPathComponent("loop.wav") }
    /// Tracks 2 and 3 (t = 0, 1).
    func trackURL(_ i: Int, _ t: Int) -> URL { dir(i).appendingPathComponent("track\(t + 2).wav") }
    func hasTrack(_ i: Int, _ t: Int) -> Bool { FileManager.default.fileExists(atPath: trackURL(i, t).path) }
    func settingsURL(_ i: Int) -> URL { dir(i).appendingPathComponent("settings.json") }

    func hasAudio(_ i: Int) -> Bool { FileManager.default.fileExists(atPath: audioURL(i).path) }

    func loadSettings(_ i: Int) -> MemorySettings? {
        guard let data = try? Data(contentsOf: settingsURL(i)) else { return nil }
        return try? JSONDecoder().decode(MemorySettings.self, from: data)
    }

    func saveSettings(_ s: MemorySettings, slot i: Int) throws {
        try FileManager.default.createDirectory(at: dir(i), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(s).write(to: settingsURL(i), options: .atomic)
    }

    func deleteAudio(_ i: Int) { try? FileManager.default.removeItem(at: audioURL(i)) }
    func delete(_ i: Int) { try? FileManager.default.removeItem(at: dir(i)) }

    func info(_ i: Int) -> MemoryInfo {
        let s = loadSettings(i)
        let name = s?.name ?? MemorySettings.defaults(for: i).name
        let secs: Double? = hasAudio(i) ? (s?.savedSeconds ?? 0) : nil
        return MemoryInfo(id: i, name: name, seconds: secs, thumb: s?.thumb ?? [],
                          tempo: s?.tempo ?? 0, bars: s?.loopMeasures ?? 0, rhythm: s?.rhythmOn ?? false)
    }

    func allInfo() -> [MemoryInfo] { (0..<Self.slotCount).map { info($0) } }

    // MARK: WAV I/O

    static func writeWAV(to url: URL, core: LoopCore, length: Int) throws {
        try writeWAV(to: url, sampleRate: core.sampleRate, length: length) { start, n, l, r in
            core.readMix(start: start, count: n, left: l, right: r)
        }
    }

    static func writeWAV(to url: URL, stack: LayerStack, sampleRate: Double, length: Int) throws {
        try writeWAV(to: url, sampleRate: sampleRate, length: length) { start, n, l, r in
            stack.readMix(start: start, count: n, left: l, right: r)
        }
    }

    /// Writes `length` frames supplied by `read` as a 32-bit float stereo WAV (atomically).
    static func writeWAV(to url: URL, sampleRate: Double, length: Int,
                         read: (Int, Int, UnsafeMutablePointer<Float>, UnsafeMutablePointer<Float>) -> Void) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).wav")
        do {
            let file = try AVAudioFile(forWriting: tmp, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let chunk = 32768
            guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(chunk)),
                  let ch = buf.floatChannelData else {
                throw NSError(domain: "Looper", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not allocate audio buffer"])
            }
            var pos = 0
            while pos < length {
                let n = min(chunk, length - pos)
                read(pos, n, ch[0], ch[1])
                buf.frameLength = AVAudioFrameCount(n)
                try file.write(from: buf)
                pos += n
            }
        }
        // The AVAudioFile has been released (file closed) at this point.
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: url)
        }
    }

    /// Reads any audio file Core Audio understands (WAV, AIFF, CAF, MP3, M4A…) into the loop base buffer.
    /// Must only be called while the core is in the empty state. Returns the loop length in frames.
    static func readAudio(from url: URL, into core: LoopCore) throws -> Int {
        try readAudio(from: url, left: core.baseL, right: core.baseR, capacity: core.capacity, sampleRate: core.sampleRate)
    }

    /// Reads an audio file into the given buffers, converted to `sampleRate`. Returns the length in frames.
    static func readAudio(from url: URL, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>,
                          capacity: Int, sampleRate: Double) throws -> Int {
        let file = try AVAudioFile(forReading: url)
        let fmt = file.processingFormat
        let total = Int(file.length)
        guard total > 0 else { return 0 }
        let ratio = fmt.sampleRate / sampleRate          // file frames per loop frame
        let outLen = min(capacity, Int(Double(total) / ratio))
        let need = min(total, Int(Double(outLen) * ratio) + 2)
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(need)) else {
            throw NSError(domain: "Looper", code: 3, userInfo: [NSLocalizedDescriptionKey: "File too large"])
        }
        try file.read(into: buf, frameCount: AVAudioFrameCount(need))
        guard let ch = buf.floatChannelData else {
            throw NSError(domain: "Looper", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unsupported audio format"])
        }
        let c0 = ch[0]
        let c1 = fmt.channelCount > 1 ? ch[1] : ch[0]
        let n = Int(buf.frameLength)
        guard n > 0 else { return 0 }
        if abs(ratio - 1) < 1e-9 {
            let len = min(outLen, n)
            left.update(from: c0, count: len)
            right.update(from: c1, count: len)
            return len
        }
        var produced = 0
        for i in 0..<outLen {
            let x = Double(i) * ratio
            let j = Int(x)
            if j >= n { break }
            let j1 = min(j + 1, n - 1)
            let f = Float(x - Double(j))
            left[i] = c0[j] + (c0[j1] - c0[j]) * f
            right[i] = c1[j] + (c1[j1] - c1[j]) * f
            produced = i + 1
        }
        return produced
    }
}
