import SwiftUI

// MARK: - Themes

enum ThemeID: String, CaseIterable, Identifiable {
    case midnight, crimson, arctic
    var id: String { rawValue }
    var label: String {
        switch self {
        case .midnight: return "Midnight"
        case .crimson: return "Crimson"
        case .arctic: return "Arctic"
        }
    }
}

struct Theme {
    let chassisTop: Color
    let chassisBottom: Color
    let edge: Color
    let accent: Color
    let ink: Color          // text on the chassis
    let subInk: Color
    let glass: Color        // display background
    let key: Color          // rubber key colour
    let metalLight: Color
    let metalDark: Color

    static func of(_ id: ThemeID) -> Theme {
        switch id {
        case .midnight:
            return Theme(chassisTop: Color(red: 0.13, green: 0.14, blue: 0.17),
                         chassisBottom: Color(red: 0.05, green: 0.05, blue: 0.07),
                         edge: Color.white.opacity(0.08),
                         accent: Color(red: 0.32, green: 0.82, blue: 1.0),
                         ink: .white, subInk: .white.opacity(0.55),
                         glass: Color(red: 0.03, green: 0.04, blue: 0.06),
                         key: Color(red: 0.16, green: 0.17, blue: 0.20),
                         metalLight: Color(white: 0.62), metalDark: Color(white: 0.24))
        case .crimson:
            return Theme(chassisTop: Color(red: 0.78, green: 0.07, blue: 0.10),
                         chassisBottom: Color(red: 0.38, green: 0.02, blue: 0.04),
                         edge: Color.white.opacity(0.15),
                         accent: Color(red: 1.0, green: 0.86, blue: 0.55),
                         ink: .white, subInk: .white.opacity(0.65),
                         glass: Color(red: 0.06, green: 0.02, blue: 0.03),
                         key: Color(red: 0.12, green: 0.10, blue: 0.10),
                         metalLight: Color(white: 0.80), metalDark: Color(white: 0.40))
        case .arctic:
            return Theme(chassisTop: Color(red: 0.86, green: 0.89, blue: 0.93),
                         chassisBottom: Color(red: 0.62, green: 0.67, blue: 0.74),
                         edge: Color.white.opacity(0.6),
                         accent: Color(red: 0.10, green: 0.45, blue: 1.0),
                         ink: Color(red: 0.08, green: 0.10, blue: 0.14), subInk: Color(red: 0.08, green: 0.10, blue: 0.14).opacity(0.55),
                         glass: Color(red: 0.05, green: 0.07, blue: 0.10),
                         key: Color(red: 0.93, green: 0.95, blue: 0.97),
                         metalLight: Color(white: 0.95), metalDark: Color(white: 0.55))
        }
    }
}

/// Colours that mean the same thing in every theme.
enum StateColor {
    static let rec = Color(red: 1.0, green: 0.23, blue: 0.29)
    static let dub = Color(red: 1.0, green: 0.69, blue: 0.13)
    static let play = Color(red: 0.18, green: 0.88, blue: 0.48)
    static let stop = Color(red: 0.44, green: 0.72, blue: 1.0)

    static func of(_ state: LoopState, accent: Color) -> Color {
        switch state {
        case .recording, .armed, .autoRecArmed: return rec
        case .overdubbing: return dub
        case .playing: return play
        case .stopped: return stop
        case .empty: return accent
        }
    }
}

// MARK: - Knob

/// Machined rotary knob with a glowing value arc: drag up/down, double-click to reset.
struct Knob: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var label: String
    var defaultValue: Double
    var size: CGFloat = 56
    var accent: Color = .cyan
    var ink: Color = .white
    @State private var dragStart: Double?

    private var fraction: Double { (value - range.lowerBound) / (range.upperBound - range.lowerBound) }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                // tick ring
                ForEach(0..<11, id: \.self) { i in
                    Capsule()
                        .fill(ink.opacity(Double(i) / 10 <= fraction ? 0.8 : 0.2))
                        .frame(width: 1.5, height: 5)
                        .offset(y: -size / 2 - 9)
                        .rotationEffect(.degrees(-135 + 27 * Double(i)))
                }
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.black.opacity(0.35), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .frame(width: size + 6, height: size + 6)
                Circle()
                    .trim(from: 0, to: 0.75 * fraction)
                    .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .frame(width: size + 6, height: size + 6)
                    .shadow(color: accent.opacity(0.8), radius: 4)
                Circle()
                    .fill(AngularGradient(colors: [Color(white: 0.32), Color(white: 0.12), Color(white: 0.28), Color(white: 0.10), Color(white: 0.32)], center: .center))
                    .frame(width: size - 4, height: size - 4)
                    .shadow(color: .black.opacity(0.7), radius: 5, y: 4)
                Circle()
                    .fill(RadialGradient(colors: [Color(white: 0.30), Color(white: 0.14)], center: .topLeading, startRadius: 1, endRadius: size * 0.6))
                    .frame(width: size * 0.62, height: size * 0.62)
                Capsule()
                    .fill(Color.white)
                    .frame(width: 3, height: size * 0.2)
                    .offset(y: -size * 0.3)
                    .rotationEffect(.degrees(-135 + 270 * fraction))
                    .shadow(color: .white.opacity(0.6), radius: 2)
            }
            .frame(width: size + 24, height: size + 24)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if dragStart == nil { dragStart = value }
                        let span = range.upperBound - range.lowerBound
                        let v = (dragStart ?? value) - Double(g.translation.height) / 160.0 * span
                        value = min(range.upperBound, max(range.lowerBound, v))
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { value = defaultValue })
            .help("\(label): drag up/down, double-click to reset")
            Text(label)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundColor(ink.opacity(0.85))
            Text("\(Int((value * 100).rounded()))")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(accent)
        }
    }
}

// MARK: - Rubber key with LED

struct KeyButton: View {
    var title: String
    var symbol: String
    var led: Color? = nil
    var theme: Theme
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        VStack(spacing: 6) {
            Circle()
                .fill(led ?? Color.black.opacity(0.35))
                .frame(width: 6, height: 6)
                .shadow(color: led ?? .clear, radius: led == nil ? 0 : 5)
                .overlay(Circle().stroke(Color.black.opacity(0.3), lineWidth: 0.5))
            Button(action: action) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: [theme.key.opacity(1), theme.key.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(LinearGradient(colors: [Color.white.opacity(0.25), Color.black.opacity(0.4)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(led ?? theme.ink.opacity(0.85))
                }
                .frame(width: 46, height: 32)
                .shadow(color: .black.opacity(0.45), radius: hover ? 6 : 3, y: hover ? 4 : 2)
                .scaleEffect(hover ? 1.04 : 1)
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.12), value: hover)
            Text(title)
                .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                .tracking(1)
                .foregroundColor(theme.ink.opacity(0.85))
                .fixedSize()
        }
    }
}

/// Momentary switch that reports press and release separately (for long-press / double-press logic).
struct MomentarySwitch<Label: View>: View {
    var onDown: () -> Void
    var onUp: () -> Void
    @ViewBuilder var label: (Bool) -> Label
    @State private var pressed = false

    var body: some View {
        label(pressed)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !pressed {
                            pressed = true
                            onDown()
                        }
                    }
                    .onEnded { _ in
                        pressed = false
                        onUp()
                    }
            )
    }
}

// MARK: - Meters

/// Horizontal gradient meter (used in forms).
struct LevelMeter: View {
    var level: Float
    var body: some View {
        GeometryReader { geo in
            let f = meterFraction(level)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.25))
                Capsule()
                    .fill(LinearGradient(colors: [.green, .yellow, .red], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * f)
            }
        }
        .frame(height: 5)
    }
}

func meterFraction(_ level: Float) -> Double {
    let db = 20 * log10(max(0.00001, Double(level)))
    return max(0, min(1, (db + 60) / 60))
}

/// Vertical segmented LED meter.
struct SegmentMeter: View {
    var level: Float
    var label: String
    var ink: Color
    private let segments = 14

    var body: some View {
        let lit = Int((meterFraction(level) * Double(segments)).rounded())
        VStack(spacing: 4) {
            VStack(spacing: 2) {
                ForEach((0..<segments).reversed(), id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color(i).opacity(i < lit ? 1 : 0.13))
                        .frame(width: 9, height: 3)
                        .shadow(color: i < lit ? color(i).opacity(0.8) : .clear, radius: 2)
                }
            }
            Text(label)
                .font(.system(size: 7.5, weight: .heavy, design: .rounded))
                .foregroundColor(ink.opacity(0.7))
        }
    }

    private func color(_ i: Int) -> Color {
        if i >= segments - 2 { return StateColor.rec }
        if i >= segments - 5 { return StateColor.dub }
        return StateColor.play
    }
}

// MARK: - Loop visualisers

/// Linear waveform strip with a glowing playhead.
struct WaveformView: View {
    var samples: [Float]
    var position: Double
    var showHead: Bool
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            let n = samples.count
            let mid = size.height / 2
            guard n > 0 else {
                ctx.fill(Path(CGRect(x: 0, y: mid - 0.5, width: size.width, height: 1)), with: .color(color.opacity(0.3)))
                return
            }
            let w = size.width / CGFloat(n)
            let headX = CGFloat(position) * size.width
            for (i, v) in samples.enumerated() {
                let x = CGFloat(i) * w
                let h = max(1, CGFloat(sqrt(Double(v))) * size.height)
                let played = !showHead || x <= headX
                ctx.fill(Path(roundedRect: CGRect(x: x, y: mid - h / 2, width: max(1, w - 0.8), height: h), cornerRadius: 0.8),
                         with: .color(color.opacity(played ? 0.95 : 0.32)))
            }
            if showHead {
                var g = ctx
                g.addFilter(.shadow(color: .white, radius: 4))
                g.fill(Path(CGRect(x: headX - 1, y: 0, width: 2, height: size.height)), with: .color(.white))
            }
        }
    }
}

/// Circular loop display: waveform radiating around a ring, glowing progress arc and bar ticks.
struct LoopRing: View {
    var samples: [Float]
    var position: Double
    var color: Color
    var recording: Bool
    var measures: Int
    var reverse: Bool
    var pulse: Double          // 0…1 beat phase, drives a subtle glow pulse

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = min(size.width, size.height) / 2 - 6
            let inner = outer * 0.58
            let barMax = outer - inner - 10

            // track
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2)),
                       with: .color(.white.opacity(0.07)), lineWidth: 5)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - inner, y: c.y - inner, width: inner * 2, height: inner * 2)),
                       with: .color(.white.opacity(0.06)), lineWidth: 1)

            // waveform bars
            let n = samples.count
            if n > 0 {
                for (i, v) in samples.enumerated() {
                    let f = Double(i) / Double(n)
                    let a = -Double.pi / 2 + 2 * Double.pi * (reverse ? 1 - f : f)
                    let len = max(1.5, CGFloat(sqrt(Double(v))) * barMax)
                    let p0 = CGPoint(x: c.x + CGFloat(cos(a)) * (inner + 4), y: c.y + CGFloat(sin(a)) * (inner + 4))
                    let p1 = CGPoint(x: c.x + CGFloat(cos(a)) * (inner + 4 + len), y: c.y + CGFloat(sin(a)) * (inner + 4 + len))
                    var path = Path()
                    path.move(to: p0)
                    path.addLine(to: p1)
                    let played = recording || f <= position
                    ctx.stroke(path, with: .color(color.opacity(played ? 0.9 : 0.28)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }

            // bar ticks
            if measures > 1 {
                for m in 0..<measures {
                    let a = -Double.pi / 2 + 2 * Double.pi * Double(m) / Double(measures)
                    var t = Path()
                    t.move(to: CGPoint(x: c.x + CGFloat(cos(a)) * (outer - 9), y: c.y + CGFloat(sin(a)) * (outer - 9)))
                    t.addLine(to: CGPoint(x: c.x + CGFloat(cos(a)) * (outer + 3), y: c.y + CGFloat(sin(a)) * (outer + 3)))
                    ctx.stroke(t, with: .color(.white.opacity(0.35)), lineWidth: 1.5)
                }
            }

            // progress arc
            let prog = recording ? 1.0 : position
            if prog > 0.001 {
                var arc = Path()
                let start = Angle.degrees(-90)
                let end = Angle.degrees(-90 + 360 * (reverse ? -prog : prog))
                arc.addArc(center: c, radius: outer, startAngle: start, endAngle: end, clockwise: reverse)
                var g = ctx
                g.addFilter(.shadow(color: color.opacity(0.4 + 0.5 * (1 - pulse)), radius: 6))
                g.stroke(arc, with: .color(color), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                if !recording {
                    let a = end.radians
                    let dot = CGPoint(x: c.x + CGFloat(cos(a)) * outer, y: c.y + CGFloat(sin(a)) * outer)
                    g.fill(Path(ellipseIn: CGRect(x: dot.x - 5, y: dot.y - 5, width: 10, height: 10)), with: .color(.white))
                }
            }
        }
    }
}

/// One LED per beat of the bar.
struct BeatDots: View {
    var count: Int
    var current: Int          // 1-based, 0 = none
    var color: Color

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(1, min(count, 12)), id: \.self) { i in
                let on = i + 1 == current
                Circle()
                    .fill(on ? (i == 0 ? StateColor.rec : color) : Color.white.opacity(0.12))
                    .frame(width: i == 0 ? 9 : 7, height: i == 0 ? 9 : 7)
                    .shadow(color: on ? (i == 0 ? StateColor.rec : color) : .clear, radius: 5)
            }
        }
    }
}

/// Diamond tread-plate texture for the pedal.
struct TreadPlate: View {
    var light: Color
    var dark: Color

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [light, dark]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            let step: CGFloat = 14
            var row = 0
            var y: CGFloat = 4
            while y < size.height {
                var x: CGFloat = (row % 2 == 0) ? 4 : 4 + step / 2
                while x < size.width {
                    var p = Path()
                    let flip = (row + Int(x / step)) % 2 == 0
                    if flip {
                        p.move(to: CGPoint(x: x, y: y + 4)); p.addLine(to: CGPoint(x: x + 7, y: y))
                    } else {
                        p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x + 7, y: y + 4))
                    }
                    ctx.stroke(p, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    var s = Path()
                    if flip {
                        s.move(to: CGPoint(x: x, y: y + 5.5)); s.addLine(to: CGPoint(x: x + 7, y: y + 1.5))
                    } else {
                        s.move(to: CGPoint(x: x, y: y + 1.5)); s.addLine(to: CGPoint(x: x + 7, y: y + 5.5))
                    }
                    ctx.stroke(s, with: .color(.black.opacity(0.25)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    x += step
                }
                y += 9
                row += 1
            }
        }
    }
}
