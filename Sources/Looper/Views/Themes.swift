import SwiftUI

/// Window themes. Each one changes the background artwork, every surface colour
/// (panels, header, display, controls, grid), the text colours and the accent.
enum AppTheme: String, CaseIterable, Identifiable {
    case graphite, midnight, synthwave, aurora, ember, ocean, forest, daylight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .graphite: return "Graphite"
        case .midnight: return "Midnight"
        case .synthwave: return "Synthwave"
        case .aurora: return "Aurora"
        case .ember: return "Ember"
        case .ocean: return "Ocean"
        case .forest: return "Forest"
        case .daylight: return "Daylight"
        }
    }

    /// Background artwork.
    enum Art { case dots, stars, synthGrid, aurora, embers, waves, hills, paper }

    struct Palette {
        let art: Art
        let light: Bool
        let bgTop: Color
        let bgMid: Color
        let bgBottom: Color
        let glowA: Color
        let glowB: Color
        let artColor: Color      // main colour of the artwork
        let artColor2: Color
        let panel: Color
        let header: Color
        let lcd: Color
        let control: Color
        let controlHi: Color
        let well: Color          // inset areas (lanes, step cells, ring track)
        let wellAlt: Color
        let track: Color         // inactive marks
        let dim: Color
        let line: Color
        let line2: Color
        let text: Color
        let text2: Color
        let muted: Color
        let accent: Color
        let selection: Color
        let base: Color          // loop waveform
    }

    var palette: Palette {
        switch self {
        case .graphite:
            return Palette(art: .dots, light: false,
                           bgTop: Color(hex: 0x1A1A1F), bgMid: Color(hex: 0x111114), bgBottom: Color(hex: 0x09090B),
                           glowA: Color(hex: 0x4A4A5A, opacity: 0.30), glowB: Color(hex: 0x2A2A34, opacity: 0.4),
                           artColor: .white.opacity(0.05), artColor2: .white.opacity(0.02),
                           panel: Color(hex: 0x18181C, opacity: 0.92), header: Color(hex: 0x1C1C21, opacity: 0.96),
                           lcd: Color(hex: 0x0A0A0C), control: Color(hex: 0x26262C), controlHi: Color(hex: 0x30303A),
                           well: Color(hex: 0x202026), wellAlt: Color(hex: 0x1B1B20), track: Color(hex: 0x34343D), dim: Color(hex: 0x5A5A66),
                           line: Color(hex: 0x2A2A31), line2: Color(hex: 0x33333B),
                           text: Color(hex: 0xF4F4F7), text2: Color(hex: 0xC2C2CC), muted: Color(hex: 0x8A8A95),
                           accent: Color(hex: 0x5E7BFF), selection: Color(hex: 0x2A3A8F), base: Color(hex: 0x8EA2FF))
        case .midnight:
            return Palette(art: .stars, light: false,
                           bgTop: Color(hex: 0x0B1A4A), bgMid: Color(hex: 0x060D29), bgBottom: Color(hex: 0x020410),
                           glowA: Color(hex: 0x2B5BFF, opacity: 0.45), glowB: Color(hex: 0x00C2FF, opacity: 0.28),
                           artColor: Color(hex: 0xCFE3FF), artColor2: Color(hex: 0x7FB2FF),
                           panel: Color(hex: 0x0B1638, opacity: 0.72), header: Color(hex: 0x0A1433, opacity: 0.88),
                           lcd: Color(hex: 0x030820), control: Color(hex: 0x14234F), controlHi: Color(hex: 0x1C2F66),
                           well: Color(hex: 0x0E1B42), wellAlt: Color(hex: 0x0B1536), track: Color(hex: 0x24386E), dim: Color(hex: 0x4F6699),
                           line: Color(hex: 0x1D2D5E), line2: Color(hex: 0x2A3F7A),
                           text: Color(hex: 0xEAF2FF), text2: Color(hex: 0xB3C6EE), muted: Color(hex: 0x7489B8),
                           accent: Color(hex: 0x38BDF8), selection: Color(hex: 0x1D4ED8), base: Color(hex: 0x7DD3FC))
        case .synthwave:
            return Palette(art: .synthGrid, light: false,
                           bgTop: Color(hex: 0x1A0533), bgMid: Color(hex: 0x3B0A57), bgBottom: Color(hex: 0x0D0221),
                           glowA: Color(hex: 0xFF2E97, opacity: 0.45), glowB: Color(hex: 0x00E5FF, opacity: 0.30),
                           artColor: Color(hex: 0xFF2E97), artColor2: Color(hex: 0xFFB000),
                           panel: Color(hex: 0x1C0833, opacity: 0.74), header: Color(hex: 0x1A0630, opacity: 0.90),
                           lcd: Color(hex: 0x0C0218), control: Color(hex: 0x33124F), controlHi: Color(hex: 0x431A66),
                           well: Color(hex: 0x260C3E), wellAlt: Color(hex: 0x1F0934), track: Color(hex: 0x4A2170), dim: Color(hex: 0x8A5CB0),
                           line: Color(hex: 0x3F1763), line2: Color(hex: 0x5A2384),
                           text: Color(hex: 0xFFF0FB), text2: Color(hex: 0xF0B8E8), muted: Color(hex: 0xB07FC8),
                           accent: Color(hex: 0xFF2E97), selection: Color(hex: 0x8E1C7A), base: Color(hex: 0x00E5FF))
        case .aurora:
            return Palette(art: .aurora, light: false,
                           bgTop: Color(hex: 0x05121C), bgMid: Color(hex: 0x081A26), bgBottom: Color(hex: 0x02060B),
                           glowA: Color(hex: 0x10B981, opacity: 0.30), glowB: Color(hex: 0x8B5CF6, opacity: 0.38),
                           artColor: Color(hex: 0x34F5A6), artColor2: Color(hex: 0xA855F7),
                           panel: Color(hex: 0x081820, opacity: 0.70), header: Color(hex: 0x07161E, opacity: 0.88),
                           lcd: Color(hex: 0x020A0F), control: Color(hex: 0x10303A), controlHi: Color(hex: 0x16404C),
                           well: Color(hex: 0x0B242C), wellAlt: Color(hex: 0x091D24), track: Color(hex: 0x1D4652), dim: Color(hex: 0x4A7F86),
                           line: Color(hex: 0x173A43), line2: Color(hex: 0x21505B),
                           text: Color(hex: 0xE8FFF6), text2: Color(hex: 0xA9E6D2), muted: Color(hex: 0x6FA99A),
                           accent: Color(hex: 0x34F5A6), selection: Color(hex: 0x6D28D9), base: Color(hex: 0xC4B5FD))
        case .ember:
            return Palette(art: .embers, light: false,
                           bgTop: Color(hex: 0x2A0A04), bgMid: Color(hex: 0x1A0603), bgBottom: Color(hex: 0x070201),
                           glowA: Color(hex: 0xFF4D00, opacity: 0.42), glowB: Color(hex: 0xFFB000, opacity: 0.26),
                           artColor: Color(hex: 0xFF8A3D), artColor2: Color(hex: 0xFFD166),
                           panel: Color(hex: 0x220B06, opacity: 0.76), header: Color(hex: 0x260C06, opacity: 0.90),
                           lcd: Color(hex: 0x0E0402), control: Color(hex: 0x3D170C), controlHi: Color(hex: 0x4F1F10),
                           well: Color(hex: 0x2E1209), wellAlt: Color(hex: 0x260E07), track: Color(hex: 0x5A2814), dim: Color(hex: 0x9A5A3C),
                           line: Color(hex: 0x4A1E0F), line2: Color(hex: 0x632A15),
                           text: Color(hex: 0xFFF1E6), text2: Color(hex: 0xF5C6A5), muted: Color(hex: 0xC08A6A),
                           accent: Color(hex: 0xFF7A1A), selection: Color(hex: 0x9A2E08), base: Color(hex: 0xFFC46B))
        case .ocean:
            return Palette(art: .waves, light: false,
                           bgTop: Color(hex: 0x00303F), bgMid: Color(hex: 0x002233), bgBottom: Color(hex: 0x000E17),
                           glowA: Color(hex: 0x00E0C6, opacity: 0.30), glowB: Color(hex: 0x0077FF, opacity: 0.34),
                           artColor: Color(hex: 0x5EEAD4), artColor2: Color(hex: 0x38BDF8),
                           panel: Color(hex: 0x002433, opacity: 0.72), header: Color(hex: 0x00202D, opacity: 0.90),
                           lcd: Color(hex: 0x000C12), control: Color(hex: 0x0A3A4C), controlHi: Color(hex: 0x0F4A60),
                           well: Color(hex: 0x062E3D), wellAlt: Color(hex: 0x052633), track: Color(hex: 0x15536A), dim: Color(hex: 0x4A8DA0),
                           line: Color(hex: 0x0E4255), line2: Color(hex: 0x155A72),
                           text: Color(hex: 0xE6FFFB), text2: Color(hex: 0xA5E4EC), muted: Color(hex: 0x69A8B5),
                           accent: Color(hex: 0x2DD4BF), selection: Color(hex: 0x0E7490), base: Color(hex: 0x7DD3FC))
        case .forest:
            return Palette(art: .hills, light: false,
                           bgTop: Color(hex: 0x123323), bgMid: Color(hex: 0x0B2117), bgBottom: Color(hex: 0x040B07),
                           glowA: Color(hex: 0xA3E635, opacity: 0.22), glowB: Color(hex: 0x16A34A, opacity: 0.30),
                           artColor: Color(hex: 0x0E2A1C), artColor2: Color(hex: 0x153D28),
                           panel: Color(hex: 0x0E2219, opacity: 0.80), header: Color(hex: 0x0F241A, opacity: 0.92),
                           lcd: Color(hex: 0x050E09), control: Color(hex: 0x1A3A2A), controlHi: Color(hex: 0x224A35),
                           well: Color(hex: 0x142E22), wellAlt: Color(hex: 0x11271D), track: Color(hex: 0x2A5240), dim: Color(hex: 0x5E8A70),
                           line: Color(hex: 0x214332), line2: Color(hex: 0x2B5640),
                           text: Color(hex: 0xEEFBEF), text2: Color(hex: 0xBEDFC4), muted: Color(hex: 0x86A88E),
                           accent: Color(hex: 0x84CC16), selection: Color(hex: 0x166534), base: Color(hex: 0xBEF264))
        case .daylight:
            return Palette(art: .paper, light: true,
                           bgTop: Color(hex: 0xF4F6FA), bgMid: Color(hex: 0xECEFF5), bgBottom: Color(hex: 0xDFE4EE),
                           glowA: Color(hex: 0x93C5FD, opacity: 0.55), glowB: Color(hex: 0xFBCFE8, opacity: 0.55),
                           artColor: Color(hex: 0x3B82F6, opacity: 0.10), artColor2: Color(hex: 0xEC4899, opacity: 0.08),
                           panel: Color(hex: 0xFFFFFF, opacity: 0.86), header: Color(hex: 0xFFFFFF, opacity: 0.92),
                           lcd: Color(hex: 0xE8ECF3), control: Color(hex: 0xE6E9F0), controlHi: Color(hex: 0xD9DEE8),
                           well: Color(hex: 0xEEF1F6), wellAlt: Color(hex: 0xE5E9F0), track: Color(hex: 0xCBD2DE), dim: Color(hex: 0x98A2B3),
                           line: Color(hex: 0xD5DBE5), line2: Color(hex: 0xC4CCD9),
                           text: Color(hex: 0x111827), text2: Color(hex: 0x374151), muted: Color(hex: 0x6B7280),
                           accent: Color(hex: 0x2563EB), selection: Color(hex: 0x2563EB), base: Color(hex: 0x4F46E5))
        }
    }
}

// MARK: - Background

/// The window background: a theme gradient, coloured glows, the theme's artwork
/// and a glow that follows the loop state.
struct ThemeBackground: View {
    let theme: AppTheme
    let stateColor: Color
    let live: Bool

    var body: some View {
        let p = theme.palette
        ZStack {
            LinearGradient(colors: [p.bgTop, p.bgMid, p.bgBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [p.glowA, .clear], center: UnitPoint(x: 0.1, y: 0.0), startRadius: 0, endRadius: 900)
            RadialGradient(colors: [p.glowB, .clear], center: UnitPoint(x: 0.95, y: 1.0), startRadius: 0, endRadius: 900)
            ThemeArt(palette: p)
            RadialGradient(colors: [stateColor.opacity(live ? (p.light ? 0.12 : 0.18) : 0.05), .clear],
                           center: UnitPoint(x: 0.36, y: 0.42), startRadius: 0, endRadius: 560)
                .animation(.easeInOut(duration: 0.6), value: live)
        }
        .ignoresSafeArea()
    }
}

/// Theme artwork, slowly animated where it helps the mood (stars, aurora, embers, waves).
private struct ThemeArt: View {
    let palette: AppTheme.Palette

    var body: some View {
        switch palette.art {
        case .stars, .aurora, .embers, .waves, .synthGrid:
            TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in draw(&ctx, size, t) }
            }
        default:
            Canvas { ctx, size in draw(&ctx, size, 0) }
        }
    }

    /// Deterministic pseudo random number in 0…1.
    private func rand(_ i: Int, _ salt: Int) -> CGFloat {
        var x = UInt64(truncatingIfNeeded: i &* 73_856_093 ^ salt &* 19_349_663)
        x ^= x >> 33
        x = x &* 0xFF51_AFD7_ED55_8CCD
        x ^= x >> 33
        return CGFloat(x % 10_000) / 10_000
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let p = palette
        let w = size.width
        let h = size.height
        switch p.art {
        case .dots:
            let step: CGFloat = 22
            var y: CGFloat = step / 2
            while y < h {
                var x: CGFloat = step / 2
                while x < w {
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.3, height: 1.3)), with: .color(p.artColor))
                    x += step
                }
                y += step
            }
            // a few large soft circles
            for i in 0..<3 {
                let r = 260 + rand(i, 1) * 260
                let c = CGPoint(x: rand(i, 2) * w, y: rand(i, 3) * h)
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(p.artColor), lineWidth: 1)
            }

        case .stars:
            for i in 0..<260 {
                let x = rand(i, 11) * w
                let y = rand(i, 12) * h
                let big = rand(i, 13) > 0.93
                let s: CGFloat = big ? 2.4 : 1 + rand(i, 14) * 0.9
                let tw = 0.55 + 0.45 * sin(t * (0.6 + Double(rand(i, 15)) * 1.6) + Double(i))
                let col = rand(i, 16) > 0.7 ? p.artColor2 : p.artColor
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: s, height: s)), with: .color(col.opacity(0.25 + 0.6 * tw)))
                if big {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 5, y: y - 5, width: s + 10, height: s + 10)),
                             with: .color(col.opacity(0.08 * tw)))
                }
            }
            // a faint galaxy band
            var band = Path()
            band.move(to: CGPoint(x: -50, y: h * 0.85))
            band.addQuadCurve(to: CGPoint(x: w + 50, y: h * 0.1), control: CGPoint(x: w * 0.45, y: h * 0.62))
            ctx.stroke(band, with: .color(p.artColor2.opacity(0.07)), style: StrokeStyle(lineWidth: 140, lineCap: .round))
            ctx.stroke(band, with: .color(p.artColor.opacity(0.05)), style: StrokeStyle(lineWidth: 50, lineCap: .round))

        case .synthGrid:
            let horizon = h * 0.58
            // sun with stripes
            let r = min(w, h) * 0.2
            let sc = CGPoint(x: w * 0.5, y: horizon - r * 0.45)
            let sun = Path(ellipseIn: CGRect(x: sc.x - r, y: sc.y - r, width: 2 * r, height: 2 * r))
            ctx.drawLayer { g in
                g.clip(to: sun)
                g.fill(sun, with: .linearGradient(Gradient(colors: [p.artColor2, p.artColor]),
                                                  startPoint: CGPoint(x: sc.x, y: sc.y - r), endPoint: CGPoint(x: sc.x, y: sc.y + r)))
                for k in 0..<7 {
                    let yy = sc.y + r * (0.1 + 0.13 * CGFloat(k))
                    g.fill(Path(CGRect(x: sc.x - r, y: yy, width: 2 * r, height: 2 + CGFloat(k) * 1.6)), with: .color(p.bgMid))
                }
            }
            ctx.fill(Path(ellipseIn: CGRect(x: sc.x - r * 1.6, y: sc.y - r * 1.6, width: r * 3.2, height: r * 3.2)),
                     with: .radialGradient(Gradient(colors: [p.artColor.opacity(0.25), .clear]), center: sc, startRadius: r, endRadius: r * 1.6))
            // floor
            ctx.fill(Path(CGRect(x: 0, y: horizon, width: w, height: h - horizon)),
                     with: .linearGradient(Gradient(colors: [Color(hex: 0x12021F), p.bgBottom]),
                                           startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: h)))
            let lineCol = Color(hex: 0x00E5FF)
            for k in -14...14 {
                var l = Path()
                l.move(to: CGPoint(x: w * 0.5 + CGFloat(k) * w * 0.012, y: horizon))
                l.addLine(to: CGPoint(x: w * 0.5 + CGFloat(k) * w * 0.16, y: h))
                ctx.stroke(l, with: .color(lineCol.opacity(0.35)), lineWidth: 1.2)
            }
            let phase = CGFloat((t * 0.25).truncatingRemainder(dividingBy: 1))
            for k in 0..<14 {
                let f = (CGFloat(k) + phase) / 14
                let yy = horizon + (h - horizon) * f * f
                ctx.stroke(Path(CGRect(x: 0, y: yy, width: w, height: 0.5)), with: .color(lineCol.opacity(0.12 + 0.4 * Double(f))), lineWidth: 1.2)
            }
            ctx.stroke(Path(CGRect(x: 0, y: horizon, width: w, height: 0.5)), with: .color(p.artColor.opacity(0.9)), lineWidth: 2)

        case .aurora:
            for band in 0..<4 {
                let col = band % 2 == 0 ? p.artColor : p.artColor2
                let baseY = h * (0.16 + 0.11 * CGFloat(band))
                var path = Path()
                let steps = 60
                for s in 0...steps {
                    let x = w * CGFloat(s) / CGFloat(steps)
                    let y = baseY + 40 * CGFloat(sin(Double(s) * 0.21 + t * 0.25 + Double(band) * 1.7))
                        + 26 * CGFloat(sin(Double(s) * 0.07 - t * 0.13 + Double(band)))
                    if s == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                ctx.stroke(path, with: .color(col.opacity(0.10)), style: StrokeStyle(lineWidth: 120, lineCap: .round, lineJoin: .round))
                ctx.stroke(path, with: .color(col.opacity(0.14)), style: StrokeStyle(lineWidth: 40, lineCap: .round, lineJoin: .round))
                ctx.stroke(path, with: .color(col.opacity(0.35)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            for i in 0..<120 {
                ctx.fill(Path(ellipseIn: CGRect(x: rand(i, 21) * w, y: rand(i, 22) * h, width: 1.3, height: 1.3)),
                         with: .color(.white.opacity(0.25 + 0.3 * Double(rand(i, 23)))))
            }

        case .embers:
            // heat at the bottom
            ctx.fill(Path(CGRect(x: 0, y: h * 0.55, width: w, height: h * 0.45)),
                     with: .linearGradient(Gradient(colors: [.clear, p.artColor.opacity(0.22)]),
                                           startPoint: CGPoint(x: 0, y: h * 0.55), endPoint: CGPoint(x: 0, y: h)))
            for i in 0..<90 {
                let speed = 0.02 + Double(rand(i, 31)) * 0.05
                let f = (Double(rand(i, 32)) + t * speed).truncatingRemainder(dividingBy: 1)
                let x = rand(i, 33) * w + CGFloat(sin(t * 0.7 + Double(i)) * 18)
                let y = h * CGFloat(1 - f)
                let s = 1.5 + rand(i, 34) * 3
                let a = sin(f * .pi)
                let col = rand(i, 35) > 0.5 ? p.artColor : p.artColor2
                ctx.fill(Path(ellipseIn: CGRect(x: x - s * 2, y: y - s * 2, width: s * 4, height: s * 4)), with: .color(col.opacity(0.08 * a)))
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: s, height: s)), with: .color(col.opacity(0.75 * a)))
            }

        case .waves:
            for k in 0..<9 {
                let baseY = h * (0.45 + 0.07 * CGFloat(k))
                var path = Path()
                let steps = 80
                for s in 0...steps {
                    let x = w * CGFloat(s) / CGFloat(steps)
                    let y = baseY + 14 * CGFloat(sin(Double(s) * 0.16 + t * (0.35 + 0.05 * Double(k)) + Double(k)))
                    if s == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                let col = k % 2 == 0 ? p.artColor : p.artColor2
                ctx.stroke(path, with: .color(col.opacity(0.10 + 0.03 * Double(k))), lineWidth: 1.5)
            }
            for i in 0..<40 {
                let f = (Double(rand(i, 41)) + t * 0.015 * (1 + Double(rand(i, 42)))).truncatingRemainder(dividingBy: 1)
                let s = 2 + rand(i, 43) * 6
                ctx.stroke(Path(ellipseIn: CGRect(x: rand(i, 44) * w, y: h * CGFloat(1 - f), width: s, height: s)),
                           with: .color(p.artColor.opacity(0.25 * sin(f * .pi))), lineWidth: 1)
            }

        case .hills:
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.72, y: h * 0.08, width: 90, height: 90)), with: .color(Color(hex: 0xE9F5C9, opacity: 0.18)))
            let layers: [(CGFloat, Color, Double)] = [
                (0.42, Color(hex: 0x1E4A33), 0.6), (0.55, Color(hex: 0x173C29), 0.8),
                (0.68, Color(hex: 0x102D1F), 1.0), (0.80, Color(hex: 0x0A1F15), 1.0),
            ]
            for (li, layer) in layers.enumerated() {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: h))
                let steps = 40
                for s in 0...steps {
                    let x = w * CGFloat(s) / CGFloat(steps)
                    let y = h * layer.0 + 50 * CGFloat(sin(Double(s) * 0.33 + Double(li) * 2.1))
                        + 22 * CGFloat(sin(Double(s) * 0.9 + Double(li)))
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: w, y: h))
                path.closeSubpath()
                ctx.fill(path, with: .color(layer.1.opacity(layer.2)))
                // tree tips on the far layers
                if li < 3 {
                    for k in 0..<28 {
                        let x = rand(k, 50 + li) * w
                        let s = Int(x / w * CGFloat(steps))
                        let y = h * layer.0 + 50 * CGFloat(sin(Double(s) * 0.33 + Double(li) * 2.1))
                            + 22 * CGFloat(sin(Double(s) * 0.9 + Double(li)))
                        let th = 18 + rand(k, 60 + li) * 26
                        var tree = Path()
                        tree.move(to: CGPoint(x: x, y: y - th))
                        tree.addLine(to: CGPoint(x: x - th * 0.32, y: y + 4))
                        tree.addLine(to: CGPoint(x: x + th * 0.32, y: y + 4))
                        tree.closeSubpath()
                        ctx.fill(tree, with: .color(layer.1.opacity(layer.2)))
                    }
                }
            }

        case .paper:
            for i in 0..<5 {
                let r = 180 + rand(i, 71) * 220
                let c = CGPoint(x: rand(i, 72) * w, y: rand(i, 73) * h)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                         with: .radialGradient(Gradient(colors: [i % 2 == 0 ? p.artColor : p.artColor2, .clear]),
                                               center: c, startRadius: 0, endRadius: r))
            }
            let step: CGFloat = 24
            var y: CGFloat = step / 2
            while y < h {
                var x: CGFloat = step / 2
                while x < w {
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.4, height: 1.4)), with: .color(Color(hex: 0x1E293B, opacity: 0.08)))
                    x += step
                }
                y += step
            }
        }
    }
}
