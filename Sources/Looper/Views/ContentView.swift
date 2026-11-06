import SwiftUI

struct ContentView: View {
    @EnvironmentObject var looper: LooperController

    var body: some View {
        let theme = Theme.of(looper.themeID)
        let glow = StateColor.of(looper.snapshot.state, accent: theme.accent)
        HStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                PedalView()
                    .frame(width: 500)
                    .padding(24)
            }
            .frame(width: 548)
            SidePanel()
                .frame(minWidth: 460, maxWidth: .infinity)
                .background(.ultraThinMaterial)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1)
                }
        }
        .background(
            ZStack {
                LinearGradient(colors: [Color(red: 0.07, green: 0.075, blue: 0.09), Color(red: 0.02, green: 0.02, blue: 0.03)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [glow.opacity(0.25), .clear], center: .init(x: 0.22, y: 0.5), startRadius: 20, endRadius: 650)
                    .animation(.easeInOut(duration: 0.5), value: looper.snapshot.state)
            }
            .ignoresSafeArea()
        )
        .preferredColorScheme(.dark)
        .tint(theme.accent)
        .alert("Unsaved loop", isPresented: Binding(get: { looper.pendingMemorySwitch != nil }, set: { _ in })) {
            Button("Write, then Switch") { looper.writeThenSwitch() }
            Button("Discard", role: .destructive) { looper.confirmSwitch() }
            Button("Cancel", role: .cancel) { looper.cancelSwitch() }
        } message: {
            Text("Memory \(String(format: "%02d", looper.memoryIndex + 1)) has changes that haven't been written.")
        }
    }
}

struct SidePanel: View {
    @EnvironmentObject var looper: LooperController

    var body: some View {
        VStack(spacing: 0) {
            TabBar(selection: $looper.selectedTab, accent: Theme.of(looper.themeID).accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            switch looper.selectedTab {
            case .setup: SetupView()
            case .audio: AudioSetupView()
            case .rhythm: RhythmView()
            case .memory: MemoryView()
            case .help: HelpView()
            }
        }
        .scrollContentBackground(.hidden)
    }
}

/// Icon tab bar for the side panel.
struct TabBar: View {
    @Binding var selection: SideTab
    var accent: Color
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SideTab.allCases) { tab in
                let selected = tab == selection
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = tab }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.symbol)
                        Text(tab.rawValue).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(selected ? .black : .white.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background {
                        if selected {
                            Capsule().fill(accent)
                                .shadow(color: accent.opacity(0.6), radius: 8)
                                .matchedGeometryEffect(id: "tab", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
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
                Toggle("Count-in (one bar of rhythm before recording)", isOn: $looper.settings.countIn)
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
                Picker("Theme", selection: $looper.themeID) {
                    ForEach(ThemeID.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("MIDI") {
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
                Toggle("Mono input (one input channel on both sides)", isOn: $looper.monoInput)
                if looper.inputChannelCount > 1 {
                    Picker(looper.monoInput ? "Input channel" : "Left input channel", selection: $looper.inputLeftChannel) {
                        ForEach(0..<looper.inputChannelCount, id: \.self) { Text("Input \($0 + 1)").tag($0) }
                    }
                    if !looper.monoInput {
                        Picker("Right input channel", selection: $looper.inputRightChannel) {
                            ForEach(0..<looper.inputChannelCount, id: \.self) { Text("Input \($0 + 1)").tag($0) }
                        }
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

    var body: some View {
        Form {
            Section {
                Toggle("Rhythm", isOn: $looper.settings.rhythmOn)
                LabeledContent("Pattern") {
                    Button { looper.selectPattern((looper.settings.rhythmPattern + RhythmLibrary.patterns.count - 1) % RhythmLibrary.patterns.count) } label: {
                        Image(systemName: "chevron.left")
                    }
                    Picker("", selection: Binding(get: { looper.settings.rhythmPattern }, set: { looper.selectPattern($0) })) {
                        ForEach(RhythmLibrary.categories, id: \.self) { cat in
                            Section(cat) {
                                ForEach(RhythmLibrary.patterns.indices.filter { RhythmLibrary.patterns[$0].category == cat }, id: \.self) { i in
                                    Text(String(format: "%02d  ", i + 1) + RhythmLibrary.patterns[i].name).tag(i)
                                }
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240)
                    Button { looper.selectPattern((looper.settings.rhythmPattern + 1) % RhythmLibrary.patterns.count) } label: {
                        Image(systemName: "chevron.right")
                    }
                }
                Picker("Variation", selection: $looper.settings.rhythmVariation) {
                    Text("A").tag(0)
                    Text("B").tag(1)
                }
                .pickerStyle(.segmented)
                Picker("Kit", selection: $looper.settings.rhythmKit) {
                    ForEach(0..<RhythmLibrary.kitNames.count, id: \.self) { i in
                        Text(RhythmLibrary.kitNames[i]).tag(i)
                    }
                }
                LabeledContent("Tempo") {
                    Slider(value: Binding(get: { looper.settings.tempo }, set: { looper.setTempo($0) }), in: looper.tempoRange)
                        .disabled(looper.tempoLocked)
                    Text(String(format: "%.1f", looper.settings.tempo)).monospacedDigit().frame(width: 48)
                    Stepper("", onIncrement: { looper.setTempo(looper.settings.tempo + 1) },
                            onDecrement: { looper.setTempo(looper.settings.tempo - 1) })
                        .labelsHidden()
                        .disabled(looper.tempoLocked)
                    Button("Tap") { looper.tapTempo() }
                }
                if looper.hasLoop {
                    LabeledContent("Loop speed") {
                        Text("\(Int((looper.snapshot.tempo / max(1, looper.snapshot.loopTempo) * 100).rounded())) %  ·  recorded at ♩\(String(format: "%.1f", looper.snapshot.loopTempo)), \(looper.settings.loopMeasures) bar\(looper.settings.loopMeasures == 1 ? "" : "s")")
                            .monospacedDigit()
                        Button("Original tempo") { looper.resetTempo() }
                            .disabled(abs(looper.snapshot.tempo - looper.snapshot.loopTempo) < 0.05)
                    }
                    Picker("Tempo change", selection: $looper.settings.stretchMode) {
                        ForEach(StretchMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text("Changing the tempo speeds the recorded loop up or down (50–200 %), and the rhythm follows. Overdubs recorded at another tempo are fitted into the loop.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("Rhythm level") {
                    Slider(value: $looper.settings.rhythmLevel, in: 0...2)
                    Text("\(Int(looper.settings.rhythmLevel * 100))").monospacedDigit().frame(width: 48)
                }
                LabeledContent("Reverb") {
                    Slider(value: $looper.settings.rhythmReverb, in: 0...1)
                    Text("\(Int(looper.settings.rhythmReverb * 100))").monospacedDigit().frame(width: 48)
                }
            }
            ForEach(RhythmLibrary.categories, id: \.self) { cat in
                Section(cat) {
                    ForEach(RhythmLibrary.patterns.indices.filter { RhythmLibrary.patterns[$0].category == cat }, id: \.self) { i in
                        let p = RhythmLibrary.patterns[i]
                        HStack {
                                Text(String(format: "%02d", i + 1)).monospacedDigit().foregroundStyle(.secondary)
                                Text(p.name)
                                Spacer()
                                Text(p.signature).foregroundStyle(.secondary)
                                Text("♩\(Int(p.tempo))").monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                                Image(systemName: "checkmark")
                                    .opacity(looper.settings.rhythmPattern == i ? 1 : 0)
                                    .foregroundStyle(Color.accentColor)
                        }
                        .padding(.vertical, 2)
                        .background(looper.settings.rhythmPattern == i ? Color.accentColor.opacity(0.18) : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { looper.selectPattern(i) }
                    }
                }
            }
        }
        .formStyle(.grouped)
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
        ("Space", "Pedal: REC → DUB/PLAY → … (tap)"),
        ("Space ×2", "Stop"),
        ("Hold Space 2 s", "Undo / redo last overdub (playing) · Clear (stopped)"),
        ("Esc / S", "Stop (hold Esc 2 s = clear)"),
        ("U  or  ⌘U", "Undo / redo"),
        ("Delete  or  ⌘⌫", "Clear loop"),
        ("R  or  ⌘R", "Rhythm on / off"),
        ("B  or  ⌘B", "Rhythm variation A / B"),
        ("T  or  ⌘T", "Tap tempo"),
        ("← / →  or  ⌘[ / ⌘]", "Previous / next memory"),
        ("⌘S", "Write memory"),
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
            }
            Section("How it works") {
                Text("Press the pedal to record. Press again to close the loop: depending on Rec action it goes straight into overdub or into playback. Every overdub sits on its own layer, so the latest one can always be undone and redone. With Rhythm on and Loop quantize enabled, the loop length snaps to whole bars and the tempo is kept; without rhythm, the tempo is derived from the loop length.")
                Text("Set Latency compensation so overdubs line up with what you hear (the estimate is a good start; use headphones or a guitar via an audio interface to avoid feedback from the speakers).")
            }
        }
        .formStyle(.grouped)
    }
}
