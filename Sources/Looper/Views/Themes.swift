import SwiftUI

/// Window themes: background artwork, panel tint and accent colour.
enum AppTheme: String, CaseIterable, Identifiable {
    case graphite, midnight, aurora, ember, forest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .graphite: return "Graphite"
        case .midnight: return "Midnight Blue"
        case .aurora: return "Aurora"
        case .ember: return "Ember"
        case .forest: return "Forest"
        }
    }

    struct Palette {
        let bgTop: Color
        let bgBottom: Color
        let glowA: Color          // top-left glow
        let glowB: Color          // bottom-right glow
        let panel: Color          // translucent panels
        let header: Color
        let accent: Color
        let selection: Color
        let line: Color
    }

    var palette: Palette {
        switch self {
        case .graphite:
            return Palette(bgTop: Color(hex: 0x16161A), bgBottom: Color(hex: 0x0B0B0E),
                           glowA: Color(hex: 0x3A3A48, opacity: 0.35), glowB: Color(hex: 0x23232C, opacity: 0.4),
                           panel: Color(hex: 0x17171B, opacity: 0.88), header: Color(hex: 0x1C1C21, opacity: 0.94),
                           accent: Color(hex: 0x5E7BFF), selection: Color(hex: 0x2A3A8F), line: Color(hex: 0x2A2A31))
        case .midnight:
            return Palette(bgTop: Color(hex: 0x0D1530), bgBottom: Color(hex: 0x04060E),
                           glowA: Color(hex: 0x2B4FD8, opacity: 0.38), glowB: Color(hex: 0x0EA5E9, opacity: 0.20),
                           panel: Color(hex: 0x0F1730, opacity: 0.78), header: Color(hex: 0x0E152B, opacity: 0.92),
                           accent: Color(hex: 0x60A5FF), selection: Color(hex: 0x1E3A8A), line: Color(hex: 0x22305A))
        case .aurora:
            return Palette(bgTop: Color(hex: 0x120E22), bgBottom: Color(hex: 0x06060C),
                           glowA: Color(hex: 0x10B981, opacity: 0.26), glowB: Color(hex: 0x8B5CF6, opacity: 0.34),
                           panel: Color(hex: 0x15122A, opacity: 0.76), header: Color(hex: 0x161327, opacity: 0.92),
                           accent: Color(hex: 0xA78BFA), selection: Color(hex: 0x4C2A99), line: Color(hex: 0x2E2850))
        case .ember:
            return Palette(bgTop: Color(hex: 0x1C0E0C), bgBottom: Color(hex: 0x080404),
                           glowA: Color(hex: 0xDC2626, opacity: 0.32), glowB: Color(hex: 0xF59E0B, opacity: 0.18),
                           panel: Color(hex: 0x1E1211, opacity: 0.80), header: Color(hex: 0x221413, opacity: 0.93),
                           accent: Color(hex: 0xFF7A45), selection: Color(hex: 0x7A2412), line: Color(hex: 0x3A2420))
        case .forest:
            return Palette(bgTop: Color(hex: 0x0C1A13), bgBottom: Color(hex: 0x040906),
                           glowA: Color(hex: 0x16A34A, opacity: 0.26), glowB: Color(hex: 0x84CC16, opacity: 0.14),
                           panel: Color(hex: 0x10201A, opacity: 0.80), header: Color(hex: 0x112019, opacity: 0.93),
                           accent: Color(hex: 0x4ADE80), selection: Color(hex: 0x14532D), line: Color(hex: 0x21382D))
        }
    }
}

/// The window background: gradient, two soft colour glows, a faint dot grid and a glow that follows the loop state.
struct ThemeBackground: View {
    let theme: AppTheme
    let stateColor: Color
    let live: Bool

    var body: some View {
        let p = theme.palette
        ZStack {
            LinearGradient(colors: [p.bgTop, p.bgBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [p.glowA, .clear], center: UnitPoint(x: 0.12, y: 0.05), startRadius: 0, endRadius: 760)
            RadialGradient(colors: [p.glowB, .clear], center: UnitPoint(x: 0.95, y: 0.95), startRadius: 0, endRadius: 820)
            RadialGradient(colors: [stateColor.opacity(live ? 0.16 : 0.06), .clear],
                           center: UnitPoint(x: 0.36, y: 0.42), startRadius: 0, endRadius: 520)
                .animation(.easeInOut(duration: 0.6), value: live)
            Canvas { ctx, size in
                let step: CGFloat = 22
                var y: CGFloat = step / 2
                while y < size.height {
                    var x: CGFloat = step / 2
                    while x < size.width {
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 1.2)), with: .color(.white.opacity(0.045)))
                        x += step
                    }
                    y += step
                }
            }
        }
        .ignoresSafeArea()
    }
}
