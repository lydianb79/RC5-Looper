import SwiftUI

// MARK: - Track lanes (track 1 = main loop, tracks 2 and 3 synced to it)

struct TrackLanesView: View {
    @EnvironmentObject var looper: LooperController

    var body: some View {
        let snap = looper.snapshot
        VStack(spacing: 8) {
            MainLane(snap: snap)
            SubLane(index: 0, snap: snap.tracks[0], main: snap)
            SubLane(index: 1, snap: snap.tracks[1], main: snap)
        }
        .frame(maxWidth: .infinity)
    }
}

private let laneHeight: CGFloat = 68
private let laneHeaderWidth: CGFloat = 168

private struct MainLane: View {
    @EnvironmentObject var looper: LooperController
    let snap: Snapshot

    var body: some View {
        let c = UI.state(snap.state)
        let active = snap.state == .recording || snap.state == .overdubbing
        let pos = snap.state == .recording ? 1.0 : snap.position
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Badge(text: "1", color: UI.base)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Track 1").font(.system(size: 12.5, weight: .semibold))
                    Text(meta).font(.system(size: 10.5)).foregroundColor(UI.muted).lineLimit(1)
                }
            }
            .frame(width: laneHeaderWidth, alignment: .leading)
            Canvas { ctx, size in
                drawBars(ctx, size, looper.baseWave, UI.base, pos, dimmed: false)
                if snap.hasDubLayer && !looper.dubWave.isEmpty {
                    drawBars(ctx, size, looper.dubWave, UI.dub, pos, dimmed: !snap.dubActive, scale: 0.7)
                }
                if snap.state == .playing || snap.state == .overdubbing {
                    let x = size.width * CGFloat(pos)
                    ctx.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(.white.opacity(0.9)))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            MuteButton(muted: looper.mainMuted) { looper.toggleMainMute() }
            LevelSlider(value: Binding(get: { looper.settings.loopLevel }, set: { looper.settings.loopLevel = $0 }))
        }
        .padding(.horizontal, 10)
        .frame(height: laneHeight)
        .background(RoundedRectangle(cornerRadius: 12).fill(UI.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(active ? c : UI.line, lineWidth: active ? 1.5 : 1))
    }

    private var meta: String {
        switch snap.state {
        case .recording: return "recording…"
        case .empty, .armed, .autoRecArmed: return "empty"
        default:
            let dubs = snap.undoDepth > 0 ? " · \(snap.undoDepth) overdub\(snap.undoDepth == 1 ? "" : "s")" : ""
            return String(format: "%.1f s", snap.loopSeconds) + dubs
        }
    }
}

private struct SubLane: View {
    @EnvironmentObject var looper: LooperController
    let index: Int
    let snap: TrackSnapshot
    let main: Snapshot

    private var color: Color { index == 0 ? Color(hex: 0x34D399) : Color(hex: 0xF472B6) }

    var body: some View {
        let st = snap.state
        let stateColor: Color = st == 1 ? UI.state(.recording) : (st == 3 ? UI.state(.overdubbing) : color)
        let k = max(1, snap.cycles)
        let pos: Double = st == 2 || st == 3
            ? (Double(((main.masterCycle % k) + k) % k) + main.position) / Double(k) : 0
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Badge(text: "\(index + 2)", color: color)
                Button { looper.trackPress(index) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: symbol(st)).font(.system(size: 10, weight: .black))
                        Text(label(st)).font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundColor(st == 0 ? UI.text : .white)
                    .frame(width: 118, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(st == 0 ? UI.well : stateColor.opacity(0.8)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(st == 0 ? UI.line2 : stateColor, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(main.loopSeconds <= 0)
                .help("Track \(index + 2): record → overdub ↔ play (key \(index + 2))")
            }
            .frame(width: laneHeaderWidth, alignment: .leading)
            ZStack(alignment: .leading) {
                Canvas { ctx, size in
                    if !looper.trackWaves[index].isEmpty { drawBars(ctx, size, looper.trackWaves[index], color, pos, dimmed: false) }
                    if st == 2 || st == 3 {
                        let x = size.width * CGFloat(pos)
                        ctx.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(.white.opacity(0.9)))
                    }
                }
                Text(caption(st, k))
                    .font(.system(size: 10.5))
                    .foregroundColor(looper.trackWaves[index].isEmpty ? UI.muted : UI.text2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(UI.panel.opacity(looper.trackWaves[index].isEmpty ? 0 : 0.8)))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            IconTool(symbol: "arrow.uturn.backward", enabled: snap.undoDepth > 0, help: "Undo on track \(index + 2)") { looper.trackUndo(index) }
            IconTool(symbol: "arrow.uturn.forward", enabled: snap.redoDepth > 0, help: "Redo on track \(index + 2)") { looper.trackRedo(index) }
            IconTool(symbol: "trash", enabled: st != 0, help: "Clear track \(index + 2)") { looper.trackClear(index) }
            MuteButton(muted: looper.trackMuted[index]) { looper.toggleTrackMute(index) }
            LevelSlider(value: Binding(get: { looper.settings.trackLevels.count > index ? looper.settings.trackLevels[index] : 1 },
                                       set: { looper.setTrackLevel(index, $0) }))
        }
        .padding(.horizontal, 10)
        .frame(height: laneHeight)
        .background(RoundedRectangle(cornerRadius: 12).fill(UI.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(st == 1 || st == 3 ? stateColor : UI.line, lineWidth: st == 1 || st == 3 ? 1.5 : 1))
    }

    private func caption(_ st: Int, _ k: Int) -> String {
        switch st {
        case 0: return main.loopSeconds > 0 ? "Record a part in sync with track 1" : "Record track 1 first"
        case 1: return snap.stopRequested ? "closes at the loop end…" : "recording · \(String(format: "%.1f", snap.recordProgress)) × track 1"
        case 3: return "overdubbing · \(k) × track 1"
        default: return "\(k) × track 1 · \(String(format: "%.1f", snap.seconds)) s"
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

private struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.system(size: 13, weight: .black, design: .monospaced))
            .frame(width: 26, height: 26)
            .background(RoundedRectangle(cornerRadius: 7).fill(color.opacity(0.28)))
    }
}

/// Waveform bars across a lane.
private func drawBars(_ ctx: GraphicsContext, _ size: CGSize, _ wave: [Float], _ color: Color, _ position: Double,
                      dimmed: Bool, scale: CGFloat = 1) {
    guard !wave.isEmpty else {
        ctx.fill(Path(CGRect(x: 0, y: size.height / 2 - 1, width: size.width, height: 2)), with: .color(UI.track))
        return
    }
    let n = 120
    let w = size.width / CGFloat(n)
    for i in 0..<n {
        let a0 = i * wave.count / n
        let a1 = max(a0 + 1, (i + 1) * wave.count / n)
        let v = wave[a0..<min(a1, wave.count)].max() ?? 0
        let f = Double(i) / Double(n)
        let h = max(2, CGFloat(sqrt(Double(v))) * (size.height - 4) * scale)
        let rect = CGRect(x: CGFloat(i) * w, y: (size.height - h) / 2, width: max(1, w - 1.4), height: h)
        let col = dimmed ? UI.track : color
        ctx.fill(Path(roundedRect: rect, cornerRadius: 1.2), with: .color(col.opacity(dimmed ? 0.5 : (f <= position ? 0.95 : 0.38))))
    }
}

// MARK: - Control row buttons

struct ActionButton: View {
    let symbol: String
    let title: String
    var enabled = true
    var active: Color? = nil
    var help = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            }
            .foregroundColor(active.map { _ in Color.white } ?? UI.text)
            .frame(width: 70, height: 56)
            .background(RoundedRectangle(cornerRadius: 12).fill(active.map { $0.opacity(0.8) } ?? UI.well))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(active ?? UI.line2, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .help(help)
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
            Slider(value: $value, in: 0...2).frame(width: 78)
            Text("\(Int((value * 100).rounded()))%").font(.system(size: 11)).monospacedDigit()
                .foregroundColor(UI.muted).frame(width: 38, alignment: .trailing)
        }
        .help("Track level")
    }
}

// MARK: - Effects

/// The Effects window (menu Effects › Effects…): input and loop chains side by side.
struct EffectsWindow: View {
    @EnvironmentObject var looper: LooperController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Input FX are recorded with your playing; Loop FX change the playback only. Switch on as many effects as you like.")
                .font(.system(size: 11.5))
                .foregroundColor(UI.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 14) {
                FXChainView(title: "Input FX", chain: Binding(get: { looper.settings.inputFX }, set: { looper.settings.inputFX = $0 }))
                FXChainView(title: "Loop FX", chain: Binding(get: { looper.settings.loopFX }, set: { looper.settings.loopFX = $0 }))
            }
        }
        .padding(18)
        .frame(width: 940)
        .fixedSize()
        .background(ThemeBackground(theme: looper.appTheme, stateColor: UI.state(looper.snapshot.state), live: false))
        .foregroundColor(UI.text)
        .preferredColorScheme(UI.light ? .light : .dark)
        .tint(UI.rhythm)
        .id(looper.appTheme)
    }
}

private struct FXChainView: View {
    let title: String
    @Binding var chain: FXChainSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(title).font(.system(size: 14, weight: .bold))
                Text("\(chain.activeCount) on").font(.system(size: 11)).foregroundColor(UI.muted)
                Spacer()
                Toggle("Chain", isOn: $chain.on)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Bypass the whole \(title) chain")
            }
            ForEach(fxChainOrder) { t in
                FXRow(fx: Binding(get: { chain[t] }, set: { chain[t] = $0 }), dimmed: !chain.on)
            }
        }
        .padding(12)
        .frame(width: 445, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(UI.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(UI.line, lineWidth: 1))
    }
}

private struct FXRow: View {
    @Binding var fx: FXSettings
    let dimmed: Bool

    var body: some View {
        let t = fx.type
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button { fx.on.toggle() } label: {
                    HStack(spacing: 7) {
                        Circle().fill(fx.on ? UI.rhythm : UI.track).frame(width: 8, height: 8)
                            .shadow(color: fx.on ? UI.rhythm : .clear, radius: 4)
                        Image(systemName: t.symbol).font(.system(size: 11))
                        Text(t == .tapeStop ? (fx.on ? "Tape stopped" : "Tape stop") : t.label)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(width: 128, height: 26, alignment: .leading)
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 7).fill(fx.on ? UI.rhythm.opacity(0.2) : UI.well))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(fx.on ? UI.rhythm : UI.line2, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                knob(t.knobs.0, $fx.a)
                knob(t.knobs.1, $fx.b)
            }
            if t == .delay {
                HStack(spacing: 8) {
                    Text("Time").font(.system(size: 10.5)).foregroundColor(UI.muted).frame(width: 144, alignment: .trailing)
                    Picker("", selection: $fx.time) {
                        ForEach(DelayTime.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 250)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 9).fill(UI.well.opacity(fx.on ? 1 : 0.5)))
        .opacity(dimmed ? 0.5 : 1)
        .help(help(t))
    }

    private func knob(_ name: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name).font(.system(size: 10)).foregroundColor(UI.muted)
            Slider(value: value, in: 0...1).controlSize(.small)
        }
        .frame(width: 120)
    }

    private func help(_ t: FXType) -> String {
        switch t {
        case .filter: return "Cutoff: centre = open, left = low-pass, right = high-pass"
        case .delay: return "Tempo-synced ping-pong delay"
        case .reverb: return "Room to hall reverb"
        case .crusher: return "Lower bit depth and sample rate"
        case .tapeStop: return "Switch on to slow the sound down to a halt, off to bring it back"
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
