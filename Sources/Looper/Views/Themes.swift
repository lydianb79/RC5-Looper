import SwiftUI

/// Window themes. Each one changes the background artwork, every surface colour
/// (panels, header, display, controls, grid), the text colours and the accent.
enum AppTheme: String, CaseIterable, Identifiable {
    case graphite, midnight, synthwave, aurora, ember, ocean, forest, daylight
    case sunset, cyberpunk, terminal, sakura, arctic, vintage
    case nebula, desert, arcade, studioWood, candy, bauhaus

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
        case .sunset: return "Sunset"
        case .cyberpunk: return "Neon City"
        case .terminal: return "Terminal"
        case .sakura: return "Sakura"
        case .arctic: return "Arctic"
        case .vintage: return "Vintage Tape"
        case .nebula: return "Nebula"
        case .desert: return "Desert Dusk"
        case .arcade: return "Arcade"
        case .studioWood: return "Studio Wood"
        case .candy: return "Candy"
        case .bauhaus: return "Bauhaus"
        }
    }

    /// Background artwork.
    enum Art { case dots, stars, synthGrid, aurora, embers, waves, hills, paper, mountains, cityRain, codeRain, petals, snow, tape, nebula, dunes, arcade, wood, candy, bauhaus }

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
        case .sunset:
            return Palette(art: .mountains, light: false,
                           bgTop: Color(hex: 0x2B1055), bgMid: Color(hex: 0xC2410C), bgBottom: Color(hex: 0x1A0B1E),
                           glowA: Color(hex: 0xFB7185, opacity: 0.35), glowB: Color(hex: 0xFBBF24, opacity: 0.30),
                           artColor: Color(hex: 0xFFD166), artColor2: Color(hex: 0x2A0F2E),
                           panel: Color(hex: 0x2A1028, opacity: 0.74), header: Color(hex: 0x2A0F2A, opacity: 0.90),
                           lcd: Color(hex: 0x14060F), control: Color(hex: 0x4A1D3C), controlHi: Color(hex: 0x5C2549),
                           well: Color(hex: 0x3A1531), wellAlt: Color(hex: 0x321229), track: Color(hex: 0x642A50), dim: Color(hex: 0xA8648A),
                           line: Color(hex: 0x55213F), line2: Color(hex: 0x6E2C52),
                           text: Color(hex: 0xFFF3EA), text2: Color(hex: 0xF8C9B4), muted: Color(hex: 0xC98F98),
                           accent: Color(hex: 0xFF8C42), selection: Color(hex: 0xB4235A), base: Color(hex: 0xFFD166))
        case .cyberpunk:
            return Palette(art: .cityRain, light: false,
                           bgTop: Color(hex: 0x05060F), bgMid: Color(hex: 0x0A0F24), bgBottom: Color(hex: 0x020205),
                           glowA: Color(hex: 0xFCEE0A, opacity: 0.16), glowB: Color(hex: 0x00F0FF, opacity: 0.26),
                           artColor: Color(hex: 0x00F0FF), artColor2: Color(hex: 0xFCEE0A),
                           panel: Color(hex: 0x0A0D1C, opacity: 0.78), header: Color(hex: 0x0B0E1F, opacity: 0.92),
                           lcd: Color(hex: 0x020309), control: Color(hex: 0x161C38), controlHi: Color(hex: 0x1F2750),
                           well: Color(hex: 0x10152C), wellAlt: Color(hex: 0x0D1124), track: Color(hex: 0x2A3463), dim: Color(hex: 0x5A6AA0),
                           line: Color(hex: 0x1E2650), line2: Color(hex: 0x2C376E),
                           text: Color(hex: 0xF1FBFF), text2: Color(hex: 0xB9D7E6), muted: Color(hex: 0x7C93AE),
                           accent: Color(hex: 0xFCEE0A), selection: Color(hex: 0x00808A), base: Color(hex: 0x00F0FF))
        case .terminal:
            return Palette(art: .codeRain, light: false,
                           bgTop: Color(hex: 0x020A04), bgMid: Color(hex: 0x010603), bgBottom: Color(hex: 0x000200),
                           glowA: Color(hex: 0x22FF66, opacity: 0.12), glowB: Color(hex: 0x00AA44, opacity: 0.14),
                           artColor: Color(hex: 0x33FF77), artColor2: Color(hex: 0xB6FFC9),
                           panel: Color(hex: 0x031008, opacity: 0.86), header: Color(hex: 0x041209, opacity: 0.94),
                           lcd: Color(hex: 0x010502), control: Color(hex: 0x0A2414), controlHi: Color(hex: 0x0F301B),
                           well: Color(hex: 0x071A0E), wellAlt: Color(hex: 0x05140B), track: Color(hex: 0x14432A), dim: Color(hex: 0x2F8A52),
                           line: Color(hex: 0x0E3320), line2: Color(hex: 0x16492D),
                           text: Color(hex: 0xC8FFD8), text2: Color(hex: 0x7EE6A0), muted: Color(hex: 0x3FA866),
                           accent: Color(hex: 0x33FF77), selection: Color(hex: 0x0B6B2E), base: Color(hex: 0x9DFFB9))
        case .sakura:
            return Palette(art: .petals, light: false,
                           bgTop: Color(hex: 0x2A1024), bgMid: Color(hex: 0x1C0B19), bgBottom: Color(hex: 0x0C050B),
                           glowA: Color(hex: 0xF9A8D4, opacity: 0.30), glowB: Color(hex: 0xC084FC, opacity: 0.20),
                           artColor: Color(hex: 0xFBCFE8), artColor2: Color(hex: 0xF472B6),
                           panel: Color(hex: 0x24101F, opacity: 0.76), header: Color(hex: 0x250F20, opacity: 0.90),
                           lcd: Color(hex: 0x10060D), control: Color(hex: 0x3D1A34), controlHi: Color(hex: 0x4D2242),
                           well: Color(hex: 0x30142A), wellAlt: Color(hex: 0x2A1124), track: Color(hex: 0x58284C), dim: Color(hex: 0xA4709A),
                           line: Color(hex: 0x4A1F40), line2: Color(hex: 0x622A55),
                           text: Color(hex: 0xFFF0F7), text2: Color(hex: 0xF5C2DC), muted: Color(hex: 0xC48FAE),
                           accent: Color(hex: 0xF472B6), selection: Color(hex: 0x9D174D), base: Color(hex: 0xFBCFE8))
        case .arctic:
            return Palette(art: .snow, light: true,
                           bgTop: Color(hex: 0xDCEBF7), bgMid: Color(hex: 0xEEF5FB), bgBottom: Color(hex: 0xC9DCEB),
                           glowA: Color(hex: 0x7DD3FC, opacity: 0.45), glowB: Color(hex: 0xA5B4FC, opacity: 0.40),
                           artColor: Color(hex: 0xFFFFFF), artColor2: Color(hex: 0x94B8D6),
                           panel: Color(hex: 0xF7FBFF, opacity: 0.80), header: Color(hex: 0xF5FAFF, opacity: 0.90),
                           lcd: Color(hex: 0xE2EDF6), control: Color(hex: 0xDDE9F3), controlHi: Color(hex: 0xCFDFEC),
                           well: Color(hex: 0xE8F1F8), wellAlt: Color(hex: 0xDFEAF3), track: Color(hex: 0xBACFE0), dim: Color(hex: 0x8AA4BA),
                           line: Color(hex: 0xC8D9E7), line2: Color(hex: 0xB4C9DB),
                           text: Color(hex: 0x0B2135), text2: Color(hex: 0x2C4A63), muted: Color(hex: 0x5F7C94),
                           accent: Color(hex: 0x0284C7), selection: Color(hex: 0x0284C7), base: Color(hex: 0x0369A1))
        case .vintage:
            return Palette(art: .tape, light: true,
                           bgTop: Color(hex: 0xEADBC0), bgMid: Color(hex: 0xE2CFAE), bgBottom: Color(hex: 0xC9B08A),
                           glowA: Color(hex: 0xFFF3D6, opacity: 0.6), glowB: Color(hex: 0xB45309, opacity: 0.18),
                           artColor: Color(hex: 0x7C4A1E), artColor2: Color(hex: 0xC2410C),
                           panel: Color(hex: 0xF6ECD8, opacity: 0.88), header: Color(hex: 0x3B2A1A, opacity: 0.94),
                           lcd: Color(hex: 0x2B1E12), control: Color(hex: 0xE9DABD), controlHi: Color(hex: 0xDDCBA8),
                           well: Color(hex: 0xEFE2C8), wellAlt: Color(hex: 0xE6D6B8), track: Color(hex: 0xCDB58E), dim: Color(hex: 0xA48B66),
                           line: Color(hex: 0xD5BF98), line2: Color(hex: 0xC4AB80),
                           text: Color(hex: 0x2B1B0E), text2: Color(hex: 0x5A3E24), muted: Color(hex: 0x8A6C4C),
                           accent: Color(hex: 0xC2410C), selection: Color(hex: 0xC2410C), base: Color(hex: 0x9A3412))
        case .nebula:
            return Palette(art: .nebula, light: false,
                           bgTop: Color(hex: 0x0A0418), bgMid: Color(hex: 0x120828), bgBottom: Color(hex: 0x03020A),
                           glowA: Color(hex: 0x7C3AED, opacity: 0.35), glowB: Color(hex: 0x06B6D4, opacity: 0.25),
                           artColor: Color(hex: 0xC026D3), artColor2: Color(hex: 0x22D3EE),
                           panel: Color(hex: 0x120A26, opacity: 0.72), header: Color(hex: 0x110923, opacity: 0.9),
                           lcd: Color(hex: 0x05030E), control: Color(hex: 0x24164A), controlHi: Color(hex: 0x2E1D5C),
                           well: Color(hex: 0x1A1036), wellAlt: Color(hex: 0x150D2D), track: Color(hex: 0x372466), dim: Color(hex: 0x7A68B0),
                           line: Color(hex: 0x2B1C55), line2: Color(hex: 0x3B2870),
                           text: Color(hex: 0xF5F0FF), text2: Color(hex: 0xCDBEF5), muted: Color(hex: 0x9183C2),
                           accent: Color(hex: 0xE879F9), selection: Color(hex: 0x7E22CE), base: Color(hex: 0x67E8F9))
        case .desert:
            return Palette(art: .dunes, light: false,
                           bgTop: Color(hex: 0x3B1D4A), bgMid: Color(hex: 0xB45309), bgBottom: Color(hex: 0x2A1206),
                           glowA: Color(hex: 0xF59E0B, opacity: 0.35), glowB: Color(hex: 0xDB2777, opacity: 0.25),
                           artColor: Color(hex: 0x7C2D12), artColor2: Color(hex: 0xFDE68A),
                           panel: Color(hex: 0x2A140C, opacity: 0.76), header: Color(hex: 0x2A140C, opacity: 0.9),
                           lcd: Color(hex: 0x140803), control: Color(hex: 0x4A2512), controlHi: Color(hex: 0x5C3018),
                           well: Color(hex: 0x3A1D0E), wellAlt: Color(hex: 0x32190C), track: Color(hex: 0x6B3A1D), dim: Color(hex: 0xB07A52),
                           line: Color(hex: 0x5A2E16), line2: Color(hex: 0x73401F),
                           text: Color(hex: 0xFFF5E6), text2: Color(hex: 0xF5D3A8), muted: Color(hex: 0xC9A27A),
                           accent: Color(hex: 0xFB923C), selection: Color(hex: 0xB45309), base: Color(hex: 0xFDE68A))
        case .arcade:
            return Palette(art: .arcade, light: false,
                           bgTop: Color(hex: 0x050510), bgMid: Color(hex: 0x080818), bgBottom: Color(hex: 0x020206),
                           glowA: Color(hex: 0x00FF9C, opacity: 0.12), glowB: Color(hex: 0xFF00E5, opacity: 0.16),
                           artColor: Color(hex: 0x00FF9C), artColor2: Color(hex: 0xFF00E5),
                           panel: Color(hex: 0x0A0A1C, opacity: 0.84), header: Color(hex: 0x0B0B1E, opacity: 0.94),
                           lcd: Color(hex: 0x000005), control: Color(hex: 0x16163A), controlHi: Color(hex: 0x1E1E4C),
                           well: Color(hex: 0x10102A), wellAlt: Color(hex: 0x0C0C22), track: Color(hex: 0x262660), dim: Color(hex: 0x5B5BA8),
                           line: Color(hex: 0x1E1E50), line2: Color(hex: 0x2A2A6A),
                           text: Color(hex: 0xEFFFF7), text2: Color(hex: 0xB0F5D8), muted: Color(hex: 0x7A8FB8),
                           accent: Color(hex: 0x00FF9C), selection: Color(hex: 0x6D28D9), base: Color(hex: 0xFF5CF0))
        case .studioWood:
            return Palette(art: .wood, light: false,
                           bgTop: Color(hex: 0x3B2416), bgMid: Color(hex: 0x2A190F), bgBottom: Color(hex: 0x140B06),
                           glowA: Color(hex: 0xFFB86B, opacity: 0.22), glowB: Color(hex: 0x8B5A2B, opacity: 0.25),
                           artColor: Color(hex: 0x1A0F08), artColor2: Color(hex: 0x6B4426),
                           panel: Color(hex: 0x1C130D, opacity: 0.88), header: Color(hex: 0x1A110B, opacity: 0.95),
                           lcd: Color(hex: 0x0D0805), control: Color(hex: 0x33241A), controlHi: Color(hex: 0x403022),
                           well: Color(hex: 0x261A12), wellAlt: Color(hex: 0x21160F), track: Color(hex: 0x4A3626), dim: Color(hex: 0x8C6E55),
                           line: Color(hex: 0x3A2A1E), line2: Color(hex: 0x4B3828),
                           text: Color(hex: 0xFBF1E6), text2: Color(hex: 0xE2CBB2), muted: Color(hex: 0xA88C72),
                           accent: Color(hex: 0xF5A524), selection: Color(hex: 0x8A5A1F), base: Color(hex: 0xFFD08A))
        case .candy:
            return Palette(art: .candy, light: true,
                           bgTop: Color(hex: 0xFFE4F1), bgMid: Color(hex: 0xFDF2FF), bgBottom: Color(hex: 0xDFF7F0),
                           glowA: Color(hex: 0xF9A8D4, opacity: 0.6), glowB: Color(hex: 0x99F6E4, opacity: 0.6),
                           artColor: Color(hex: 0xF472B6), artColor2: Color(hex: 0x2DD4BF),
                           panel: Color(hex: 0xFFFFFF, opacity: 0.82), header: Color(hex: 0xFFFFFF, opacity: 0.9),
                           lcd: Color(hex: 0xFCE7F3), control: Color(hex: 0xFBE3EF), controlHi: Color(hex: 0xF6D2E4),
                           well: Color(hex: 0xFDF0F6), wellAlt: Color(hex: 0xF9E6F0), track: Color(hex: 0xEBC8DA), dim: Color(hex: 0xC08AA6),
                           line: Color(hex: 0xF0D2E1), line2: Color(hex: 0xE5BDD1),
                           text: Color(hex: 0x3B1530), text2: Color(hex: 0x6B2F57), muted: Color(hex: 0x9B6A88),
                           accent: Color(hex: 0xDB2777), selection: Color(hex: 0xDB2777), base: Color(hex: 0x0D9488))
        case .bauhaus:
            return Palette(art: .bauhaus, light: true,
                           bgTop: Color(hex: 0xF3EFE6), bgMid: Color(hex: 0xEDE7DA), bgBottom: Color(hex: 0xE3DCCB),
                           glowA: Color(hex: 0xFFFFFF, opacity: 0.4), glowB: Color(hex: 0xE3DCCB, opacity: 0.4),
                           artColor: Color(hex: 0xD62828), artColor2: Color(hex: 0x1D3FAA),
                           panel: Color(hex: 0xFBF9F4, opacity: 0.92), header: Color(hex: 0xFBF9F4, opacity: 0.96),
                           lcd: Color(hex: 0xEAE3D6), control: Color(hex: 0xEBE5D8), controlHi: Color(hex: 0xDED6C5),
                           well: Color(hex: 0xF2EDE3), wellAlt: Color(hex: 0xEAE3D6), track: Color(hex: 0xCFC6B3), dim: Color(hex: 0x9C927E),
                           line: Color(hex: 0xD9D1C0), line2: Color(hex: 0xC7BDA8),
                           text: Color(hex: 0x141414), text2: Color(hex: 0x3A3A3A), muted: Color(hex: 0x6E675A),
                           accent: Color(hex: 0xD62828), selection: Color(hex: 0x1D3FAA), base: Color(hex: 0x1D3FAA))
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
    static let glyphs = Array("0123456789ABCDEFアカサタナハマヤラワ#$%&*+<>=")

    var body: some View {
        switch palette.art {
        case .stars, .aurora, .embers, .waves, .synthGrid, .cityRain, .codeRain, .petals, .snow, .nebula, .arcade:
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

        case .mountains:
            let sunC = CGPoint(x: w * 0.62, y: h * 0.5)
            ctx.fill(Path(ellipseIn: CGRect(x: sunC.x - 400, y: sunC.y - 400, width: 800, height: 800)),
                     with: .radialGradient(Gradient(colors: [p.artColor.opacity(0.35), .clear]), center: sunC, startRadius: 60, endRadius: 400))
            ctx.fill(Path(ellipseIn: CGRect(x: sunC.x - 70, y: sunC.y - 70, width: 140, height: 140)), with: .color(p.artColor.opacity(0.9)))
            let ranges: [(CGFloat, Double, Double)] = [(0.52, 0.55, 0.7), (0.62, 0.8, 1.1), (0.74, 1.0, 1.6)]
            for (ri, r) in ranges.enumerated() {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: h))
                let steps = 24
                for s in 0...steps {
                    let x = w * CGFloat(s) / CGFloat(steps)
                    let peak = rand(s, 80 + ri) * 120 * CGFloat(r.2)
                    path.addLine(to: CGPoint(x: x, y: h * r.0 - peak + (s % 2 == 0 ? 30 : 0)))
                }
                path.addLine(to: CGPoint(x: w, y: h))
                path.closeSubpath()
                ctx.fill(path, with: .color(p.artColor2.opacity(r.1)))
            }

        case .cityRain:
            // skyline
            var x: CGFloat = 0
            var k = 0
            while x < w {
                let bw = 40 + rand(k, 90) * 90
                let bh = h * (0.25 + rand(k, 91) * 0.4)
                let rect = CGRect(x: x, y: h - bh, width: bw - 6, height: bh)
                ctx.fill(Path(rect), with: .color(Color(hex: 0x070A18)))
                // lit windows
                var wy = rect.minY + 10
                var row = 0
                while wy < h - 10 {
                    var wx = rect.minX + 6
                    var col = 0
                    while wx < rect.maxX - 8 {
                        if rand(k * 97 + row * 13 + col, 92) > 0.72 {
                            let c = rand(k + row + col, 93) > 0.5 ? p.artColor : p.artColor2
                            ctx.fill(Path(CGRect(x: wx, y: wy, width: 4, height: 6)), with: .color(c.opacity(0.55)))
                        }
                        wx += 10
                        col += 1
                    }
                    wy += 14
                    row += 1
                }
                x += bw
                k += 1
            }
            // rain
            for i in 0..<160 {
                let f = (Double(rand(i, 94)) + t * (0.6 + Double(rand(i, 95)) * 0.5)).truncatingRemainder(dividingBy: 1)
                let rx = rand(i, 96) * (w + 200) - CGFloat(f) * 120
                let ry = h * CGFloat(f)
                var l = Path()
                l.move(to: CGPoint(x: rx, y: ry))
                l.addLine(to: CGPoint(x: rx - 6, y: ry + 22))
                ctx.stroke(l, with: .color(p.artColor.opacity(0.22)), lineWidth: 1)
            }

        case .codeRain:
            let colW: CGFloat = 26
            let cols = Int(w / colW) + 1
            for c in 0..<cols {
                let speed = 0.08 + Double(rand(c, 101)) * 0.18
                let head = (Double(rand(c, 102)) + t * speed).truncatingRemainder(dividingBy: 1.4) * Double(h)
                let len = 6 + Int(rand(c, 103) * 10)
                for j in 0..<len {
                    let y = CGFloat(head) - CGFloat(j) * 18
                    if y < -18 || y > h { continue }
                    let glyph = Int(rand(c * 31 + j + Int(t * 2), 104) * 36)
                    let ch = String(ThemeArt.glyphs[glyph % ThemeArt.glyphs.count])
                    let a = j == 0 ? 0.9 : 0.45 * (1 - Double(j) / Double(len))
                    ctx.draw(Text(ch).font(.system(size: 13, design: .monospaced)).foregroundColor((j == 0 ? p.artColor2 : p.artColor).opacity(a)),
                             at: CGPoint(x: CGFloat(c) * colW + 9, y: y))
                }
            }

        case .petals:
            // a branch
            var br = Path()
            br.move(to: CGPoint(x: w + 20, y: h * 0.05))
            br.addQuadCurve(to: CGPoint(x: w * 0.55, y: h * 0.22), control: CGPoint(x: w * 0.78, y: h * 0.02))
            ctx.stroke(br, with: .color(Color(hex: 0x3B1A2C)), style: StrokeStyle(lineWidth: 10, lineCap: .round))
            for i in 0..<26 {
                let f = CGFloat(i) / 26
                let bx = w + 20 - (w * 0.45 + 20) * f + (rand(i, 110) - 0.5) * 40
                let by = h * 0.05 + h * 0.17 * f - 30 * sin(f * .pi) + (rand(i, 111) - 0.5) * 40
                let r = 8 + rand(i, 112) * 10
                ctx.fill(Path(ellipseIn: CGRect(x: bx - r, y: by - r, width: 2 * r, height: 2 * r)), with: .color(p.artColor.opacity(0.55)))
            }
            for i in 0..<70 {
                let speed = 0.025 + Double(rand(i, 113)) * 0.04
                let f = (Double(rand(i, 114)) + t * speed).truncatingRemainder(dividingBy: 1)
                let x = rand(i, 115) * w - CGFloat(f) * w * 0.3 + CGFloat(sin(t * 0.8 + Double(i)) * 20)
                let y = h * CGFloat(f)
                let s = 5 + rand(i, 116) * 6
                var g = ctx
                g.translateBy(x: x, y: y)
                g.rotate(by: .radians(t * 0.8 + Double(i)))
                g.fill(Path(ellipseIn: CGRect(x: -s, y: -s * 0.45, width: 2 * s, height: s * 0.9)),
                       with: .color((i % 3 == 0 ? p.artColor2 : p.artColor).opacity(0.7)))
            }

        case .snow:
            var hill = Path()
            hill.move(to: CGPoint(x: 0, y: h))
            hill.addLine(to: CGPoint(x: 0, y: h * 0.78))
            hill.addQuadCurve(to: CGPoint(x: w * 0.55, y: h * 0.74), control: CGPoint(x: w * 0.25, y: h * 0.66))
            hill.addQuadCurve(to: CGPoint(x: w, y: h * 0.7), control: CGPoint(x: w * 0.8, y: h * 0.82))
            hill.addLine(to: CGPoint(x: w, y: h))
            hill.closeSubpath()
            ctx.fill(hill, with: .color(.white.opacity(0.7)))
            for i in 0..<140 {
                let speed = 0.02 + Double(rand(i, 120)) * 0.04
                let f = (Double(rand(i, 121)) + t * speed).truncatingRemainder(dividingBy: 1)
                let x = rand(i, 122) * w + CGFloat(sin(t * 0.6 + Double(i)) * 24)
                let y = h * CGFloat(f)
                let s = 2 + rand(i, 123) * 4
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: s, height: s)), with: .color(p.artColor2.opacity(0.55)))
            }

        case .tape:
            // two reels and tape path, like an old tape deck
            for (cx, cy) in [(w * 0.18, h * 0.78), (w * 0.86, h * 0.2)] {
                let c = CGPoint(x: cx, y: cy)
                for ring in 0..<6 {
                    let r = 60 + CGFloat(ring) * 26
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                               with: .color(p.artColor.opacity(0.07 + 0.015 * Double(ring))), lineWidth: ring == 5 ? 3 : 1)
                }
                for k in 0..<3 {
                    let a = Double(k) * 2 * .pi / 3
                    var spoke = Path()
                    spoke.move(to: c)
                    spoke.addLine(to: CGPoint(x: c.x + CGFloat(cos(a)) * 50, y: c.y + CGFloat(sin(a)) * 50))
                    ctx.stroke(spoke, with: .color(p.artColor.opacity(0.15)), lineWidth: 8)
                }
            }
            for k in 0..<5 {
                let y = h * (0.1 + 0.2 * CGFloat(k))
                ctx.fill(Path(CGRect(x: 0, y: y, width: w, height: 2)), with: .color(p.artColor2.opacity(0.06)))
            }

        case .nebula:
            for i in 0..<7 {
                let r = 220 + rand(i, 130) * 280
                let drift = CGFloat(sin(t * 0.05 + Double(i))) * 30
                let c = CGPoint(x: rand(i, 131) * w + drift, y: rand(i, 132) * h)
                let col = i % 3 == 0 ? p.artColor : (i % 3 == 1 ? p.artColor2 : Color(hex: 0x6366F1))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r * 0.7, width: 2 * r, height: 1.4 * r)),
                         with: .radialGradient(Gradient(colors: [col.opacity(0.28), .clear]), center: c, startRadius: 0, endRadius: r))
            }
            for i in 0..<220 {
                let tw = 0.5 + 0.5 * sin(t * (0.5 + Double(rand(i, 133)) * 1.4) + Double(i))
                let sz = 0.8 + rand(i, 134) * 1.6
                ctx.fill(Path(ellipseIn: CGRect(x: rand(i, 135) * w, y: rand(i, 136) * h, width: sz, height: sz)),
                         with: .color(.white.opacity(0.25 + 0.6 * tw)))
            }

        case .dunes:
            let sunC = CGPoint(x: w * 0.3, y: h * 0.42)
            ctx.fill(Path(ellipseIn: CGRect(x: sunC.x - 80, y: sunC.y - 80, width: 160, height: 160)), with: .color(p.artColor2.opacity(0.85)))
            ctx.fill(Path(ellipseIn: CGRect(x: sunC.x - 300, y: sunC.y - 300, width: 600, height: 600)),
                     with: .radialGradient(Gradient(colors: [p.artColor2.opacity(0.3), .clear]), center: sunC, startRadius: 70, endRadius: 300))
            let dunes: [(CGFloat, Double, Double)] = [(0.6, 0.55, 0.0), (0.7, 0.75, 1.3), (0.82, 0.95, 2.6)]
            for (di, d) in dunes.enumerated() {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: h))
                for st in 0...60 {
                    let x = w * CGFloat(st) / 60
                    let y = h * d.0 - 60 * CGFloat(sin(Double(st) * 0.11 + d.2)) - 25 * CGFloat(sin(Double(st) * 0.29 + Double(di)))
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: w, y: h))
                path.closeSubpath()
                ctx.fill(path, with: .color(p.artColor.opacity(d.1)))
            }

        case .arcade:
            // scanlines
            var y: CGFloat = 0
            while y < h {
                ctx.fill(Path(CGRect(x: 0, y: y, width: w, height: 1)), with: .color(.white.opacity(0.025)))
                y += 3
            }
            // pixel invaders marching
            let shape = ["00100000100", "00010001000", "00111111100", "01101110110", "11111111111", "10111111101", "10100000101", "00011011000"]
            let px: CGFloat = 5
            let march = CGFloat((t * 12).truncatingRemainder(dividingBy: 160))
            for row in 0..<3 {
                for col in 0..<9 {
                    let ox = CGFloat(col) * 150 + march + CGFloat(row % 2) * 60 - 80
                    let oy = h * 0.12 + CGFloat(row) * 90
                    let colr = row == 1 ? p.artColor2 : p.artColor
                    for (ry, line) in shape.enumerated() {
                        for (rx, ch) in line.enumerated() where ch == "1" {
                            ctx.fill(Path(CGRect(x: ox + CGFloat(rx) * px, y: oy + CGFloat(ry) * px, width: px - 1, height: px - 1)),
                                     with: .color(colr.opacity(0.13)))
                        }
                    }
                }
            }
            // ground line
            ctx.fill(Path(CGRect(x: 0, y: h - 40, width: w, height: 2)), with: .color(p.artColor.opacity(0.3)))

        case .wood:
            // vertical planks with grain
            let plank: CGFloat = 140
            var x: CGFloat = 0
            var k = 0
            while x < w {
                let shade = 0.15 + rand(k, 140) * 0.25
                ctx.fill(Path(CGRect(x: x, y: 0, width: plank - 3, height: h)), with: .color(p.artColor2.opacity(shade)))
                for g in 0..<9 {
                    var line = Path()
                    let gx = x + 10 + CGFloat(g) * (plank - 20) / 9 + rand(k * 9 + g, 141) * 8
                    line.move(to: CGPoint(x: gx, y: 0))
                    for st in 1...20 {
                        let yy = h * CGFloat(st) / 20
                        line.addLine(to: CGPoint(x: gx + 6 * CGFloat(sin(Double(st) * 0.6 + Double(g + k))), y: yy))
                    }
                    ctx.stroke(line, with: .color(p.artColor.opacity(0.25)), lineWidth: 1.2)
                }
                ctx.fill(Path(CGRect(x: x + plank - 3, y: 0, width: 3, height: h)), with: .color(p.artColor.opacity(0.7)))
                x += plank
                k += 1
            }

        case .candy:
            for i in 0..<6 {
                let r = 160 + rand(i, 150) * 200
                let c = CGPoint(x: rand(i, 151) * w, y: rand(i, 152) * h)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                         with: .radialGradient(Gradient(colors: [(i % 2 == 0 ? p.artColor : p.artColor2).opacity(0.18), .clear]),
                                               center: c, startRadius: 0, endRadius: r))
            }
            let sprinkleColors: [Color] = [p.artColor, p.artColor2, Color(hex: 0xFBBF24), Color(hex: 0xA78BFA)]
            for i in 0..<120 {
                var g = ctx
                g.translateBy(x: rand(i, 153) * w, y: rand(i, 154) * h)
                g.rotate(by: .radians(Double(rand(i, 155)) * .pi))
                g.fill(Path(roundedRect: CGRect(x: -7, y: -2, width: 14, height: 4), cornerRadius: 2),
                       with: .color(sprinkleColors[i % 4].opacity(0.45)))
            }

        case .bauhaus:
            // large primary shapes at the edges, partly outside the window
            ctx.fill(Path(ellipseIn: CGRect(x: w - 260, y: -140, width: 420, height: 420)), with: .color(p.artColor.opacity(0.55)))
            ctx.fill(Path(CGRect(x: -120, y: h - 260, width: 360, height: 360)), with: .color(p.artColor2.opacity(0.5)))
            var tri = Path()
            tri.move(to: CGPoint(x: w * 0.55, y: h + 20))
            tri.addLine(to: CGPoint(x: w * 0.7, y: h - 230))
            tri.addLine(to: CGPoint(x: w * 0.85, y: h + 20))
            tri.closeSubpath()
            ctx.fill(tri, with: .color(Color(hex: 0xF2B705).opacity(0.6)))
            var arcP = Path()
            arcP.addArc(center: CGPoint(x: w * 0.42, y: -20), radius: 150, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            ctx.stroke(arcP, with: .color(Color(hex: 0x141414).opacity(0.35)), lineWidth: 14)
            ctx.fill(Path(CGRect(x: w - 22, y: h * 0.35, width: 10, height: h * 0.4)), with: .color(Color(hex: 0x141414).opacity(0.4)))

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
