import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// Export of the whole mix (all tracks + rhythm) as audio, and of the rhythm as a MIDI file.
extension LooperController {
    enum ExportFormat: String, CaseIterable, Identifiable {
        case wav = "WAV (32-bit float)"
        case m4a = "AAC (.m4a)"
        var id: String { rawValue }
    }

    /// Renders `repeats` passes of the loop (tracks 1–3 with their levels, loop FX) plus the
    /// rhythm, offline on a background thread, and writes the file.
    func exportMix(repeats: Int, includeRhythm: Bool, format: ExportFormat) {
        let L = core.loopLength
        guard L > 0 else { flash("No loop to export"); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format == .wav ? .wav : UTType.mpeg4Audio]
        panel.nameFieldStringValue = "\(settings.name) mix.\(format == .wav ? "wav" : "m4a")"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let c = core
        let sr = c.sampleRate
        let s = settings
        let tempo = c.loopTempo > 0 ? c.loopTempo : s.tempo
        let mainLevel = Float(s.loopLevel)
        let levels = [Float(s.trackLevels.first ?? 1), Float(s.trackLevels.count > 1 ? s.trackLevels[1] : 1)]
        let mutes = [trackMuted[0], trackMuted[1]]
        let mainMute = mainMuted
        let subLens = [c.sub1.hasContent ? c.sub1.length : 0, c.sub2.hasContent ? c.sub2.length : 0]
        let total = L * max(1, repeats)
        let rl = Float(s.rhythmLevel)
        exportProgress = 0

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var drums: RhythmEngine?
            if includeRhythm && s.rhythmOn {
                let r = RhythmEngine(sampleRate: sr)
                var waited = 0
                while !r.synth.ready && waited < 400 {
                    r.synth.prepare()
                    usleep(25_000)
                    waited += 1
                }
                r.configure(tempo: tempo, pattern: s.rhythmPattern, variation: s.rhythmVariation, kit: s.rhythmKit,
                            reverb: Float(s.rhythmReverb), humanize: Float(s.rhythmHumanize))
                r.reset()
                drums = r
            }
            let fx = FXUnit(sampleRate: sr)
            LooperController.apply(s.loopFX, to: fx)
            fx.tempo = tempo
            do {
                var fileSettings: [String: Any] = [AVSampleRateKey: sr, AVNumberOfChannelsKey: 2]
                if format == .wav {
                    fileSettings[AVFormatIDKey] = kAudioFormatLinearPCM
                    fileSettings[AVLinearPCMBitDepthKey] = 32
                    fileSettings[AVLinearPCMIsFloatKey] = true
                    fileSettings[AVLinearPCMIsBigEndianKey] = false
                    fileSettings[AVLinearPCMIsNonInterleaved] = false
                } else {
                    fileSettings[AVFormatIDKey] = kAudioFormatMPEG4AAC
                    fileSettings[AVEncoderBitRateKey] = 256_000
                }
                try? FileManager.default.removeItem(at: url)
                let file = try AVAudioFile(forWriting: url, settings: fileSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
                let chunk = 8192
                guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(chunk)),
                      let ch = buf.floatChannelData else { throw NSError(domain: "Looper", code: 5) }
                var pos = 0
                while pos < total {
                    let n = min(chunk, total - pos)
                    if let d = drums {
                        d.configure(tempo: tempo, pattern: s.rhythmPattern, variation: s.rhythmVariation, kit: s.rhythmKit,
                                    reverb: Float(s.rhythmReverb), humanize: Float(s.rhythmHumanize))
                    }
                    for k in 0..<n {
                        let a = pos + k
                        let i = a % L
                        var l: Float = 0
                        var r: Float = 0
                        if !mainMute {
                            let m = c.stack.mix(i)
                            l = m.0 * mainLevel
                            r = m.1 * mainLevel
                        }
                        for t in 0..<2 where subLens[t] > 0 && !mutes[t] {
                            let m = c.sub(t).stack.mix(a % subLens[t])
                            l += m.0 * levels[t]
                            r += m.1 * levels[t]
                        }
                        let f = fx.process(l, r)
                        l = f.0
                        r = f.1
                        if let d = drums {
                            let x = d.tick()
                            l += x.0 * rl
                            r += x.1 * rl
                        }
                        ch[0][k] = max(-1, min(1, l))
                        ch[1][k] = max(-1, min(1, r))
                    }
                    buf.frameLength = AVAudioFrameCount(n)
                    try file.write(from: buf)
                    pos += n
                    if pos % (chunk * 16) == 0 {
                        let p = Double(pos) / Double(total)
                        DispatchQueue.main.async { self?.exportProgress = p }
                    }
                }
                DispatchQueue.main.async {
                    self?.exportProgress = nil
                    self?.flash("Exported \(url.lastPathComponent)")
                }
            } catch {
                DispatchQueue.main.async {
                    self?.exportProgress = nil
                    self?.flash("Export failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Writes the current rhythm pattern as a Standard MIDI File (General MIDI drums, channel 10).
    func exportRhythmMIDI(bars requested: Int) {
        let pi = settings.rhythmPattern
        let p = RhythmLibrary.pattern(pi)
        let bars = max(1, requested)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "mid") ?? .data]
        panel.nameFieldStringValue = "\(p.name).mid"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let ppq = 480
        let steps = max(1, min(kMaxSteps, p.steps))
        let stepTicks = Double(ppq) * p.beats / Double(steps)
        let gm: [UInt8] = [36, 38, 42, 46, 51, 49, 48, 43, 37, 39, 70]
        var events: [(tick: Int, data: [UInt8])] = []
        for bar in 0..<bars {
            for st in 0..<steps {
                let sw = st % 2 == 1 ? p.swing : 0
                let tick = Int(((Double(bar * steps + st) + sw) * stepTicks).rounded())
                for d in 0..<kInstrumentCount {
                    let v = core.rhythm.cell(pattern: pi, variation: settings.rhythmVariation, drum: d, step: st)
                    guard v > 0 else { continue }
                    let vel = UInt8(max(1, min(127, Int((v * 120).rounded()))))
                    events.append((tick, [0x99, gm[d], vel]))
                    events.append((tick + max(1, Int(stepTicks * 0.5)), [0x89, gm[d], 0]))
                }
            }
        }
        events.sort { $0.tick == $1.tick ? ($0.data[0] & 0xF0) < ($1.data[0] & 0xF0) : $0.tick < $1.tick }

        func vlq(_ x: Int) -> [UInt8] {
            var v = max(0, x)
            var out: [UInt8] = [UInt8(v & 0x7F)]
            v >>= 7
            while v > 0 {
                out.insert(UInt8(v & 0x7F) | 0x80, at: 0)
                v >>= 7
            }
            return out
        }
        var track: [UInt8] = []
        let usPerQuarter = Int(60_000_000 / max(20, settings.tempo))
        track += [0x00, 0xFF, 0x51, 0x03, UInt8((usPerQuarter >> 16) & 0xFF), UInt8((usPerQuarter >> 8) & 0xFF), UInt8(usPerQuarter & 0xFF)]
        let sig = p.signature.split(separator: "/").compactMap { Int($0) }
        let num = UInt8(sig.first ?? 4)
        let den = sig.count > 1 ? sig[1] : 4
        let denPow = UInt8(max(0, Int(log2(Double(den)))))
        track += [0x00, 0xFF, 0x58, 0x04, num, denPow, 24, 8]
        let name = Array(p.name.utf8.prefix(60))
        track += [0x00, 0xFF, 0x03] + vlq(name.count) + name
        var last = 0
        for e in events {
            track += vlq(e.tick - last) + e.data
            last = e.tick
        }
        track += [0x00, 0xFF, 0x2F, 0x00]
        var file: [UInt8] = Array("MThd".utf8) + [0, 0, 0, 6, 0, 0, 0, 1, UInt8(ppq >> 8), UInt8(ppq & 0xFF)]
        file += Array("MTrk".utf8)
        let n = track.count
        file += [UInt8((n >> 24) & 0xFF), UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)]
        file += track
        do {
            try Data(file).write(to: url, options: .atomic)
            flash("Exported \(url.lastPathComponent)")
        } catch {
            flash("Export failed: \(error.localizedDescription)")
        }
    }
}
