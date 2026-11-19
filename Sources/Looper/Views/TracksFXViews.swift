import SwiftUI

// MARK: - Loop tools (undo history, ×2, mute, fade)

struct LoopToolsRow: View {
    @EnvironmentObject var looper: LooperController

    var body: some View {
        let snap = looper.snapshot
        let hasLoop = snap.loopSeconds > 0
        HStack(spacing: 8) {
            ToolButton(symbol: "arrow.uturn.backward", title: snap.undoDepth > 0 ? "Undo \(snap.undoDepth)" : "Undo",
                       hint: "⌘Z", enabled: snap.undoDepth > 0) { looper.undo() }
                .help("Undo the last overdub (up to \(LayerStack.maxUndo) steps back)")
            ToolButton(symbol: "arrow.uturn.forward", title: snap.redoDepth > 0 ? "Redo \(snap.redoDepth)" : "Redo",
                       hint: "⇧⌘Z", enabled: snap.redoDepth > 0) { looper.redo() }
            HistoryDots(undo: snap.undoDepth, redo: snap.redoDepth)
            Divider().frame(height: 26)
            ToolButton(symbol: "multiply", title: "×2", hint: "D", enabled: hasLoop && snap.state != .recording && !snap.doubling) {
                looper.doubleLoop()
            }
            .help("Double the loop length: the loop is copied behind itself so you can overdub a longer phrase")
            ToolButton(symbol: looper.allMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                       title: looper.allMuted ? "Muted" : "Mute", hint: "X", enabled: hasLoop,
                       highlight: looper.allMuted ? UI.dub : nil) { looper.toggleDrop() }
                .help("Mute all loop tracks while the rhythm keeps playing (drop)")
            ToolButton(symbol: "speaker.wave.1", title: "Fade out", hint: "F",
                       enabled: snap.state == .playing || snap.state == .overdubbing) { looper.fadeOut() }
                .help("Fade the loop out over \(String(format: "%.1f", looper.settings.fadeSeconds)) s and stop")
            Spacer(minLength: 0)
        }
    }
}

private struct HistoryDots: View {
    let undo: Int
    let redo: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<LayerStack.maxUndo, id: \.self) { i in
                Circle()
                    .fill(i < undo ? UI.dub : (i < undo + redo ? UI.dub.opacity(0.25) : UI.track))
                    .frame(width: 7, height: 7)
            }
        }
        .help("Undo history: \(undo) overdub\(undo == 1 ? "" : "s") can be undone, \(redo) redone")
    }
}

struct ToolButton: View {
    let symbol: String
    let title: String
    let hint: String
    var enabled = true
    var highlight: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Text(hint).font(.system(size: 10.5)).foregroundColor(UI.muted)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 9).fill(highlight.map { $0.opacity(0.18) } ?? UI.well))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(highlight ?? UI.line2, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .fixedSize()
    }
}

// MARK: - Tracks

struct TracksPanel: View {
    @EnvironmentObject var looper: LooperController

    var body: some View {
        let snap = looper.snapshot
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tracks").font(.system(size: 14, weight: .bold))
                Text("Tracks 2 and 3 play in sync with track 1 and can be any number of its cycles long.")
                    .font(.system(size: 11)).foregroundColor(UI.muted)
                Spacer()
            }
            MainTrackRow()
            ForEach(0..<2, id: \.self) { t in
                SubTrackRow(index: t, snap: snap.tracks[t], main: snap)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(UI.panel))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(UI.line, lineWidth: 1))
    }
}

private struct MainTrackRow: View {
    @EnvironmentObject var looper: LooperController

    var body: some View {
        let snap = looper.snapshot
        HStack(spacing: 10) {
            Text("1").font(.system(size: 13, weight: .black, design: .monospaced))
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(UI.base.opacity(0.25)))
            Text("Main loop").font(.system(size: 12.5, weight: .semibold)).frame(width: 96, alignment: .leading)
            Text(snap.loopSeconds > 0 ? "\(snap.totalMeasures) bar\(snap.totalMeasures == 1 ? "" : "s") · \(String(format: "%.1f", snap.loopSeconds)) s" : "empty")
                .font(.system(size: 11)).foregroundColor(UI.muted)
            Spacer()
            MuteButton(muted: looper.mainMuted) { looper.toggleMainMute() }
            LevelSlider(value: Binding(get: { looper.settings.loopLevel }, set: { looper.settings.loopLevel = $0 }))
        }
        .padding(.vertical, 2)
    }
}

private struct SubTrackRow: View {
    @EnvironmentObject var looper: LooperController
    let index: Int
    let snap: TrackSnapshot
    let main: Snapshot

    private var color: Color { index == 0 ? Color(hex: 0x34D399) : Color(hex: 0xF472B6) }

    var body: some View {
        let st = snap.state
        let stateColor: Color = st == 1 ? Color(hex: 0xFF453A) : (st == 3 ? Color(hex: 0xFF9F0A) : color)
        let k = max(1, snap.cycles)
        let pos: Double = st == 2 || st == 3
            ? (Double(((main.masterCycle % k) + k) % k) + main.position) / Double(k) : (st == 1 ? min(1, snap.recordProgress / max(1, ceil(snap.recordProgress))) : 0)
        HStack(spacing: 10) {
            Text("\(index + 2)").font(.system(size: 13, weight: .black, design: .monospaced))
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(color.opacity(0.25)))
            Button { looper.trackPress(index) } label: {
                HStack(spacing: 6) {
                    Image(systemName: symbol(st)).font(.system(size: 11, weight: .black))
                    Text(label(st)).font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(st == 0 ? UI.text : .white)
                .frame(width: 112, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(st == 0 ? UI.well : stateColor.opacity(0.75)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(st == 0 ? UI.line2 : stateColor, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Track \(index + 2): record → overdub ↔ play (key \(index + 2))")
            TrackWave(wave: looper.trackWaves[index], color: color, position: pos,
                      active: st == 1 || st == 3, accent: stateColor, empty: st == 0,
                      caption: caption(st, k))
            IconTool(symbol: "arrow.uturn.backward", enabled: snap.undoDepth > 0, help: "Undo on track \(index + 2)") { looper.trackUndo(index) }
            IconTool(symbol: "arrow.uturn.forward", enabled: snap.redoDepth > 0, help: "Redo on track \(index + 2)") { looper.trackRedo(index) }
            IconTool(symbol: "trash", enabled: st != 0, help: "Clear track \(index + 2)") { looper.trackClear(index) }
            MuteButton(muted: looper.trackMuted[index]) { looper.toggleTrackMute(index) }
            LevelSlider(value: Binding(get: { looper.settings.trackLevels.count > index ? looper.settings.trackLevels[index] : 1 },
                                       set: { looper.setTrackLevel(index, $0) }))
        }
    }

    private func caption(_ st: Int, _ k: Int) -> String {
        switch st {
        case 0: return looper.snapshot.loopSeconds > 0 ? "Press Record to add a part in sync with track 1" : "Record track 1 first"
        case 1: return snap.stopRequested ? "closes at the end of this cycle…" : "recording · \(String(format: "%.1f", snap.recordProgress)) cycles"
        case 3: return "overdubbing · \(k) cycle\(k == 1 ? "" : "s")"
        default: return "\(k) cycle\(k == 1 ? "" : "s") of track 1 · \(String(format: "%.1f", snap.seconds)) s"
        }
    }

    private func symbol(_ st: Int) -> String {
        switch st {
        case 0: return "circle.fill"
        case 1: return "stop.fill"
        case 2: return "plus"
        default: return "play.fill"
        }
    }

    private func label(_ st: Int) -> String {
        switch st {
        case 0: return "Record"
        case 1: return snap.stopRequested ? "Closing…" : "Close loop"
        case 2: return "Overdub"
        default: return "Play"
        }
    }
}

private struct TrackWave: View {
    let wave: [Float]
    let color: Color
    let position: Double
    let active: Bool
    let accent: Color
    let empty: Bool
    let caption: String

    var body: some View {
        ZStack(alignment: .leading) {
            Canvas { ctx, size in
                guard !wave.isEmpty else { return }
                let n = 100
                let w = size.width / CGFloat(n)
                for i in 0..<n {
                    let a0 = i * wave.count / n
                    let a1 = max(a0 + 1, (i + 1) * wave.count / n)
                    let v = wave[a0..<min(a1, wave.count)].max() ?? 0
                    let h = max(2, CGFloat(sqrt(Double(v))) * (size.height - 8))
                    let f = Double(i) / Double(n)
                    ctx.fill(Path(roundedRect: CGRect(x: CGFloat(i) * w, y: (size.height - h) / 2, width: max(1, w - 1.2), height: h),
                                  cornerRadius: 1),
                             with: .color(color.opacity(f <= position ? 0.95 : 0.4)))
                }
                if !empty {
                    let x = size.width * CGFloat(position)
                    ctx.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(.white.opacity(0.85)))
                }
            }
            if wave.isEmpty {
                Text(caption).font(.system(size: 11)).foregroundColor(UI.muted).padding(.leading, 10)
            } else {
                Text(caption).font(.system(size: 10, weight: .medium)).foregroundColor(UI.text2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(UI.panel.opacity(0.8)))
                    .padding(.leading, 6)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 4)
            }
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 9).fill(UI.well))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(active ? accent : UI.line, lineWidth: active ? 1.5 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

private struct IconTool: View {
    let symbol: String
    let enabled: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(UI.well))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.line2, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .help(help)
    }
}

private struct MuteButton: View {
    let muted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("M")
                .font(.system(size: 12, weight: .heavy))
                .foregroundColor(muted ? .white : UI.text2)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(muted ? UI.dub.opacity(0.85) : UI.well))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(muted ? UI.dub : UI.line2, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(muted ? "Unmute" : "Mute")
    }
}

private struct LevelSlider: View {
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 6) {
            Slider(value: $value, in: 0...2).frame(width: 110)
            Text("\(Int((value * 100).rounded()))%").font(.system(size: 11)).monospacedDigit()
                .foregroundColor(UI.muted).frame(width: 38, alignment: .trailing)
        }
        .help("Track level")
    }
}

// MARK: - Effects

struct EffectsPanel: View {
    @EnvironmentObject var looper: LooperController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Effects").font(.system(size: 14, weight: .bold))
                Text("Input FX are recorded with your playing; loop FX change the playback only.")
                    .font(.system(size: 11)).foregroundColor(UI.muted)
                Spacer()
            }
            HStack(alignment: .top, spacing: 12) {
                FXSlotView(title: "Input FX", fx: Binding(get: { looper.settings.inputFX }, set: { looper.settings.inputFX = $0 }))
                FXSlotView(title: "Loop FX", fx: Binding(get: { looper.settings.loopFX }, set: { looper.settings.loopFX = $0 }))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(UI.panel))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(UI.line, lineWidth: 1))
    }
}

private struct FXSlotView: View {
    let title: String
    @Binding var fx: FXSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button { fx.on.toggle() } label: {
                    HStack(spacing: 6) {
                        Circle().fill(fx.on ? UI.rhythm : UI.track).frame(width: 9, height: 9)
                            .shadow(color: fx.on ? UI.rhythm : .clear, radius: 4)
                        Text(fx.type == .tapeStop ? (fx.on ? "Stopped" : "Stop tape") : (fx.on ? "On" : "Off"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 8).fill(fx.on ? UI.rhythm.opacity(0.2) : UI.well))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(fx.on ? UI.rhythm : UI.line2, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Text(title).font(.system(size: 12.5, weight: .bold))
                Spacer()
                Picker("", selection: $fx.type) {
                    ForEach(FXType.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
                .labelsHidden()
                .frame(width: 150)
            }
            HStack(spacing: 14) {
                knob(fx.type.knobs.0, value: $fx.a)
                knob(fx.type.knobs.1, value: $fx.b)
                if fx.type == .delay {
                    Picker("", selection: $fx.time) {
                        ForEach(DelayTime.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 80)
                }
            }
            if fx.type == .filter {
                Text("Cutoff: centre = open, left = low-pass, right = high-pass")
                    .font(.system(size: 10.5)).foregroundColor(UI.muted)
            } else if fx.type == .tapeStop {
                Text("Switch on to slow the sound down to a halt, off to bring it back")
                    .font(.system(size: 10.5)).foregroundColor(UI.muted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11).fill(UI.well))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(fx.on ? UI.rhythm.opacity(0.6) : UI.line, lineWidth: 1))
    }

    private func knob(_ name: String, value: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            Text(name).font(.system(size: 11)).foregroundColor(UI.muted).frame(width: 64, alignment: .leading)
            Slider(value: value, in: 0...1).frame(minWidth: 90)
        }
    }
}

// MARK: - Song

struct SongPanel: View {
    @EnvironmentObject var looper: LooperController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    if looper.songActive { looper.stopSong() } else { looper.startSong() }
                } label: {
                    Label(looper.songActive ? "Stop song" : "Play song", systemImage: looper.songActive ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle())
            }
            Toggle("Repeat the song", isOn: $looper.song.repeatSong).font(.system(size: 12))
            Text("Each memory plays its repeats, then the next one starts exactly at the loop end.")
                .font(.system(size: 10.5)).foregroundColor(UI.muted)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(looper.song.steps.enumerated()), id: \.element.id) { i, step in
                        SongStepRow(index: i, step: step)
                    }
                }
            }
            Button {
                looper.addSongStep()
            } label: {
                Label("Add memory \(String(format: "%02d", looper.memoryIndex + 1))", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButtonStyle())
        }
        .padding(12)
    }
}

private struct SongStepRow: View {
    @EnvironmentObject var looper: LooperController
    let index: Int
    let step: SongStep

    var body: some View {
        let current = looper.songActive && looper.songStep == index
        let info = step.memory < looper.memoryInfo.count ? looper.memoryInfo[step.memory] : nil
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("\(index + 1)").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(UI.muted)
                Menu {
                    ForEach(looper.memoryInfo.filter { $0.seconds != nil }) { m in
                        Button(String(format: "%02d  ", m.id + 1) + m.name) { setMemory(m.id) }
                    }
                } label: {
                    Text(String(format: "%02d ", step.memory + 1) + (info?.name ?? ""))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                Spacer(minLength: 0)
                Button { looper.removeSongStep(step.id) } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                    .buttonStyle(.plain)
                    .foregroundColor(UI.muted)
            }
            HStack(spacing: 6) {
                Stepper(value: Binding(get: { step.repeats }, set: { setRepeats($0) }), in: 1...64) {
                    Text("× \(step.repeats)").font(.system(size: 11)).monospacedDigit()
                }
                .controlSize(.small)
                Spacer()
                if current {
                    Text("\(looper.songRepeat + 1)/\(step.repeats)").font(.system(size: 11, weight: .bold)).foregroundColor(UI.rhythm)
                }
                Button { looper.moveSongStep(step.id, by: -1) } label: { Image(systemName: "chevron.up").font(.system(size: 10)) }
                    .buttonStyle(.plain).foregroundColor(UI.muted)
                Button { looper.moveSongStep(step.id, by: 1) } label: { Image(systemName: "chevron.down").font(.system(size: 10)) }
                    .buttonStyle(.plain).foregroundColor(UI.muted)
            }
            if info?.seconds == nil {
                Text("This memory has no loop and is skipped").font(.system(size: 10)).foregroundColor(UI.dub)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 9).fill(current ? UI.selection.opacity(0.6) : UI.well))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(current ? UI.rhythm : UI.line, lineWidth: current ? 1.5 : 1))
        .onTapGesture(count: 2) { looper.startSong(from: index) }
        .help("Double-click to start the song here")
    }

    private func setMemory(_ m: Int) {
        guard let i = looper.song.steps.firstIndex(where: { $0.id == step.id }) else { return }
        looper.song.steps[i].memory = m
    }

    private func setRepeats(_ r: Int) {
        guard let i = looper.song.steps.firstIndex(where: { $0.id == step.id }) else { return }
        looper.song.steps[i].repeats = r
    }
}

// MARK: - Export sheet

struct ExportSheet: View {
    @EnvironmentObject var looper: LooperController
    @Environment(\.dismiss) private var dismiss
    @State private var repeats = 4
    @State private var rhythm = true
    @State private var format: LooperController.ExportFormat = .wav
    @State private var midiBars = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export").font(.title3.bold())
            GroupBox("Mix (all tracks + rhythm)") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Length", selection: $repeats) {
                        ForEach([1, 2, 4, 8, 16], id: \.self) { Text("\($0) × loop").tag($0) }
                    }
                    Toggle("Include the rhythm", isOn: $rhythm).disabled(!looper.settings.rhythmOn)
                    Picker("Format", selection: $format) {
                        ForEach(LooperController.ExportFormat.allCases) { Text($0.rawValue).tag($0) }
                    }
                    HStack {
                        if let p = looper.exportProgress {
                            ProgressView(value: p).frame(width: 160)
                        }
                        Spacer()
                        Button("Export Mix…") { looper.exportMix(repeats: repeats, includeRhythm: rhythm, format: format) }
                            .disabled(looper.snapshot.loopSeconds <= 0 || looper.exportProgress != nil)
                    }
                }
                .padding(6)
            }
            GroupBox("Rhythm as MIDI file") {
                VStack(alignment: .leading, spacing: 10) {
                    Stepper("Bars: \(midiBars)", value: $midiBars, in: 1...64)
                    Text("General MIDI drums on channel 10, current pattern and variation, current tempo.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        Button("Export MIDI…") { looper.exportRhythmMIDI(bars: midiBars) }
                    }
                }
                .padding(6)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            midiBars = max(1, looper.settings.loopMeasures > 0 ? looper.settings.loopMeasures : 4)
            rhythm = looper.settings.rhythmOn
        }
    }
}

// MARK: - MIDI learn (Settings)

struct MIDILearnView: View {
    @EnvironmentObject var looper: LooperController

    var body: some View {
        ForEach(MIDIAction.allCases) { a in
            HStack {
                Text(a.label)
                Spacer()
                if looper.midiLearnAction == a {
                    Text("Press a pedal, key or knob…").foregroundStyle(.orange)
                    Button("Cancel") { looper.midiLearnAction = nil }
                } else {
                    Text(looper.midiBindings[a.rawValue]?.label ?? "–").foregroundStyle(.secondary).monospacedDigit()
                    Button("Learn") { looper.midiLearnAction = a }
                    if looper.midiBindings[a.rawValue] != nil {
                        Button { looper.midiBindings[a.rawValue] = nil } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
