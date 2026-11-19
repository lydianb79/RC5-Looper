import AppKit
import SwiftUI

// MARK: - Design tokens

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum UI {
    /// Set by LooperController when the theme changes.
    static var theme: AppTheme = .graphite
    static var panel: Color { theme.palette.panel }
    static var header: Color { theme.palette.header }
    static var line: Color { theme.palette.line }
    static var rhythm: Color { theme.palette.accent }
    static var selection: Color { theme.palette.selection }
    static var lcd: Color { theme.palette.lcd }
    static var line2: Color { theme.palette.line2 }
    static var control: Color { theme.palette.control }
    static var controlHi: Color { theme.palette.controlHi }
    static var well: Color { theme.palette.well }
    static var wellAlt: Color { theme.palette.wellAlt }
    static var track: Color { theme.palette.track }
    static var dim: Color { theme.palette.dim }
    static var text: Color { theme.palette.text }
    static var text2: Color { theme.palette.text2 }
    static var muted: Color { theme.palette.muted }
    static var base: Color { theme.palette.base }
    static var light: Bool { theme.palette.light }
    static let dub = Color(hex: 0xFFB340)

    static func state(_ s: LoopState) -> Color {
        switch s {
        case .recording, .armed, .autoRecArmed: return Color(hex: 0xFF453A)
        case .overdubbing: return Color(hex: 0xFF9F0A)
        case .playing: return Color(hex: 0x30D158)
        case .stopped: return Color(hex: 0x64D2FF)
        case .empty: return Color(hex: 0x8E8E99)
        }
    }

    static func tint(_ s: LoopState) -> Color {
        state(s).opacity(light ? 0.16 : 0.2)
    }

    static let mono = Font.system(size: 20, weight: .bold, design: .monospaced)
}

private func fmtTime(_ x: Double) -> String {
    String(format: "%d:%04.1f", Int(x) / 60, x.truncatingRemainder(dividingBy: 60))
}

// MARK: - Opening the Settings window on a given tab

struct SettingsButton<Label: View>: View {
    let looper: LooperController
    let tab: SideTab
    @ViewBuilder var label: () -> Label

    var body: some View {
        if #available(macOS 14.0, *) {
            SettingsButton14(looper: looper, tab: tab, label: label)
        } else {
            Button {
                looper.selectedTab = tab
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: { label() }
        }
    }
}

@available(macOS 14.0, *)
private struct SettingsButton14<Label: View>: View {
    @Environment(\.openSettings) private var openSettings
    let looper: LooperController
    let tab: SideTab
    let label: () -> Label

    var body: some View {
        Button {
            looper.selectedTab = tab
            openSettings()
        } label: { label() }
    }
}

// MARK: - Main window

struct StudioView: View {
    @EnvironmentObject var looper: LooperController

    var body: some View {
        let snap = looper.snapshot
        VStack(spacing: 0) {
            StudioHeader(showSidebar: $looper.showSidebar)
            HStack(spacing: 0) {
                if looper.showSidebar {
                    MemorySidebar()
                        .frame(width: 244)
                        .overlay(alignment: .trailing) { Rectangle().fill(UI.line).frame(width: 1) }
                        .transition(.move(edge: .leading))
                }
                ScrollView(.vertical) {
                    StageView()
                        .padding(.horizontal, 24)
                        .padding(.vertical, 22)
                }
            }
            StudioFooter()
        }
        .id(looper.appTheme)       // UI colours are static: rebuild the view tree so every panel picks up the new theme
        .background(ThemeBackground(theme: looper.appTheme, stateColor: UI.state(snap.state),
                                    live: snap.state == .playing || snap.state == .overdubbing || snap.state == .recording))
        .ignoresSafeArea(.container, edges: .top)
        .foregroundColor(UI.text)
        .preferredColorScheme(UI.light ? .light : .dark)
        .tint(UI.rhythm)
        .animation(.easeInOut(duration: 0.2), value: looper.showSidebar)
        .animation(.easeInOut(duration: 0.2), value: looper.showRhythm)
        .sheet(item: Binding(get: { looper.renamingSlot.map { RenameTarget(id: $0) } },
                             set: { looper.renamingSlot = $0?.id })) { target in
            RenameSheet(slot: target.id).environmentObject(looper)
        }
        .sheet(isPresented: $looper.showExport) { ExportSheet().environmentObject(looper) }
        .sheet(item: Binding(get: { looper.renamingPattern.map { RenameTarget(id: $0) } },
                             set: { looper.renamingPattern = $0?.id })) { target in
            PatternRenameSheet(index: target.id).environmentObject(looper)
        }
        .overlay(alignment: .top) {
            if let msg = looper.message {
                Text(msg)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.8)))
                    .overlay(Capsule().stroke(UI.state(looper.snapshot.state).opacity(0.8), lineWidth: 1))
                    .padding(.top, 66)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: looper.message)
        .alert("Unsaved loop", isPresented: Binding(get: { looper.pendingMemorySwitch != nil }, set: { _ in })) {
            Button("Write, then Switch") { looper.writeThenSwitch() }
            Button("Discard", role: .destructive) { looper.confirmSwitch() }
            Button("Cancel", role: .cancel) { looper.cancelSwitch() }
        } message: {
            Text("Memory \(String(format: "%02d", looper.memoryIndex + 1)) has changes that haven't been written.")
        }
    }
}

// MARK: - Header (toolbar)

private struct StudioHeader: View {
    @EnvironmentObject var looper: LooperController
    @Binding var showSidebar: Bool
    @State private var showTempo = false

    var body: some View {
        let snap = looper.snapshot
        HStack(spacing: 14) {
            Color.clear.frame(width: 62, height: 1)          // room for the window buttons
            IconButton(symbol: "sidebar.left", help: "Show or hide memories", active: showSidebar) { showSidebar.toggle() }
            Text("LOOPER")
                .font(.system(size: 13, weight: .heavy))
                .tracking(2)
            Text("\(String(format: "%02d", looper.memoryIndex + 1)) · \(looper.settings.name)")
                .foregroundColor(UI.muted)
                .lineLimit(1)
            Spacer(minLength: 16)

            HStack(spacing: 4) {
                TransportButton(symbol: "circle.fill", color: Color(hex: 0xFF453A),
                                active: snap.state == .recording || snap.state == .overdubbing || snap.state == .armed,
                                help: "Record / overdub") { looper.recordButton() }
                TransportButton(symbol: "play.fill", color: Color(hex: 0x30D158), active: snap.state == .playing,
                                help: "Play") { looper.playButton() }
                TransportButton(symbol: "stop.fill", color: UI.text2, active: false, help: "Stop (Esc)") { looper.stop() }
            }

            LCDView(showTempo: $showTempo)

            Button("Tap") { looper.tapTempo() }
                .buttonStyle(PillButtonStyle())
                .help("Tap tempo (T)")

            Spacer(minLength: 16)

            HStack(spacing: 6) {
                PillToggle(title: "Rhythm", symbol: "metronome", isOn: looper.settings.rhythmOn) { looper.toggleRhythm() }
                PillToggle(title: "Count-in", symbol: nil, isOn: looper.settings.countIn) { looper.settings.countIn.toggle() }
                LoopLengthMenu()
            }
            InputMeter()
            Menu {
                ForEach(AppTheme.allCases) { t in
                    Button { looper.appTheme = t } label: {
                        if t == looper.appTheme { Label(t.label, systemImage: "checkmark") } else { Text(t.label) }
                    }
                }
            } label: {
                Image(systemName: "paintpalette")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Theme")
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(UI.header)
        .overlay(alignment: .bottom) { Rectangle().fill(UI.line2).frame(height: 1) }
    }
}

private struct LCDView: View {
    @EnvironmentObject var looper: LooperController
    @Binding var showTempo: Bool

    var body: some View {
        let snap = looper.snapshot
        let c = UI.state(snap.state)
        let live = snap.state == .playing || snap.state == .overdubbing || snap.state == .recording
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                Circle().fill(c).frame(width: 7, height: 7).shadow(color: live ? c : .clear, radius: 4)
                Text(stateWord(snap))
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.2)
                    .foregroundColor(c)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(UI.tint(snap.state)))
            .padding(.horizontal, 5)

            Text("\(snap.measure).\(snap.beat)")
                .font(UI.mono)
                .monospacedDigit()
                .frame(minWidth: 64)
                .padding(.horizontal, 10)
            divider
            Text(timeText(snap))
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(UI.text2)
                .padding(.horizontal, 12)
            divider
            Button { showTempo.toggle() } label: {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", snap.tempo)).font(UI.mono).monospacedDigit()
                    Text(abs(snap.playbackRate - 1) > 0.001 ? "BPM \(Int((snap.playbackRate * 100).rounded()))%" : "BPM")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(abs(snap.playbackRate - 1) > 0.001 ? UI.dub : UI.muted)
                }
                .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
            .help("Tempo")
            .popover(isPresented: $showTempo, arrowEdge: .bottom) { TempoPopover().environmentObject(looper) }
            divider
            Text(RhythmLibrary.pattern(looper.settings.rhythmPattern).signature)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(UI.text2)
                .padding(.horizontal, 12)
        }
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 10).fill(UI.lcd))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.line2, lineWidth: 1))
    }

    private var divider: some View { Rectangle().fill(UI.line2).frame(width: 1, height: 26) }

    private func stateWord(_ s: Snapshot) -> String {
        if s.state == .armed { return s.countdownBeats > 0 ? "COUNT \(s.countdownBeats)" : "WAIT" }
        if s.stopping { return looper.settings.rhythmEnding && looper.settings.rhythmOn ? "ENDING" : "STOPPING" }
        if s.state == .recording && s.waitingQuantize { return "REC…" }
        return s.state.label
    }

    private func timeText(_ s: Snapshot) -> String {
        if s.state == .empty { return "0:00.0" }
        if s.state == .recording { return fmtTime(s.recordSeconds) }
        let total = s.loopSeconds * (s.loopTempo > 0 ? s.loopTempo / max(1, s.tempo) : 1)
        return "\(fmtTime(s.position * total)) / \(fmtTime(total))"
    }
}

/// Type a tempo (BPM) and press Return. Accepts "92", "92.5" or "92,5".
struct TempoField: View {
    @EnvironmentObject var looper: LooperController
    var autofocus = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("BPM", text: $text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 64)
            .focused($focused)
            .disabled(looper.tempoLocked)
            .help("Type a tempo and press Return")
            .onSubmit(apply)
            .onAppear {
                text = Self.format(looper.settings.tempo)
                if autofocus { DispatchQueue.main.async { focused = true } }
            }
            .onChange(of: looper.settings.tempo) { t in if !focused { text = Self.format(t) } }
            .onChange(of: focused) { f in if !f { apply() } }
    }

    private func apply() {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if let v = Double(cleaned), v > 0, abs(v - looper.settings.tempo) > 0.04 {
            looper.setTempo(v)
        }
        text = Self.format(looper.settings.tempo)
    }

    static func format(_ t: Double) -> String {
        t.rounded() == t ? String(Int(t)) : String(format: "%.1f", t)
    }
}

private struct TempoPopover: View {
    @EnvironmentObject var looper: LooperController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tempo").font(.headline)
            HStack {
                Slider(value: Binding(get: { looper.settings.tempo }, set: { looper.setTempo($0) }), in: looper.tempoRange)
                    .disabled(looper.tempoLocked)
                TempoField(autofocus: true)
                Stepper("", onIncrement: { looper.setTempo(looper.settings.tempo + 1) },
                        onDecrement: { looper.setTempo(looper.settings.tempo - 1) })
                    .labelsHidden()
            }
            if looper.hasLoop {
                HStack {
                    Text("Recorded at ♩\(String(format: "%.1f", looper.snapshot.loopTempo))").foregroundStyle(.secondary)
                    Spacer()
                    Button("Original tempo") { looper.resetTempo() }
                }
                Picker("Tempo change", selection: $looper.settings.stretchMode) {
                    ForEach(StretchMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            HStack {
                Button("Tap") { looper.tapTempo() }
                Spacer()
                if looper.syncExternal {
                    Text(looper.externalClockTempo != nil ? "Following MIDI clock" : "Waiting for MIDI clock")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}

private struct InputMeter: View {
    @EnvironmentObject var looper: LooperController

    var body: some View {
        let snap = looper.snapshot
        let stereo = !looper.monoInput && looper.inputChannelCount > 1
        let levels: [Float] = stereo ? [snap.inLevelL, snap.inLevelR] : [snap.inLevel, snap.inLevel]
        HStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<2, id: \.self) { i in
                    let f = meterFraction(levels[i])
                    VStack {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(f > 0.85 ? Color(hex: 0xFFD60A) : Color(hex: 0x30D158))
                            .frame(height: max(3, 28 * f))
                    }
                    .frame(width: 6, height: 28)
                    .background(RoundedRectangle(cornerRadius: 2).fill(UI.control))
                }
            }
            Text(looper.inputRoutingText.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(UI.muted)
        }
        .help("Input level")
    }
}

// MARK: - Sidebar

private struct MemorySidebar: View {
    @EnvironmentObject var looper: LooperController

    var body: some View {
        let used = looper.memoryInfo.filter { $0.seconds != nil }.count
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $looper.showSong) {
                Text("Memories").tag(false)
                Text(looper.songActive ? "Song ▶" : "Song").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 4)
            if looper.showSong {
                SongPanel()
            } else {
            HStack {
                Text("MEMORIES").font(.system(size: 10.5, weight: .bold)).tracking(1.2).foregroundColor(UI.muted)
                Text("\(used) / 99").font(.system(size: 11)).foregroundColor(UI.muted)
                Spacer()
                IconButton(symbol: "plus", help: "Go to the next empty memory", active: false) {
                    if let empty = looper.memoryInfo.first(where: { $0.seconds == nil && $0.id != looper.memoryIndex }) {
                        looper.selectMemory(empty.id)
                    }
                }
            }
            .padding(.horizontal, 6)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(looper.memoryInfo) { info in
                            MemoryRow(info: info, selected: info.id == looper.memoryIndex,
                                      liveThumb: info.id == looper.memoryIndex ? looper.waveform : nil)
                                .id(info.id)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { looper.renamingSlot = info.id }
                                .onTapGesture { looper.selectMemory(info.id) }
                                .contextMenu {
                                    Button("Load") { looper.selectMemory(info.id) }
                                    Button("Rename…") { looper.renamingSlot = info.id }
                                    if info.id == looper.memoryIndex {
                                        Button("Write current loop") { looper.writeMemory() }
                                        Button("Delete memory", role: .destructive) { looper.deleteMemory() }
                                    }
                                }
                        }
                    }
                }
                .onAppear { proxy.scrollTo(looper.memoryIndex, anchor: .center) }
            }
            HStack(spacing: 6) {
                Button("Import…") { looper.importAudio() }.buttonStyle(PillButtonStyle(full: true))
                Button("Export…") { looper.showExport = true }.buttonStyle(PillButtonStyle(full: true))
            }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(UI.panel)
    }

}

private struct MemoryRow: View {
    let info: MemoryInfo
    let selected: Bool
    let liveThumb: [Float]?

    var body: some View {
        let empty = info.seconds == nil && liveThumb?.isEmpty != false
        HStack(spacing: 10) {
            Text(String(format: "%02d", info.id + 1))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(selected ? (UI.light ? .white : Color(hex: 0x121215)) : (empty ? UI.muted : UI.text))
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(selected ? UI.base : UI.control))
            VStack(alignment: .leading, spacing: 4) {
                Text(info.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(empty ? UI.muted : UI.text)
                    .lineLimit(1)
                if empty {
                    Text("empty").font(.system(size: 11)).foregroundColor(UI.muted)
                } else {
                    ThumbView(values: thumb, color: selected ? .white : UI.dim)
                        .frame(height: 12)
                }
            }
            Spacer(minLength: 0)
            if info.rhythm && !empty {
                Image(systemName: "metronome")
                    .font(.system(size: 11))
                    .foregroundColor(selected ? .white : UI.muted)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(selected ? UI.selection : Color.clear))
    }

    private var thumb: [Float] {
        if let live = liveThumb, !live.isEmpty { return LooperController.thumbnail(from: live, count: 28) }
        return info.thumb.isEmpty ? Array(repeating: 0.3, count: 28) : info.thumb
    }
}

private struct ThumbView: View {
    let values: [Float]
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let n = max(1, values.count)
            let w = size.width / CGFloat(n)
            for (i, v) in values.enumerated() {
                let h = max(2, CGFloat(sqrt(Double(v))) * size.height)
                ctx.fill(Path(roundedRect: CGRect(x: CGFloat(i) * w, y: (size.height - h) / 2, width: max(1, w - 1), height: h), cornerRadius: 1),
                         with: .color(color))
            }
        }
    }
}

// MARK: - Stage

private struct StageView: View {
    @EnvironmentObject var looper: LooperController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TitleRow()
            HStack(alignment: .center, spacing: 22) {
                HeroRing().frame(width: 300, height: 300)
                LanesView()
            }
            PerformanceRow()
            LoopToolsRow()
            if looper.showTracks { TracksPanel().transition(.opacity) }
            if looper.showRhythm { RhythmPanel().transition(.opacity) }
            if looper.showEffects { EffectsPanel().transition(.opacity) }
        }
        .frame(maxWidth: 1400, alignment: .leading)
    }
}

private struct TitleRow: View {
    @EnvironmentObject var looper: LooperController

    var body: some View {
        let snap = looper.snapshot
        HStack(spacing: 10) {
            Text(looper.settings.name)
                .font(.system(size: 22, weight: .bold))
                .lineLimit(1)
                .onTapGesture(count: 2) { looper.renamingSlot = looper.memoryIndex }
                .help("Double-click to rename")
            Button { looper.renamingSlot = looper.memoryIndex } label: {
                Image(systemName: "pencil").font(.system(size: 12, weight: .semibold)).foregroundColor(UI.muted)
            }
            .buttonStyle(.plain)
            .help("Rename memory")
            if looper.dirty {
                Circle().fill(UI.dub).frame(width: 7, height: 7).help("Not written yet")
            }
            HStack(spacing: 6) {
                if snap.totalMeasures > 0 { Chip(text: "\(snap.totalMeasures) bar\(snap.totalMeasures == 1 ? "" : "s")") }
                if snap.loopTempo > 0 { Chip(text: "Recorded ♩\(String(format: "%.1f", snap.loopTempo))") }
                Chip(text: looper.monoInput || looper.inputChannelCount < 2 ? "Mono in" : "Stereo in")
                if snap.hasDubLayer { Chip(text: snap.dubActive ? "Overdub layer" : "Overdub undone") }
            }
            Spacer()
            Button { looper.writeMemory() } label: {
                HStack(spacing: 8) {
                    Text("Write to \(String(format: "%02d", looper.memoryIndex + 1))")
                    Text("⌘S").foregroundColor(UI.muted)
                }
            }
            .buttonStyle(PillButtonStyle())
        }
    }
}

private struct Chip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundColor(UI.text2)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(UI.control))
    }
}

/// The large circular loop display.
private struct HeroRing: View {
    @EnvironmentObject var looper: LooperController

    var body: some View {
        let snap = looper.snapshot
        let c = UI.state(snap.state)
        let live = snap.state == .playing || snap.state == .overdubbing || snap.state == .recording
        let pulse = live ? (0.10 + 0.10 * (1 - snap.beatPhase)) : 0.05
        ZStack {
            Circle()
                .fill(c)
                .frame(width: 230, height: 230)
                .blur(radius: 42)
                .opacity(pulse)
            RingCanvas(wave: looper.waveform, position: snap.state == .recording ? 1 : snap.position,
                       color: c, measures: snap.totalMeasures, reverse: looper.settings.reverse,
                       showDot: snap.state == .playing || snap.state == .overdubbing, empty: snap.state == .empty)
            VStack(spacing: 2) {
                Text(centerWord(snap))
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(1.8)
                    .foregroundColor(c)
                Text(snap.state == .armed && snap.countdownBeats > 0 ? "\(snap.countdownBeats)" : "\(snap.measure).\(snap.beat)")
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                Text(subtitle(snap))
                    .font(.system(size: 11.5))
                    .foregroundColor(UI.muted)
            }
        }
        .animation(.easeOut(duration: 0.12), value: snap.beat)
    }

    private func centerWord(_ s: Snapshot) -> String {
        if s.state == .armed { return "COUNT-IN" }
        if s.state == .empty { return "READY" }
        return s.state.label
    }

    private func subtitle(_ s: Snapshot) -> String {
        switch s.state {
        case .empty: return "press R to record"
        case .armed: return "recording starts on beat 1"
        case .recording: return fmtTime(s.recordSeconds)
        default: return s.totalMeasures > 0 ? "bar · beat of \(s.totalMeasures) bar\(s.totalMeasures == 1 ? "" : "s")" : "bar · beat"
        }
    }
}

private struct RingCanvas: View {
    let wave: [Float]
    let position: Double
    let color: Color
    let measures: Int
    let reverse: Bool
    let showDot: Bool
    let empty: Bool

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = min(size.width, size.height) / 2 - 18
            let inner = outer * 0.64
            let barMax = outer - inner - 12
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2)),
                       with: .color(UI.well), lineWidth: 10)
            // radial waveform
            let n = 96
            if !wave.isEmpty {
                for i in 0..<n {
                    let a0 = i * wave.count / n
                    let a1 = max(a0 + 1, (i + 1) * wave.count / n)
                    let v = wave[a0..<min(a1, wave.count)].max() ?? 0
                    let f = Double(i) / Double(n)
                    let ang = -Double.pi / 2 + 2 * Double.pi * (reverse ? 1 - f : f)
                    let len = max(2, CGFloat(sqrt(Double(v))) * barMax)
                    var p = Path()
                    p.move(to: CGPoint(x: c.x + CGFloat(cos(ang)) * inner, y: c.y + CGFloat(sin(ang)) * inner))
                    p.addLine(to: CGPoint(x: c.x + CGFloat(cos(ang)) * (inner + len), y: c.y + CGFloat(sin(ang)) * (inner + len)))
                    ctx.stroke(p, with: .color(f <= position ? color : UI.track), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                }
            }
            // bar ticks
            let ticks = max(4, measures)
            for m in 0..<ticks {
                let ang = -Double.pi / 2 + 2 * Double.pi * Double(m) / Double(ticks)
                var t = Path()
                t.move(to: CGPoint(x: c.x + CGFloat(cos(ang)) * (outer + 8), y: c.y + CGFloat(sin(ang)) * (outer + 8)))
                t.addLine(to: CGPoint(x: c.x + CGFloat(cos(ang)) * (outer + 15), y: c.y + CGFloat(sin(ang)) * (outer + 15)))
                ctx.stroke(t, with: .color(UI.dim), lineWidth: 2)
            }
            // progress arc
            if !empty && position > 0.001 {
                var arc = Path()
                let end = Angle.degrees(-90 + 360 * (reverse ? -position : position))
                arc.addArc(center: c, radius: outer, startAngle: .degrees(-90), endAngle: end, clockwise: reverse)
                var g = ctx
                g.addFilter(.shadow(color: color.opacity(0.7), radius: 8))
                g.stroke(arc, with: .color(color), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                if showDot {
                    let a = end.radians
                    let dot = CGPoint(x: c.x + CGFloat(cos(a)) * outer, y: c.y + CGFloat(sin(a)) * outer)
                    g.fill(Path(ellipseIn: CGRect(x: dot.x - 9, y: dot.y - 9, width: 18, height: 18)), with: .color(.white))
                }
            }
        }
    }
}

/// Timeline lanes: committed audio and the undoable overdub layer, with a sweeping playhead.
private struct LanesView: View {
    @EnvironmentObject var looper: LooperController
    private let headerWidth: CGFloat = 124

    var body: some View {
        let snap = looper.snapshot
        let stateC = UI.state(snap.state)
        let pos = snap.state == .recording ? 1.0 : snap.position
        let showHead = snap.state == .playing || snap.state == .overdubbing
        VStack(spacing: 8) {
            LaneView(title: "Base", meta: baseMeta(snap), color: UI.base, wave: looper.baseWave, position: pos,
                     glow: showHead, active: snap.state == .recording, activeColor: stateC, dimmed: false, headerWidth: headerWidth)
            if snap.hasDubLayer {
                LaneView(title: "Overdub", meta: dubMeta(snap), color: UI.dub, wave: looper.dubWave, position: pos,
                         glow: showHead && snap.dubActive, active: snap.state == .overdubbing, activeColor: stateC,
                         dimmed: !snap.dubActive, headerWidth: headerWidth)
            } else {
                EmptyLane(headerWidth: headerWidth, canDub: snap.state == .playing || snap.state == .stopped)
            }
        }
        .overlay {
            if showHead {
                GeometryReader { geo in
                    let x = headerWidth + (geo.size.width - headerWidth - 10) * CGFloat(pos)
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2)
                        .shadow(color: .white.opacity(0.7), radius: 5)
                        .position(x: x, y: geo.size.height / 2)
                        .frame(height: geo.size.height)
                }
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func baseMeta(_ s: Snapshot) -> String {
        switch s.state {
        case .recording: return "recording…"
        case .empty, .armed, .autoRecArmed: return "empty"
        default: return "\(fmtTime(s.loopSeconds)) · committed"
        }
    }

    private func dubMeta(_ s: Snapshot) -> String {
        if s.state == .overdubbing { return "recording…" }
        return s.dubActive ? "last take · ⌘Z undoes" : "undone · ⌘Z redoes"
    }
}

private struct LaneView: View {
    let title: String
    let meta: String
    let color: Color
    let wave: [Float]
    let position: Double
    let glow: Bool
    let active: Bool
    let activeColor: Color
    let dimmed: Bool
    let headerWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 3).fill(dimmed ? UI.dim : color).frame(width: 9, height: 9)
                    Text(title).font(.system(size: 12.5, weight: .semibold))
                }
                Text(meta).font(.system(size: 11)).foregroundColor(UI.muted).lineLimit(1)
            }
            .padding(.leading, 12)
            .frame(width: headerWidth, alignment: .leading)
            Canvas { ctx, size in
                let n = 120
                guard !wave.isEmpty else {
                    ctx.fill(Path(CGRect(x: 0, y: size.height / 2 - 1, width: size.width, height: 2)), with: .color(UI.track))
                    return
                }
                let w = size.width / CGFloat(n)
                for i in 0..<n {
                    let a0 = i * wave.count / n
                    let a1 = max(a0 + 1, (i + 1) * wave.count / n)
                    let v = wave[a0..<min(a1, wave.count)].max() ?? 0
                    let f = Double(i) / Double(n)
                    let h = max(2, CGFloat(sqrt(Double(v))) * (size.height - 16))
                    let rect = CGRect(x: CGFloat(i) * w, y: (size.height - h) / 2, width: max(1, w - 1.5), height: h)
                    let near = glow && abs(f - position) < 0.02
                    let opacity = dimmed ? 0.35 : (near ? 1 : (f <= position ? 0.95 : 0.32))
                    let col = dimmed ? UI.track : color
                    if near {
                        var g = ctx
                        g.addFilter(.shadow(color: col, radius: 5))
                        g.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(col.opacity(opacity)))
                    } else {
                        ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(col.opacity(opacity)))
                    }
                }
            }
            .padding(.trailing, 10)
        }
        .frame(height: 78)
        .background(RoundedRectangle(cornerRadius: 12).fill(UI.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(active ? activeColor : UI.line, lineWidth: active ? 1.5 : 1))
        .shadow(color: active ? activeColor.opacity(0.25) : .clear, radius: 12)
    }
}

private struct EmptyLane: View {
    let headerWidth: CGFloat
    let canDub: Bool

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 3).stroke(UI.dub.opacity(0.6), lineWidth: 1).frame(width: 9, height: 9)
                Text("Overdub").font(.system(size: 12.5, weight: .semibold)).foregroundColor(UI.muted)
            }
            .padding(.leading, 12)
            .frame(width: headerWidth, alignment: .leading)
            Text(canDub ? "Press R while playing to record an overdub layer" : "Overdubs appear here as an undoable layer")
                .font(.system(size: 12))
                .foregroundColor(UI.muted)
            Spacer()
        }
        .frame(height: 78)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(UI.line2, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }
}

// MARK: - Performance row

private struct PerformanceRow: View {
    @EnvironmentObject var looper: LooperController

    var body: some View {
        let snap = looper.snapshot
        let c = UI.state(snap.state == .empty ? .recording : snap.state)
        let live = snap.state == .playing || snap.state == .overdubbing || snap.state == .recording || snap.state == .armed
        HStack(spacing: 12) {
            MomentarySwitch(onDown: { looper.pedalDown() }, onUp: { looper.pedalUp() }) { pressed in
                HStack(spacing: 14) {
                    Image(systemName: actionSymbol(snap.state))
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(Color(hex: 0x121215))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(c))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(looper.nextActionLabel).font(.system(size: 18, weight: .bold))
                        Text("hold 2 s: undo / clear  ·  double-press: stop")
                            .font(.system(size: 11.5))
                            .foregroundColor(UI.text2)
                    }
                    Spacer(minLength: 8)
                    Text("R")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(UI.line2, lineWidth: 1))
                }
                .padding(.horizontal, 18)
                .frame(width: 400, height: 66)
                .background(RoundedRectangle(cornerRadius: 16).fill(UI.tint(snap.state == .empty ? .recording : snap.state)))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(c, lineWidth: 1.5))
                .shadow(color: c.opacity(live ? 0.3 : 0.12), radius: pressed ? 6 : 16)
                .scaleEffect(pressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.08), value: pressed)
            }
            .help("Record / overdub (R or Return)")

            Button { looper.playStop() } label: {
                HStack(spacing: 10) {
                    Image(systemName: playStopSymbol(snap))
                        .font(.system(size: 13, weight: .bold))
                    Text(looper.playStopLabel).font(.system(size: 14, weight: .semibold))
                    Text("Space").font(.system(size: 11)).foregroundColor(UI.muted)
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 12).fill(UI.well))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(UI.line2, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Play / stop (Space)")
            Button { looper.clear() } label: {
                SecondaryLabel(title: "Clear", hint: "⌘⌫", pressed: false, highlight: nil)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            BeatLights(count: snap.beatsPerMeasure, current: live ? snap.beat : 0, color: UI.state(snap.state))
        }
    }

    private func playStopSymbol(_ s: Snapshot) -> String {
        switch s.state {
        case .playing, .overdubbing: return "stop.fill"
        case .empty: return s.rhythmRunning ? "stop.fill" : "play.fill"
        case .armed, .autoRecArmed: return "xmark"
        default: return "play.fill"
        }
    }

    private func actionSymbol(_ s: LoopState) -> String {
        switch s {
        case .empty: return "circle.fill"
        case .armed, .autoRecArmed: return "xmark"
        case .recording: return "arrow.triangle.2.circlepath"
        case .playing: return looper.settings.oneShot ? "arrow.counterclockwise" : "plus"
        case .overdubbing, .stopped: return "play.fill"
        }
    }
}

private struct SecondaryLabel: View {
    let title: String
    let hint: String
    let pressed: Bool
    let highlight: Color?

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(hint).font(.system(size: 11)).foregroundColor(UI.muted)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(RoundedRectangle(cornerRadius: 12).fill(highlight.map { $0.opacity(0.15) } ?? UI.well))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(highlight ?? UI.line2, lineWidth: 1))
        .scaleEffect(pressed ? 0.97 : 1)
        .contentShape(Rectangle())
    }
}

private struct BeatLights: View {
    let count: Int
    let current: Int
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<max(1, min(count, 12)), id: \.self) { i in
                let on = i + 1 == current
                let col = i == 0 ? Color(hex: 0xFF453A) : color
                Circle()
                    .fill(on ? col : UI.track)
                    .frame(width: 14, height: 14)
                    .shadow(color: on ? col : .clear, radius: 7)
            }
        }
        .accessibilityLabel("Beat \(current) of \(count)")
    }
}

// MARK: - Rhythm panel

private struct RhythmPanel: View {
    @EnvironmentObject var looper: LooperController

    private static let drumNames = ["Kick", "Snare", "Hi-hat", "Open hat", "Ride", "Crash", "Tom hi", "Tom lo", "Rim", "Clap", "Shaker"]

    var body: some View {
        let s = looper.settings
        let pattern = RhythmLibrary.pattern(s.rhythmPattern)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Toggle("", isOn: $looper.settings.rhythmOn).toggleStyle(.switch).labelsHidden().controlSize(.small)
                Text("Rhythm").font(.system(size: 14, weight: .bold))
                if looper.snapshot.state == .empty && s.rhythmOn {
                    Button { looper.playStop() } label: {
                        Label(looper.snapshot.rhythmRunning ? "Stop" : "Play", systemImage: looper.snapshot.rhythmRunning ? "stop.fill" : "play.fill")
                            .frame(minWidth: 54)
                    }
                    .buttonStyle(PillButtonStyle())
                    .fixedSize()
                    .layoutPriority(2)
                    .help("Play or stop the rhythm on its own (Space)")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(RhythmLibrary.categories, id: \.self) { cat in
                            let selected = pattern.category == cat
                            Button(cat) {
                                if let i = RhythmLibrary.indices(in: cat).first { looper.selectPattern(i) }
                            }
                            .buttonStyle(ChipButtonStyle(selected: selected))
                            .fixedSize()
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            HStack(spacing: 10) {
                Menu {
                    ForEach(RhythmLibrary.categories, id: \.self) { cat in
                        Menu(cat) {
                            ForEach(RhythmLibrary.indices(in: cat), id: \.self) { i in
                                let pd = RhythmLibrary.pattern(i)
                                Button((i == s.rhythmPattern ? "✓ " : "") + "\(pd.name)  ·  \(pd.signature)") { looper.selectPattern(i) }
                            }
                        }
                    }
                    Divider()
                    Button("Save as New Pattern") { looper.forkPattern() }
                    if looper.currentIsUserPattern {
                        Button("Rename Pattern…") { looper.renamingPattern = s.rhythmPattern }
                        Button("Clear Variation \(s.rhythmVariation == 0 ? "A" : "B")") { looper.clearPatternVariation() }
                        Button("Delete Pattern") { looper.deleteUserPattern(s.rhythmPattern) }
                    }
                } label: {
                    Text("\(pattern.name) · \(pattern.signature)")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Menu {
                    ForEach(0..<RhythmLibrary.kitNames.count, id: \.self) { k in
                        Button(RhythmLibrary.kitNames[k]) { looper.settings.rhythmKit = k }
                    }
                } label: {
                    Text("\(RhythmLibrary.kitNames[max(0, min(RhythmLibrary.kitNames.count - 1, s.rhythmKit))]) kit")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Picker("", selection: $looper.settings.rhythmVariation) {
                    Text("A").tag(0)
                    Text("B").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 90)
                Spacer(minLength: 8)
                ToggleChip(title: "Edit", isOn: $looper.editingPattern)
                    .help("Edit the pattern: click steps to cycle accent → normal → ghost → off. Built-in patterns are copied to your User patterns first.")
                ToggleChip(title: "Intro", isOn: $looper.settings.rhythmIntro)
                ToggleChip(title: "Ending", isOn: $looper.settings.rhythmEnding)
                ToggleChip(title: "Count-in", isOn: $looper.settings.countIn)
            }
            HStack(spacing: 18) {
                HStack(spacing: 6) {
                    Text("Feel").font(.system(size: 11)).foregroundColor(UI.muted)
                    Slider(value: $looper.settings.rhythmHumanize, in: 0...1).frame(width: 80)
                        .help("Humanize: 0 = rigid drum machine, right = a drummer's natural timing and dynamics")
                }
                HStack(spacing: 6) {
                    Text("Room").font(.system(size: 11)).foregroundColor(UI.muted)
                    Slider(value: $looper.settings.rhythmReverb, in: 0...1).frame(width: 70)
                }
                HStack(spacing: 6) {
                    Text("Level").font(.system(size: 11)).foregroundColor(UI.muted)
                    Slider(value: $looper.settings.rhythmLevel, in: 0...2).frame(width: 90)
                }
                Spacer(minLength: 0)
            }
            if looper.editingPattern {
                Text(looper.currentIsUserPattern
                     ? "Editing \(pattern.name), variation \(s.rhythmVariation == 0 ? "A" : "B"): click a step to cycle accent → normal → ghost → off."
                     : "Click a step to start editing: \(pattern.name) is copied to your User patterns first.")
                    .font(.system(size: 11))
                    .foregroundColor(UI.muted)
            }
            StepGrid(pattern: s.rhythmPattern, variation: s.rhythmVariation, on: s.rhythmOn,
                     step: looper.snapshot.rhythmStep, names: Self.drumNames, core: looper.core,
                     editing: looper.editingPattern, version: looper.patternsVersion) { d, i in looper.toggleCell(drum: d, step: i) }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(UI.panel))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(UI.line, lineWidth: 1))
    }
}

private struct StepGrid: View {
    let pattern: Int
    let variation: Int
    let on: Bool
    let step: Int
    let names: [String]
    let core: LoopCore
    var editing = false
    var version = 0
    var onTap: (Int, Int) -> Void = { _, _ in }

    var body: some View {
        let p = RhythmLibrary.pattern(pattern)
        let steps = max(1, min(kMaxSteps, p.steps))
        let spb = max(1, Int((Double(steps) / max(0.5, p.beats)).rounded()))
        let rows = editing ? Array(0..<kInstrumentCount) : (0..<kInstrumentCount).filter { d in
            (0..<steps).contains { core.rhythm.cell(pattern: pattern, variation: 0, drum: d, step: $0) > 0 ||
                core.rhythm.cell(pattern: pattern, variation: 1, drum: d, step: $0) > 0 }
        }
        VStack(spacing: 4) {
            ForEach(rows, id: \.self) { d in
                HStack(spacing: 4) {
                    Text(names[d])
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(UI.text2)
                        .frame(width: 64, alignment: .leading)
                    ForEach(0..<steps, id: \.self) { i in
                        cell(d: d, i: i, spb: spb)
                            .contentShape(Rectangle())
                            .onTapGesture { if editing { onTap(d, i) } }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(d: Int, i: Int, spb: Int) -> some View {
        let v = core.rhythm.cell(pattern: pattern, variation: variation, drum: d, step: i)
        let hit = v > 0
        let current = on && i == step
        let base: Color = hit
            ? (on ? (v >= 0.9 ? UI.rhythm : (v >= 0.5 ? UI.rhythm.opacity(0.65) : UI.rhythm.opacity(0.38))) : UI.track)
            : (i % spb == 0 ? UI.well : UI.wellAlt)
        RoundedRectangle(cornerRadius: 5)
            .fill(current && hit ? Color.white : base)
            .frame(height: 22)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(current ? (hit ? Color.white : UI.dim) : (editing ? UI.line2 : Color.clear), lineWidth: current ? 2 : 1))
            .shadow(color: current && hit ? UI.base : .clear, radius: 6)
    }
}

// MARK: - Footer

private struct StudioFooter: View {
    @EnvironmentObject var looper: LooperController

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "cable.connector")
            Text(looper.deviceSummary.isEmpty ? "No audio device" : looper.deviceSummary).lineLimit(1)
            Text("\(Int(looper.core.sampleRate / 1000)) kHz · \(looper.actualBufferFrames) samples · comp. \(String(format: "%.1f", max(0, looper.latencyMs))) ms")
            Spacer()
            if looper.syncExternal {
                Label(looper.externalClockTempo != nil ? "MIDI clock in" : "No MIDI clock", systemImage: "dot.radiowaves.left.and.right")
            } else if looper.midiClockOut {
                Label("MIDI clock out", systemImage: "dot.radiowaves.left.and.right")
            }
        }
        .font(.system(size: 11))
        .foregroundColor(UI.muted)
        .padding(.horizontal, 16)
        .frame(height: 30)
        .background(UI.panel)
        .overlay(alignment: .top) { Rectangle().fill(UI.line).frame(height: 1) }
    }
}

// MARK: - Small controls

private struct IconButton: View {
    let symbol: String
    let help: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(active ? UI.text : UI.muted)
                .frame(width: 30, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(active ? UI.control : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct TransportButton: View {
    let symbol: String
    let color: Color
    let active: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(active || symbol != "play.fill" ? color : UI.text2)
                .frame(width: 40, height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(active ? color.opacity(0.16) : UI.control))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(active ? color : UI.line2, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Toolbar menu for the fixed loop length ("Length: None / 4 bars").
private struct LoopLengthMenu: View {
    @EnvironmentObject var looper: LooperController

    var body: some View {
        let bars = looper.settings.loopLength
        let on = bars > 0
        Menu {
            ForEach(LoopLengthOptions.bars, id: \.self) { b in
                Button {
                    looper.settings.loopLength = b
                } label: {
                    if b == bars { Label(LoopLengthOptions.label(b), systemImage: "checkmark") } else { Text(LoopLengthOptions.label(b)) }
                }
                if b == 0 { Divider() }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "ruler")
                Text(on ? LoopLengthOptions.label(bars) : "Length")
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(on ? (UI.light ? UI.rhythm : .white) : UI.text2)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(on ? UI.rhythm.opacity(0.28) : UI.control))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? UI.rhythm : UI.line2, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Loop length: recording stops by itself after this many bars (None = close the loop yourself)")
    }
}

private struct PillToggle: View {
    let title: String
    let symbol: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(isOn ? (UI.light ? UI.rhythm : .white) : UI.text2)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(isOn ? UI.rhythm.opacity(0.28) : UI.control))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isOn ? UI.rhythm : UI.line2, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct ToggleChip: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isOn ? UI.text : UI.text2)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(isOn ? UI.rhythm.opacity(0.22) : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(isOn ? UI.rhythm : UI.line2, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct ChipButtonStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: selected ? .semibold : .regular))
            .foregroundColor(selected ? .white : UI.text2)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(Capsule().fill(selected ? UI.rhythm : Color.clear))
            .overlay(Capsule().stroke(selected ? Color.clear : UI.line2, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

struct PillButtonStyle: ButtonStyle {
    var full = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundColor(UI.text)
            .padding(.horizontal, 12)
            .frame(maxWidth: full ? .infinity : nil)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(configuration.isPressed ? UI.controlHi : UI.control))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.line2, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

// MARK: - Rename

private struct RenameTarget: Identifiable { let id: Int }

private struct RenameSheet: View {
    @EnvironmentObject var looper: LooperController
    @Environment(\.dismiss) private var dismiss
    let slot: Int
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename memory \(String(format: "%02d", slot + 1))").font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit { commit() }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Rename") { commit() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .onAppear { name = looper.memoryInfo.first { $0.id == slot }?.name ?? "" }
    }

    private func commit() {
        looper.renameMemory(slot, to: name)
        dismiss()
    }
}

private struct PatternRenameSheet: View {
    @EnvironmentObject var looper: LooperController
    @Environment(\.dismiss) private var dismiss
    let index: Int
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename pattern").font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit { commit() }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Rename") { commit() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .onAppear { name = RhythmLibrary.pattern(index).name }
    }

    private func commit() {
        looper.renameUserPattern(index, to: name)
        dismiss()
    }
}

// MARK: - Settings window

struct SettingsView: View {
    @EnvironmentObject var looper: LooperController

    var body: some View {
        TabView(selection: $looper.selectedTab) {
            SetupView().tabItem { Label("Loop", systemImage: "repeat") }.tag(SideTab.setup)
            AudioSetupView().tabItem { Label("Audio", systemImage: "hifispeaker") }.tag(SideTab.audio)
            RhythmView().tabItem { Label("Rhythm", systemImage: "metronome") }.tag(SideTab.rhythm)
            MemoryView().tabItem { Label("Memories", systemImage: "square.stack.3d.up") }.tag(SideTab.memory)
            HelpView().tabItem { Label("Help", systemImage: "questionmark.circle") }.tag(SideTab.help)
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 600, idealHeight: 700)
    }
}
