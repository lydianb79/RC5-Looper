import SwiftUI

struct ContentView: View {
    var body: some View {
        StudioView()
    }
}

struct SetupView: View {
    @EnvironmentObject var looper: LooperController

    var body: some View {
        Form {
            Section("Recording") {
                Picker("Rec action", selection: $looper.settings.recAction) {
                    ForEach(RecAction.allCases) { Text($0.label).tag($0) }
                }
                Picker("Dub mode", selection: $looper.settings.dubMode) {
                    ForEach(DubMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Loop quantize (snap loop to whole bars when rhythm is on)", isOn: $looper.settings.quantize)
                Toggle("Count-in (one bar before recording; metronome clicks when the rhythm is off)", isOn: $looper.settings.countIn)
                Toggle("Auto rec (recording starts when you play)", isOn: $looper.settings.autoRec)
                if looper.settings.autoRec {
                    LabeledContent("Auto rec threshold") {
                        Slider(value: $looper.autoRecThreshold, in: 0.005...0.3)
                        Text(String(format: "%.0f dB", 20 * log10(looper.autoRecThreshold))).monospacedDigit().frame(width: 52)
                    }
                }
            }
            Section("Playback") {
                Picker("Start", selection: $looper.settings.startMode) {
                    ForEach(StartMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Stop", selection: $looper.settings.stopMode) {
                    ForEach(StopMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Fade time") {
                    Slider(value: $looper.settings.fadeSeconds, in: 0.2...10)
                    Text(String(format: "%.1f s", looper.settings.fadeSeconds)).monospacedDigit().frame(width: 52)
                }
                Toggle("One shot (play once, pedal restarts)", isOn: $looper.settings.oneShot)
                Toggle("Reverse playback", isOn: $looper.settings.reverse)
            }
            Section("Levels & input") {
                LabeledContent("Loop level") {
                    Slider(value: $looper.settings.loopLevel, in: 0...2)
                    Text("\(Int(looper.settings.loopLevel * 100))").monospacedDigit().frame(width: 52)
                }
                LabeledContent("Rhythm level") {
                    Slider(value: $looper.settings.rhythmLevel, in: 0...2)
                    Text("\(Int(looper.settings.rhythmLevel * 100))").monospacedDigit().frame(width: 52)
                }
                Toggle("Input monitor (hear the input through the app)", isOn: $looper.inputMonitor)
                LabeledContent("Input") { LevelMeter(level: looper.snapshot.inLevel).frame(width: 180) }
            }
            Section("Appearance") {
                Picker("Theme", selection: $looper.appTheme) {
                    ForEach(AppTheme.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Show memories sidebar", isOn: $looper.showSidebar)
                Toggle("Show rhythm panel", isOn: $looper.showRhythm)
            }
            Section("MIDI") {
                Picker("Tempo sync", selection: $looper.syncExternal) {
                    Text("Internal").tag(false)
                    Text("External MIDI clock").tag(true)
                }
                .pickerStyle(.segmented)
                if looper.syncExternal {
                    LabeledContent("Incoming clock") {
                        if let t = looper.externalClockTempo {
                            Text(String(format: "♩ %.1f", t)).monospacedDigit().foregroundStyle(.green)
                        } else {
                            Text("No clock received").foregroundStyle(.secondary)
                        }
                    }
                    Text("The tempo follows the clock (a recorded loop changes speed, 50–200 %). MIDI Start plays from the top, Stop stops, Continue resumes. Clock out is disabled while syncing to an external clock.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Send MIDI clock + start/stop on virtual port \"Looper\"", isOn: $looper.midiClockOut)
                Text("Remote control: CC80 pedal · CC81 stop · CC82 undo · CC83 clear · CC84 rhythm · CC85 variation · CC86 loop level · Notes 60–66 · Program change 0–98 selects memory")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct AudioSetupView: View {
    @EnvironmentObject var looper: LooperController

    var body: some View {
        Form {
            Section("Audio devices") {
                Picker("Input device", selection: $looper.inputDeviceUID) {
                    Text("System default").tag("")
                    ForEach(looper.inputDevices) { d in
                        Text("\(d.name) — \(d.inputChannels) in").tag(d.uid)
                    }
                }
                Picker("Output device", selection: $looper.outputDeviceUID) {
                    Text("System default").tag("")
                    ForEach(looper.outputDevices) { d in
                        Text("\(d.name) — \(d.outputChannels) out").tag(d.uid)
                    }
                }
                if looper.outputChannelCount > 2 {
                    Picker("Output channels", selection: $looper.outputPair) {
                        ForEach(Array(stride(from: 0, to: looper.outputChannelCount, by: 2)), id: \.self) { i in
                            Text(i + 1 < looper.outputChannelCount ? "Outputs \(i + 1)–\(i + 2)" : "Output \(i + 1) (left only)").tag(i)
                        }
                    }
                }
                Picker("Input", selection: Binding(get: { looper.stereoInput }, set: { looper.stereoInput = $0 })) {
                    Text("Mono").tag(false)
                    Text("Stereo").tag(true)
                }
                .pickerStyle(.segmented)
                .disabled(looper.inputChannelCount < 2 && looper.monoInput)
                if looper.inputChannelCount < 2 {
                    Text("This input device has only one channel, so it records in mono.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if looper.monoInput {
                    Picker("Input channel", selection: $looper.inputLeftChannel) {
                        ForEach(0..<looper.inputChannelCount, id: \.self) { Text("Input \($0 + 1)").tag($0) }
                    }
                    Text("The selected channel is recorded on both sides (centre).")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker("Input channels", selection: Binding(get: { looper.inputPair }, set: { looper.inputPair = $0 })) {
                        ForEach(Array(stride(from: 0, to: looper.inputChannelCount - 1, by: 2)), id: \.self) { i in
                            Text("Inputs \(i + 1) + \(i + 2)").tag(i)
                        }
                        if looper.inputPair < 0 {
                            Text("Custom (\(looper.inputLeftChannel + 1) + \(looper.inputRightChannel + 1))").tag(-1)
                        }
                    }
                    DisclosureGroup("Custom left / right channels") {
                        Picker("Left", selection: $looper.inputLeftChannel) {
                            ForEach(0..<looper.inputChannelCount, id: \.self) { Text("Input \($0 + 1)").tag($0) }
                        }
                        Picker("Right", selection: $looper.inputRightChannel) {
                            ForEach(0..<looper.inputChannelCount, id: \.self) { Text("Input \($0 + 1)").tag($0) }
                        }
                    }
                    LabeledContent("Input levels") {
                        VStack(spacing: 4) {
                            HStack { Text("L").font(.caption2); LevelMeter(level: looper.snapshot.inLevelL) }
                            HStack { Text("R").font(.caption2); LevelMeter(level: looper.snapshot.inLevelR) }
                        }
                        .frame(width: 180)
                    }
                }
                Picker("Buffer size", selection: $looper.bufferFrames) {
                    Text("Device setting (currently \(looper.actualBufferFrames))").tag(0)
                    ForEach(looper.bufferChoices, id: \.self) { n in
                        Text("\(n) frames  ·  \(String(format: "%.1f", Double(n) / looper.core.sampleRate * 1000)) ms").tag(n)
                    }
                }
                Text("Smaller buffers = less latency but more CPU; raise it if you hear crackles. The buffer applies to the whole device.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text(looper.audioStatus).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh devices") { looper.refreshDevices() }
                }
            }
            Section("Audio") {
                LabeledContent("Latency compensation") {
                    Slider(value: $looper.latencyMs, in: 0...120)
                    Text(String(format: "%.1f ms", max(0, looper.latencyMs))).monospacedDigit().frame(width: 64)
                }
                HStack {
                    Text("Estimated round trip: \(String(format: "%.1f", looper.estimatedLatencyMs)) ms")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Use estimate") { looper.useEstimatedLatency() }
                    Button("Restart audio") { looper.restartAudio() }
                }
                Stepper("Maximum loop length: \(Int(looper.maxLoopMinutes)) min (applies after relaunch)",
                        value: $looper.maxLoopMinutes, in: 1...90, step: 1)
            }
        }
        .formStyle(.grouped)
    }
}

struct RhythmView: View {
    @EnvironmentObject var looper: LooperController
    @State private var category = ""

    private static let icons: [String: String] = [
        "Rock": "guitars", "Pop": "music.mic", "Funk": "figure.dance", "Blues": "music.note",
        "Jazz": "music.quarternote.3", "Latin": "sun.max", "Reggae": "leaf", "Metal": "bolt",
        "Electronic": "waveform", "Country": "music.note.house", "Odd Meter": "function", "Metronome": "metronome",
    ]

    var body: some View {
        let s = looper.settings
        VStack(spacing: 0) {
            // top bar: on/off, kit, variation, fills
            HStack(spacing: 14) {
                Toggle("Rhythm", isOn: $looper.settings.rhythmOn).toggleStyle(.switch)
                Divider().frame(height: 20)
                Picker("Kit", selection: $looper.settings.rhythmKit) {
                    ForEach(0..<RhythmLibrary.kitNames.count, id: \.self) { Text(RhythmLibrary.kitNames[$0]).tag($0) }
                }
                .frame(width: 170)
                Picker("Variation", selection: $looper.settings.rhythmVariation) {
                    Text("A").tag(0)
                    Text("B").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                Spacer()
                Toggle("Intro", isOn: $looper.settings.rhythmIntro)
                Toggle("Ending", isOn: $looper.settings.rhythmEnding)
                Toggle("Count-in", isOn: $looper.settings.countIn)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()

            HStack(spacing: 0) {
                // styles
                List(selection: Binding(get: { category }, set: { category = $0 ?? category })) {
                    Section("Styles") {
                        ForEach(RhythmLibrary.categories, id: \.self) { cat in
                            Label(cat, systemImage: Self.icons[cat] ?? "music.note")
                                .badge(RhythmLibrary.patterns.filter { $0.category == cat }.count)
                                .tag(cat)
                        }
                    }
                }
                .listStyle(.sidebar)
                .frame(width: 190)

                // patterns of the style
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                        ForEach(RhythmLibrary.patterns.indices.filter { RhythmLibrary.patterns[$0].category == category }, id: \.self) { i in
                            PatternCard(index: i, selected: s.rhythmPattern == i, variation: s.rhythmVariation, core: looper.core)
                                .onTapGesture { looper.selectPattern(i) }
                        }
                    }
                    .padding(16)
                }
            }
            Divider()

            // tempo + levels
            HStack(spacing: 18) {
                HStack(spacing: 8) {
                    Text("Tempo")
                    Slider(value: Binding(get: { looper.settings.tempo }, set: { looper.setTempo($0) }), in: looper.tempoRange)
                        .frame(width: 160)
                        .disabled(looper.tempoLocked)
                    Text(String(format: "%.1f", looper.settings.tempo)).monospacedDigit().frame(width: 44, alignment: .trailing)
                    Button("Tap") { looper.tapTempo() }
                }
                HStack(spacing: 8) {
                    Text("Level")
                    Slider(value: $looper.settings.rhythmLevel, in: 0...2).frame(width: 110)
                }
                HStack(spacing: 8) {
                    Text("Room")
                    Slider(value: $looper.settings.rhythmReverb, in: 0...1).frame(width: 90)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .onAppear { category = RhythmLibrary.pattern(looper.settings.rhythmPattern).category }
    }
}

/// One rhythm pattern as a card: name, meter, tempo and a small preview of its grid.
private struct PatternCard: View {
    let index: Int
    let selected: Bool
    let variation: Int
    let core: LoopCore

    var body: some View {
        let p = RhythmLibrary.pattern(index)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(p.name).font(.system(size: 13, weight: .semibold))
                Spacer()
                if selected { Image(systemName: "checkmark.circle.fill").foregroundColor(.accentColor) }
            }
            Text("\(p.signature) · ♩\(Int(p.tempo))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            MiniGrid(index: index, variation: selected ? variation : 0, core: core)
                .frame(height: 30)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: selected ? 2 : 1))
        .contentShape(Rectangle())
        .help("Click to select (turns the rhythm on)")
    }
}

/// Kick / snare / hi-hat rows of a pattern, drawn small.
private struct MiniGrid: View {
    let index: Int
    let variation: Int
    let core: LoopCore

    var body: some View {
        Canvas { ctx, size in
            let p = RhythmLibrary.pattern(index)
            let steps = max(1, min(kMaxSteps, p.steps))
            // pick up to three rows that have hits, preferring kick, snare, hats/ride/rim
            let order = [0, 1, 2, 4, 8, 9, 10, 3, 6, 7, 5]
            var rows: [Int] = []
            for d in order where rows.count < 3 {
                if (0..<steps).contains(where: { core.rhythm.cell(pattern: index, variation: variation, drum: d, step: $0) > 0 }) { rows.append(d) }
            }
            let gap: CGFloat = 2
            let w = (size.width - gap * CGFloat(steps - 1)) / CGFloat(steps)
            let h = (size.height - gap * 2) / 3
            for (r, d) in rows.enumerated() {
                for i in 0..<steps {
                    let v = core.rhythm.cell(pattern: index, variation: variation, drum: d, step: i)
                    let rect = CGRect(x: CGFloat(i) * (w + gap), y: CGFloat(r) * (h + gap), width: w, height: h)
                    let color: Color = v > 0 ? Color.accentColor.opacity(0.35 + 0.65 * Double(v)) : Color.secondary.opacity(0.15)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct MemoryView: View {
    @EnvironmentObject var looper: LooperController

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(String(format: "%02d", looper.memoryIndex + 1))
                    .font(.system(size: 20, weight: .heavy, design: .monospaced))
                TextField("Memory name", text: $looper.settings.name)
                    .textFieldStyle(.roundedBorder)
                Button("Write") { looper.writeMemory() }
                    .keyboardShortcut(.defaultAction)
            }
            HStack {
                Button("Import Audio…") { looper.importAudio() }
                Button("Export WAV…") { looper.exportAudio() }
                Spacer()
                Button("Delete Memory", role: .destructive) { looper.deleteMemory() }
            }
            List {
                ForEach(looper.memoryInfo) { info in
                    HStack {
                        Text(String(format: "%02d", info.id + 1)).monospacedDigit().foregroundStyle(.secondary)
                        Text(info.name)
                            .fontWeight(info.id == looper.memoryIndex ? .bold : .regular)
                        Spacer()
                        if let s = info.seconds {
                            Image(systemName: "waveform")
                            Text(String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .listRowBackground(info.id == looper.memoryIndex ? Color.accentColor.opacity(0.25) : Color.clear)
                    .onTapGesture { looper.selectMemory(info.id) }
                }
            }
            .listStyle(.inset)
            Text("Memories are stored in ~/Library/Application Support/Looper/Memories as 32-bit float WAV + settings.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
    }
}

struct HelpView: View {
    private let rows: [(String, String)] = [
        ("Space", "Play / stop (without a loop: play / stop the rhythm)"),
        ("R  or  Return", "Record → overdub → play (like the pedal)"),
        ("R ×2", "Stop"),
        ("Hold R 2 s", "Undo / redo last overdub (playing) · Clear (stopped)"),
        ("Esc / S", "Stop (hold Esc 2 s = clear)"),
        ("U  or  ⌘Z", "Undo / redo the last overdub"),
        ("Delete  or  ⌘⌫", "Clear loop"),
        ("M  or  ⌘R", "Rhythm on / off"),
        ("B  or  ⌘B", "Rhythm variation A / B"),
        ("T  or  ⌘T", "Tap tempo"),
        ("← / →  or  ⌘[ / ⌘]", "Previous / next memory"),
        ("⌘S", "Write memory"),
        ("Double-click a memory", "Rename it"),
        ("⌃⌘S / ⌃⌘R", "Show or hide memories / rhythm panel"),
        ("⌘I / ⌘E", "Import audio / export WAV"),
    ]

    var body: some View {
        Form {
            Section("Keyboard") {
                ForEach(rows.indices, id: \.self) { i in
                    LabeledContent(rows[i].0) { Text(rows[i].1).foregroundStyle(.secondary) }
                }
            }
            Section("Version") {
                LabeledContent("Looper", value: LooperController.version)
                LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–")
                LabeledContent("Architecture", value: LooperController.architecture)
            }
            Section("How it works") {
                Text("Press the pedal to record. Press again to close the loop: depending on Rec action it goes straight into overdub or into playback. Every overdub sits on its own layer, so the latest one can always be undone and redone. With Rhythm on and Loop quantize enabled, the loop length snaps to whole bars and the tempo is kept; without rhythm, the tempo is derived from the loop length.")
                Text("Set Latency compensation so overdubs line up with what you hear (the estimate is a good start; use headphones or a guitar via an audio interface to avoid feedback from the speakers).")
            }
        }
        .formStyle(.grouped)
    }
}
