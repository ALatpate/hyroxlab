import SwiftUI
import StrandDesign

// HYROX Lab design tokens. Two voices, deliberately: the dark "performance" surface for anything
// live (Go, Run, Race, summaries) and the calmer card surface for reading (Today, Body). Every
// HYROX screen takes colour, type and spacing from here; nothing is hard-coded in views.
enum HX {
    // MARK: Colour
    static let ink = Color(red: 0.043, green: 0.051, blue: 0.063)          // #0B0D10
    static let surface = Color(red: 0.082, green: 0.094, blue: 0.114)      // #15181D
    static let raised = Color(red: 0.110, green: 0.125, blue: 0.153)       // #1C2027
    static let hairline = Color.white.opacity(0.08)
    static let text = Color(red: 0.949, green: 0.957, blue: 0.969)         // #F2F4F7
    static let textDim = Color(red: 0.604, green: 0.639, blue: 0.686)      // #9AA3AF
    static let volt = Color(red: 0.784, green: 1.0, blue: 0.180)           // #C8FF2E
    static let voltDim = Color(red: 0.784, green: 1.0, blue: 0.180).opacity(0.18)
    static let good = Color(red: 0.420, green: 0.863, blue: 0.616)
    static let warn = Color(red: 0.980, green: 0.757, blue: 0.345)
    static let bad = Color(red: 0.976, green: 0.447, blue: 0.447)
    static let run = Color(red: 0.502, green: 0.871, blue: 1.0)
    static let station = Color(red: 1.0, green: 0.690, blue: 0.408)
    static let rox = Color(red: 0.745, green: 0.655, blue: 1.0)

    static func zone(_ z: Int) -> Color { StrandPalette.hrZoneColor(z) }

    static func readinessColor(_ score: Int) -> Color {
        switch score {
        case ..<40: return bad
        case 40..<62: return warn
        default: return good
        }
    }

    // MARK: Type
    static func numeral(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
    static let heroNumeral = numeral(72)
    static let bigNumeral = numeral(44)
    static let midNumeral = numeral(28, weight: .bold)
    static let title = Font.system(.title2, design: .rounded).weight(.bold)
    static let headline = Font.system(.headline, design: .rounded)
    static let body = Font.system(.body, design: .rounded)
    static let caption = Font.system(.caption, design: .rounded)
    static let overline = Font.system(size: 11, weight: .semibold, design: .rounded)

    // MARK: Layout
    static let radius: CGFloat = 24
    static let pad: CGFloat = 16
    static let gap: CGFloat = 12
    static let screenPad: CGFloat = 16
}

// MARK: - Reusable pieces

/// Small-caps tracked label above a number.
struct HXOverline: View {
    let text: String
    var color: Color = HX.textDim
    init(_ text: String, color: Color = HX.textDim) { self.text = text; self.color = color }
    var body: some View {
        Text(text.uppercased()).font(HX.overline).tracking(1.5).foregroundStyle(color)
    }
}

/// The card every HYROX screen is built from.
struct HXCard<Content: View>: View {
    var tint: Color? = nil
    var padding: CGFloat = HX.pad
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: HX.radius, style: .continuous)
                    .fill(tint.map { $0.opacity(0.10) } ?? HX.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: HX.radius, style: .continuous)
                    .strokeBorder(HX.hairline, lineWidth: 1)
            )
    }
}

/// One big number with its unit and a one-line verdict under it.
struct HXStat: View {
    let label: String
    let value: String
    var unit: String? = nil
    var verdict: String? = nil
    var color: Color = HX.text
    var size: CGFloat = 36
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HXOverline(label)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(HX.numeral(size)).foregroundStyle(color)
                    .contentTransition(.numericText())
                if let unit { Text(unit).font(HX.caption).foregroundStyle(HX.textDim) }
            }
            if let verdict { Text(verdict).font(HX.caption).foregroundStyle(HX.textDim).lineLimit(2) }
        }
    }
}

/// Readiness ring: score in the middle, arc coloured by band.
struct HXRing: View {
    let value: Double        // 0…1
    let color: Color
    var lineWidth: CGFloat = 10
    var body: some View {
        ZStack {
            Circle().stroke(HX.raised, lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: value)
        }
    }
}

/// Primary action button in volt.
struct HXPrimaryButtonStyle: ButtonStyle {
    var color: Color = HX.volt
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(HX.headline)
            .foregroundStyle(HX.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(color))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct HXGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(HX.headline)
            .foregroundStyle(HX.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(HX.raised))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Screen container with the dark ink background and large title.
struct HXScreen<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HX.gap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(HX.text)
                    if let subtitle { Text(subtitle).font(HX.body).foregroundStyle(HX.textDim) }
                }
                .padding(.top, 8)
                content()
            }
            .padding(.horizontal, HX.screenPad)
            .padding(.bottom, 110)
        }
        .background(HX.ink.ignoresSafeArea())
        .scrollIndicators(.hidden)
    }
}

struct HXPill: View {
    let text: String
    var color: Color = HX.textDim
    var body: some View {
        Text(text).font(HX.caption.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}
