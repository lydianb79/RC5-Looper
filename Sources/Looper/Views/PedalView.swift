import SwiftUI

/// The hardware-style front panel: meters, display, knobs, keys, big pedal and footswitches.
struct PedalView: View {
    @EnvironmentObject var looper: LooperController

    var body: some View {
        let snap = looper.snapshot
        let theme = Theme.of(looper.themeID)
        let glow = StateColor.of(snap.state, accent: theme.accent)

        VStack(spacing: 16) {
            header(theme: theme, snap: snap)

            DisplayView()

            controls(theme: theme, snap: snap)

            Button { looper.selectedTab = .audio } label: {
                HStack(spacing: 6) {
                    Image(systemName: "cable.connector")
                    Text(looper.deviceSummary.isEmpty ? "Choose audio devices…" : looper.deviceSummary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundColor(theme.subInk)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.18)))
            }
            .buttonStyle(.plain)
            .help("Select input / output device and buffer size")

            pedal(theme: theme, snap: snap, glow: glow)

            HStack(spacing: 14) {
                footswitch("STOP", "Esc · hold = clear", symbol: "stop.fill", ring: StateColor.stop, theme: theme,
                           onDown: { looper.stopDown() }, onUp: { looper.stopUp() })
                footswitch(snap.canRedo ? "REDO" : "UNDO", "U", symbol: snap.canRedo ? "arrow.uturn.forward" : "arrow.uturn.backward",
                           ring: (snap.canUndo || snap.canRedo) ? StateColor.dub : nil, theme: theme,
                           onDown: { looper.undoRedo() }, onUp: {})
                footswitch("CLEAR", "Delete", symbol: "xmark", ring: nil, theme: theme,
                           onDown: { looper.clear() }, onUp: {})
            }
        }
        .padding(22)
        .background(chassis(theme: theme, glow: glow))
        .overlay(alignment: .top) {
            if let msg = looper.message {
                Text(msg)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .overlay(Capsule().stroke(glow.opacity(0.8), lineWidth: 1))
                    .shadow(color: glow.opacity(0.6), radius: 10)
                    .padding(.top, -14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: looper.message)
    }

    // MARK: Sections

    private func header(theme: Theme, snap: Snapshot) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LOOPER")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .tracking(5)
                    .foregroundColor(theme.ink)
                HStack(spacing: 6) {
                    Rectangle().fill(theme.accent).frame(width: 18, height: 2)
                    Text("PHRASE LOOP · 1 TRACK · STEREO")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .tracking(1.5)
                        .foregroundColor(theme.subInk)
                }
            }
            Spacer()
            Menu {
                ForEach(ThemeID.allCases) { t in
                    Button(t.label) { looper.themeID = t }
                }
            } label: {
                Image(systemName: "paintpalette.fill")
                    .foregroundColor(theme.subInk)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Theme")
            SegmentMeter(level: snap.inLevel, label: "IN", ink: theme.ink)
            SegmentMeter(level: snap.outLevel, label: "OUT", ink: theme.ink)
        }
    }

    private func controls(theme: Theme, snap: Snapshot) -> some View {
        let beatLit = (snap.rhythmRunning || snap.state == .playing || snap.state == .overdubbing) && snap.beatPhase < 0.18
        return HStack(alignment: .top, spacing: 6) {
            Knob(value: $looper.settings.loopLevel, range: 0...2, label: "LOOP", defaultValue: 1, size: 46,
                 accent: theme.accent, ink: theme.ink)
            Knob(value: $looper.settings.rhythmLevel, range: 0...2, label: "RHYTHM", defaultValue: 0.7, size: 46,
                 accent: theme.accent, ink: theme.ink)
            Spacer(minLength: 4)
            Grid(horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    KeyButton(title: "MEM −", symbol: "chevron.left", theme: theme) { looper.memoryDown() }
                    KeyButton(title: "MEM +", symbol: "chevron.right", theme: theme) { looper.memoryUp() }
                    KeyButton(title: "WRITE", symbol: "square.and.arrow.down", led: looper.dirty ? StateColor.dub : nil, theme: theme) { looper.writeMemory() }
                }
                GridRow {
                    KeyButton(title: "RHYTHM", symbol: "metronome", led: looper.settings.rhythmOn ? StateColor.play : nil, theme: theme) { looper.toggleRhythm() }
                    KeyButton(title: "TAP", symbol: "hand.tap",
                              led: beatLit ? (snap.beat == 1 ? StateColor.rec : StateColor.play) : nil, theme: theme) { looper.tapTempo() }
                    KeyButton(title: "SETUP", symbol: "slider.horizontal.3", theme: theme) { looper.selectedTab = .setup }
                }
            }
        }
    }

    private func pedal(theme: Theme, snap: Snapshot, glow: Color) -> some View {
        let active = snap.state == .recording || snap.state == .overdubbing || snap.state == .playing || snap.state == .armed
        return MomentarySwitch(onDown: { looper.pedalDown() }, onUp: { looper.pedalUp() }) { pressed in
            ZStack {
                TreadPlate(light: theme.metalLight, dark: theme.metalDark)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(glow.opacity(active ? 1 : 0.35), lineWidth: active ? 3 : 1.5)
                    .shadow(color: glow.opacity(active ? 0.9 : 0), radius: active ? 12 : 0)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.6), .black.opacity(0.4)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    .padding(3)
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: pedalIcon(snap.state))
                        Text(pedalAction(snap.state))
                    }
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: glow.opacity(0.9), radius: 8)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .overlay(Capsule().stroke(glow.opacity(0.8), lineWidth: 1))
                    Text("REC · PLAY · DUB   —   click or Space")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                        .foregroundColor(.black.opacity(0.65))
                    Text("×2 stop  ·  hold 2 s undo/redo · clear")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(.black.opacity(0.5))
                }
            }
            .frame(height: 140)
            .shadow(color: .black.opacity(0.6), radius: pressed ? 2 : 12, y: pressed ? 1 : 8)
            .scaleEffect(pressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.07), value: pressed)
        }
        .help("Space bar")
    }

    private func chassis(theme: Theme, glow: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(colors: [theme.chassisTop, theme.chassisBottom], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(RadialGradient(colors: [glow.opacity(0.14), .clear], center: .bottom, startRadius: 10, endRadius: 420))
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(theme.edge, lineWidth: 1)
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.black.opacity(0.35), lineWidth: 1)
                .padding(2)
            // screws
            GeometryReader { geo in
                ForEach(0..<4, id: \.self) { i in
                    Screw()
                        .position(x: i % 2 == 0 ? 12 : geo.size.width - 12, y: i < 2 ? 12 : geo.size.height - 12)
                }
            }
        }
        .shadow(color: .black.opacity(0.55), radius: 22, y: 12)
        .animation(.easeInOut(duration: 0.3), value: looper.snapshot.state)
    }

    // MARK: Pieces

    private func footswitch(_ title: String, _ hint: String, symbol: String, ring: Color?, theme: Theme,
                            onDown: @escaping () -> Void, onUp: @escaping () -> Void) -> some View {
        MomentarySwitch(onDown: onDown, onUp: onUp) { pressed in
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .stroke(ring ?? Color.black.opacity(0.3), lineWidth: 2)
                        .shadow(color: ring ?? .clear, radius: ring == nil ? 0 : 6)
                        .frame(width: 48, height: 48)
                    Circle()
                        .fill(AngularGradient(colors: [Color(white: 0.9), Color(white: 0.5), Color(white: 0.85), Color(white: 0.45), Color(white: 0.9)], center: .center))
                        .frame(width: 40, height: 40)
                        .shadow(color: .black.opacity(0.55), radius: pressed ? 1 : 4, y: pressed ? 1 : 3)
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black.opacity(0.6))
                }
                .scaleEffect(pressed ? 0.93 : 1)
                Text(title)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundColor(theme.ink)
                Text(hint)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundColor(theme.subInk)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// What pressing the pedal will do next.
    private func pedalAction(_ st: LoopState) -> String {
        switch st {
        case .empty: return "REC"
        case .armed, .autoRecArmed: return "CANCEL"
        case .recording: return looper.settings.recAction == .recDubPlay && !looper.settings.oneShot ? "DUB" : "PLAY"
        case .playing: return looper.settings.oneShot ? "RESTART" : "DUB"
        case .overdubbing: return "PLAY"
        case .stopped: return "PLAY"
        }
    }

    private func pedalIcon(_ st: LoopState) -> String {
        switch st {
        case .empty: return "record.circle"
        case .armed, .autoRecArmed: return "xmark.circle"
        case .recording, .overdubbing: return pedalAction(st) == "DUB" ? "plus.circle" : "play.circle"
        case .playing: return looper.settings.oneShot ? "arrow.counterclockwise.circle" : "plus.circle"
        case .stopped: return "play.circle"
        }
    }
}

private struct Screw: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.75), Color(white: 0.3)], center: .topLeading, startRadius: 0, endRadius: 7))
            Rectangle()
                .fill(Color.black.opacity(0.45))
                .frame(width: 6, height: 1.2)
                .rotationEffect(.degrees(35))
        }
        .frame(width: 8, height: 8)
        .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
    }
}

/// The glass display with the circular loop visualiser.
struct DisplayView: View {
    @EnvironmentObject var looper: LooperController

    var body: some View {
        let snap = looper.snapshot
        let theme = Theme.of(looper.themeID)
        let blink = Int(Date().timeIntervalSinceReferenceDate * 4) % 2 == 0
        let glow = StateColor.of(snap.state, accent: theme.accent)
        let stateColor = (snap.state == .armed || snap.state == .autoRecArmed) && !blink ? glow.opacity(0.35) : glow
        let pattern = RhythmLibrary.pattern(looper.settings.rhythmPattern)
        let running = snap.rhythmRunning || snap.state == .playing || snap.state == .overdubbing || snap.state == .recording

        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    LoopRing(samples: looper.waveform,
                             position: snap.position,
                             color: glow,
                             recording: snap.state == .recording,
                             measures: snap.totalMeasures,
                             reverse: looper.settings.reverse,
                             pulse: running ? snap.beatPhase : 1)
                    VStack(spacing: 2) {
                        Text(stateText(snap))
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundColor(stateColor)
                            .shadow(color: glow.opacity(0.8), radius: 8)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text(timeText(snap))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                        if snap.state == .armed && snap.countdownBeats > 0 {
                            Text("\(snap.countdownBeats)")
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundColor(StateColor.rec)
                        }
                    }
                    .frame(width: 104)
                }
                .frame(width: 186, height: 186)

                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        Text(String(format: "%02d", looper.memoryIndex + 1))
                            .font(.system(size: 15, weight: .black, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(theme.accent))
                        Text(looper.settings.name)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        if looper.dirty {
                            Circle().fill(StateColor.dub).frame(width: 6, height: 6).shadow(color: StateColor.dub, radius: 3)
                        }
                    }

                    Text(detailText(snap))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundColor(glow.opacity(0.9))

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("♩").font(.system(size: 18, weight: .bold)).foregroundColor(.white.opacity(0.6))
                        Text(String(format: "%.1f", snap.tempo))
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(pattern.signature)
                            if abs(snap.playbackRate - 1) > 0.001 {
                                Text("\(Int((snap.playbackRate * 100).rounded()))%").foregroundColor(StateColor.dub)
                            }
                        }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                    }

                    HStack(spacing: 14) {
                        stat("BAR", "\(snap.measure)\(snap.totalMeasures > 0 ? "/\(snap.totalMeasures)" : "")")
                        stat("BEAT", "\(snap.beat)/\(snap.beatsPerMeasure)")
                    }

                    HStack(spacing: 5) {
                        Image(systemName: "metronome.fill")
                            .foregroundColor(looper.settings.rhythmOn ? StateColor.play : .white.opacity(0.3))
                        Text(rhythmLine(pattern))
                            .lineLimit(1)
                            .foregroundColor(.white.opacity(looper.settings.rhythmOn ? 0.85 : 0.4))
                    }
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))

                    HStack(spacing: 4) {
                        if looper.settings.reverse { tag("REV", theme.accent) }
                        if looper.settings.oneShot { tag("1SHOT", theme.accent) }
                        if looper.settings.dubMode == .replace { tag("RPL", StateColor.dub) }
                        if looper.settings.quantize && looper.settings.rhythmOn { tag("QTZ", theme.accent) }
                        if looper.syncExternal { tag(looper.externalClockTempo != nil ? "EXT" : "EXT?", looper.externalClockTempo != nil ? StateColor.play : StateColor.rec) }
                        if snap.canUndo { tag("UNDO", StateColor.dub) }
                        if snap.canRedo { tag("REDO", StateColor.dub) }
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                BeatDots(count: snap.beatsPerMeasure, current: running ? snap.beat : 0, color: glow)
                WaveformView(samples: looper.waveform, position: snap.position,
                             showHead: snap.state == .playing || snap.state == .overdubbing, color: glow)
                    .frame(height: 26)
            }
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.glass)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(RadialGradient(colors: [glow.opacity(0.22), .clear], center: .init(x: 0.22, y: 0.45), startRadius: 4, endRadius: 260))
                // glass reflection
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.07), .clear], startPoint: .top, endPoint: .center))
            }
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.black.opacity(0.8), lineWidth: 3))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(glow.opacity(0.35), lineWidth: 1).padding(1.5))
        .animation(.easeInOut(duration: 0.25), value: snap.state)
    }

    private func rhythmLine(_ pattern: PatternDef) -> String {
        guard looper.settings.rhythmOn else { return "Rhythm off" }
        let kits = RhythmLibrary.kitNames
        let kit = kits[max(0, min(kits.count - 1, looper.settings.rhythmKit))]
        let variation = looper.settings.rhythmVariation == 0 ? "A" : "B"
        return "\(pattern.name) \(variation) · \(kit)"
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .tracking(1)
                .foregroundColor(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
        }
    }

    private func tag(_ s: String, _ c: Color) -> some View {
        Text(s)
            .font(.system(size: 8.5, weight: .heavy, design: .rounded))
            .foregroundColor(c)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .overlay(Capsule().stroke(c.opacity(0.7), lineWidth: 1))
    }

    private func stateText(_ s: Snapshot) -> String {
        if s.state == .recording && s.waitingQuantize { return "REC…" }
        if s.stopping { return looper.settings.rhythmEnding && looper.settings.rhythmOn ? "ENDING" : "STOP…" }
        if s.state == .empty && looper.settings.autoRec { return "READY" }
        return s.state.label
    }

    private func detailText(_ s: Snapshot) -> String {
        switch s.state {
        case .armed: return s.countdownBeats > 0 ? "COUNT IN" : "WAIT FOR BAR"
        case .autoRecArmed: return "PLAY TO START REC"
        case .recording: return s.waitingQuantize ? "QUANTIZING TO BAR" : "PRESS TO \(looper.settings.recAction == .recDubPlay ? "DUB" : "PLAY")"
        case .playing: return looper.settings.oneShot ? "ONE SHOT" : "PRESS TO DUB"
        case .overdubbing: return looper.settings.dubMode == .replace ? "REPLACING" : "OVERDUBBING"
        case .stopped: return "PRESS TO PLAY"
        case .empty: return looper.settings.autoRec ? "AUTO REC ON" : "PEDAL / SPACE = REC"
        }
    }

    private func timeText(_ s: Snapshot) -> String {
        let t = s.state == .recording ? s.recordSeconds : s.position * s.loopSeconds
        let total = s.state == .recording ? s.recordSeconds : s.loopSeconds
        func fmt(_ x: Double) -> String { String(format: "%d:%04.1f", Int(x) / 60, x.truncatingRemainder(dividingBy: 60)) }
        return s.state == .empty ? "0:00.0" : "\(fmt(t)) / \(fmt(total))"
    }
}
