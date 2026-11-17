import SwiftUI

public extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

/// Luma's colour tokens. The interface is a night field; every metric family is a light of its own
/// colour on it. Volt is the brand light and the primary action, used sparingly elsewhere.
public enum Luma {
    // Night field
    public static let night = Color(hex: 0x05070B)
    public static let deep = Color(hex: 0x0B0F16)
    public static let slate = Color(hex: 0x141A25)
    public static let raised = Color(hex: 0x1C2330)
    public static let line = Color.white.opacity(0.08)
    public static let lineStrong = Color.white.opacity(0.16)

    // Text
    public static let frost = Color(hex: 0xF3F6FC)
    public static let mist = Color(hex: 0xA7B1C4)
    public static let smoke = Color(hex: 0x6B768C)
    /// Text on a volt surface.
    public static let ink = Color(hex: 0x0A0D08)

    // Lights
    public static let volt = Color(hex: 0xC8FF2E)
    public static let ember = Color(hex: 0xFF8038)
    public static let coral = Color(hex: 0xFF4F6D)
    public static let dusk = Color(hex: 0x8A78FF)
    public static let sky = Color(hex: 0x52A9FF)
    public static let aqua = Color(hex: 0x34E0C4)
    public static let amber = Color(hex: 0xFFC247)
    public static let mint = Color(hex: 0x5AE6A0)

    /// Recovery reads red / amber / green at the same cut-offs everywhere it appears.
    public static func recovery(_ score: Double?) -> Color {
        guard let s = score else { return smoke }
        return s >= 67 ? volt : (s >= 34 ? amber : coral)
    }

    /// Heart-rate zones 1…5.
    public static func zone(_ z: Int) -> Color {
        switch z {
        case 1: return Color(hex: 0x7C8AA5)
        case 2: return sky
        case 3: return mint
        case 4: return amber
        default: return coral
        }
    }

    public static let radiusCard: CGFloat = 26
    public static let radiusControl: CGFloat = 16
    public static let gutter: CGFloat = 20
}

/// A metric family and its light.
public enum LumaTone: String, CaseIterable, Sendable {
    case recovery, strain, sleep, heart, hrv, stress, fuel, run, neutral

    public var color: Color {
        switch self {
        case .recovery, .run: return Luma.volt
        case .strain: return Luma.ember
        case .sleep: return Luma.dusk
        case .heart: return Luma.coral
        case .hrv: return Luma.aqua
        case .stress: return Luma.amber
        case .fuel: return Luma.mint
        case .neutral: return Luma.frost
        }
    }

    /// The second stop of the tone's gradient.
    public var partner: Color {
        switch self {
        case .recovery, .run: return Luma.mint
        case .strain: return Luma.coral
        case .sleep: return Luma.sky
        case .heart: return Luma.ember
        case .hrv: return Luma.sky
        case .stress: return Luma.ember
        case .fuel: return Luma.aqua
        case .neutral: return Luma.mist
        }
    }

    public var gradient: LinearGradient {
        LinearGradient(colors: [color, partner], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Type roles. Titles and figures are set in Barlow Condensed, tall and narrow like a timing board;
/// labels and running text stay in the system face.
public enum LumaFont {
    public static func numeral(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        LumaType.condensed(size * 1.06, weight).monospacedDigit()
    }
    public static func title(_ size: CGFloat = 30) -> Font {
        LumaType.condensed(size * 1.36 * LumaType.headingScale, .semibold)
    }
    public static func heading(_ size: CGFloat = 16) -> Font {
        LumaType.condensed(size * 1.3 * LumaType.headingScale, .semibold)
    }
    public static func label(_ size: CGFloat = 11) -> Font {
        Font.system(size: size * LumaType.textScale, weight: .medium)
    }
    public static func body(_ size: CGFloat = 15, _ weight: Font.Weight = .regular) -> Font {
        Font.system(size: size * LumaType.textScale, weight: weight)
    }
}
