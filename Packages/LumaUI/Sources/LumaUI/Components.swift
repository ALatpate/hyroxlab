import SwiftUI
import LumaCore
@_exported import LumaKit
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Haptics

@MainActor
public enum LumaHaptics {
    public static func tap() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
    public static func thud() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
    public static func select() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
    public static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    public static func warn() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
}

// MARK: - Backdrop and screen scaffolds

/// The night field with one soft light spilling in from the top, tinted by the screen's tone.
struct LumaBackdrop: View {
    var tone: LumaTone = .neutral
    var strength: Double = 1

    var body: some View {
        ZStack {
            Luma.night
            RadialGradient(colors: [tone.color.opacity(0.17 * strength), tone.color.opacity(0)],
                           center: UnitPoint(x: 0.82, y: -0.08), startRadius: 0, endRadius: 440)
            RadialGradient(colors: [tone.partner.opacity(0.09 * strength), tone.partner.opacity(0)],
                           center: UnitPoint(x: 0.0, y: 0.18), startRadius: 0, endRadius: 320)
        }
        .ignoresSafeArea()
    }
}

/// A top-level tab screen: large title, optional trailing controls, scrolling content.
struct LumaTabScreen<Trailing: View, Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var tone: LumaTone = .neutral
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            LumaBackdrop(tone: tone)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center, spacing: 12) {
                            if let subtitle {
                                Text(subtitle).font(LumaFont.label(12)).foregroundStyle(Luma.mist)
                            }
                            Spacer(minLength: 8)
                            trailing()
                        }
                        Text(title).font(LumaFont.title(30)).foregroundStyle(Luma.frost).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .padding(.top, 6)
                    content()
                }
                .padding(.horizontal, Luma.gutter)
                .padding(.bottom, 130)
                .offset(y: -LumaLaunch.scrollOffset)
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .top) {
            // Keeps the status bar legible when content scrolls beneath it.
            LinearGradient(stops: [.init(color: Luma.night.opacity(0.96), location: 0), .init(color: Luma.night.opacity(0.88), location: 0.72),
                                   .init(color: Luma.night.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom)
                .frame(height: 16)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// A pushed detail screen: the system back gesture and a compact title, over the same backdrop.
struct LumaDetailScreen<Content: View>: View {
    let title: String
    var tone: LumaTone = .neutral
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            LumaBackdrop(tone: tone)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) { content() }
                    .padding(.horizontal, Luma.gutter)
                    .padding(.top, 4)
                    .padding(.bottom, 130)
                    .offset(y: -LumaLaunch.scrollOffset)
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(title).font(LumaFont.heading(15)).foregroundStyle(Luma.frost)
            }
        }
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarRole(.editor)
    }
}

// MARK: - Surfaces

/// An instrument card: a dark panel lit from above, with a hairline that catches the light.
struct LumaCard<Content: View>: View {
    var padding: CGFloat = 18
    var tint: Color? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LumaPanel(tint: tint))
    }
}

struct LumaPanel: View {
    var tint: Color? = nil
    var radius: CGFloat = Luma.radiusCard

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape.fill(Luma.deep)
            shape.fill(LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.015)], startPoint: .top, endPoint: .bottom))
            if let tint {
                shape.fill(RadialGradient(colors: [tint.opacity(0.2), tint.opacity(0)], center: .topTrailing, startRadius: 0, endRadius: 260))
            }
            shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom),
                               lineWidth: 1)
        }
    }
}

// MARK: - Text roles

struct LumaLabel: View {
    let text: String
    var color: Color = Luma.mist
    init(_ text: String, color: Color = Luma.mist) { self.text = text; self.color = color }
    var body: some View { Text(text).font(LumaFont.label(11)).foregroundStyle(color) }
}

/// A section heading with an optional trailing action.
struct LumaSection: View {
    let title: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(LumaFont.heading(17)).foregroundStyle(Luma.frost)
            Spacer()
            if let action, let onAction {
                Button(action: onAction) {
                    Text(action).font(LumaFont.body(14, .medium)).foregroundStyle(Luma.mist)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 6)
    }
}

/// A number that counts up to its value when it appears or changes.
struct RollingNumber: View, Animatable {
    var value: Double
    var format: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View { Text(format(value)) }
}

/// A number with its unit, set like a clock: big compressed digits, a small unit on the baseline.
struct LumaFigure: View {
    let value: Double?
    var decimals: Int = 0
    var unit: String = ""
    var size: CGFloat = 44
    var color: Color = Luma.frost
    var signed: Bool = false
    /// Thousands separators (steps, energy).
    var grouped: Bool = false
    @State private var shown: Double = 0

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            if let value {
                RollingNumber(value: shown) { v in
                    if grouped { return LFormat.grouped(v) }
                    return signed ? String(format: "%+.\(decimals)f", v) : String(format: "%.\(decimals)f", v)
                }
                .font(LumaFont.numeral(size))
                .foregroundStyle(color)
                .onAppear { withAnimation(.easeOut(duration: 0.9)) { shown = value } }
                .onChange(of: value) { _, new in withAnimation(.easeOut(duration: 0.5)) { shown = new } }
            } else {
                Text("–").font(LumaFont.numeral(size)).foregroundStyle(Luma.smoke)
            }
            if !unit.isEmpty {
                Text(unit).font(LumaFont.body(size * 0.3, .semibold)).foregroundStyle(Luma.mist)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// Compares a value with the athlete's baseline: an arrow, the difference, and whether that is good.
struct DeltaBadge: View {
    let delta: Double?
    var decimals: Int = 0
    var unit: String = ""
    /// nil: direction carries no judgement.
    var higherIsBetter: Bool? = true
    var suffix: String = "vs baseline"

    var body: some View {
        if let d = delta {
            let flat = abs(d) < pow(10, -Double(decimals)) / 2
            let good: Bool? = flat ? nil : higherIsBetter.map { $0 == (d > 0) }
            let color: Color = good == nil ? Luma.mist : (good == true ? Luma.mint : Luma.coral)
            HStack(spacing: 4) {
                Image(systemName: flat ? "minus" : (d > 0 ? "arrow.up.right" : "arrow.down.right"))
                    .font(.system(size: 10, weight: .bold))
                Text(flat ? "Level \(suffix.replacingOccurrences(of: "vs", with: "with"))" : "\(String(format: "%+.\(decimals)f", d))\(unit) \(suffix)")
                    .font(LumaFont.body(12, .medium))
            }
            .foregroundStyle(color)
        }
    }
}

// MARK: - Controls

struct LumaPill: View {
    let text: String
    var color: Color = Luma.mist
    var filled: Bool = false
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .bold)) }
            Text(text).font(LumaFont.body(12, .semibold))
        }
        .foregroundStyle(filled ? Luma.ink : color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(filled ? color : color.opacity(0.14)))
    }
}

struct LumaPrimaryButtonStyle: ButtonStyle {
    var color: Color = Luma.volt
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LumaFont.heading(compact ? 14 : 16))
            .foregroundStyle(Luma.ink)
            .padding(.vertical, compact ? 11 : 16)
            .padding(.horizontal, compact ? 16 : 20)
            .frame(maxWidth: compact ? nil : .infinity)
            .background(RoundedRectangle(cornerRadius: compact ? 14 : 18, style: .continuous).fill(color))
            .shadow(color: color.opacity(configuration.isPressed ? 0.1 : 0.35), radius: 14, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct LumaSecondaryButtonStyle: ButtonStyle {
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LumaFont.heading(compact ? 14 : 16))
            .foregroundStyle(Luma.frost)
            .padding(.vertical, compact ? 11 : 16)
            .padding(.horizontal, compact ? 16 : 20)
            .frame(maxWidth: compact ? nil : .infinity)
            .background(RoundedRectangle(cornerRadius: compact ? 14 : 18, style: .continuous).fill(Luma.raised))
            .overlay(RoundedRectangle(cornerRadius: compact ? 14 : 18, style: .continuous).strokeBorder(Luma.line, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// One of a row of equal-width shortcuts: an icon and a short label on one line.
struct LumaQuickAction: View {
    let symbol: String
    let title: String
    var tint: Color = Luma.frost
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
                Text(title).font(LumaFont.body(13.5, .semibold)).foregroundStyle(Luma.frost).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Luma.raised))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Luma.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// A round icon button used in headers.
struct LumaIconButton: View {
    let symbol: String
    var color: Color = Luma.frost
    var badge: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Color.white.opacity(0.07)))
                .overlay(Circle().strokeBorder(Luma.line, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if badge { Circle().fill(Luma.volt).frame(width: 9, height: 9).offset(x: -2, y: 2) }
                }
        }
        .buttonStyle(.plain)
    }
}

/// A segmented control whose highlight slides between options.
struct LumaSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    var tint: Color = Luma.frost
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let isOn = option.value == selection
                Button {
                    LumaHaptics.select()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(LumaFont.body(13, .semibold))
                        .foregroundStyle(isOn ? Luma.ink : Luma.mist)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if isOn {
                                Capsule().fill(tint).matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Luma.line, lineWidth: 1))
    }
}

/// A toggleable chip (check-in tags, filters).
struct LumaChip: View {
    let title: String
    var symbol: String? = nil
    let isOn: Bool
    var tint: Color = Luma.volt
    let action: () -> Void

    var body: some View {
        Button {
            LumaHaptics.select()
            action()
        } label: {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)) }
                Text(title).font(LumaFont.body(13, .medium))
            }
            .foregroundStyle(isOn ? Luma.ink : Luma.frost)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(isOn ? tint : Color.white.opacity(0.06)))
            .overlay(Capsule().strokeBorder(isOn ? Color.clear : Luma.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// A list row inside a grouped panel.
struct LumaRow<Trailing: View>: View {
    let symbol: String?
    var symbolColor: Color = Luma.frost
    let title: String
    var subtitle: String? = nil
    var chevron: Bool = false
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 13) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(symbolColor)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(symbolColor.opacity(0.13)))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                if let subtitle {
                    Text(subtitle).font(LumaFont.body(12.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing()
            if chevron {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Luma.smoke)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }
}

extension LumaRow where Trailing == EmptyView {
    init(symbol: String?, symbolColor: Color = Luma.frost, title: String, subtitle: String? = nil, chevron: Bool = false) {
        self.init(symbol: symbol, symbolColor: symbolColor, title: title, subtitle: subtitle, chevron: chevron) { EmptyView() }
    }
}

/// A panel that stacks rows with hairline dividers between them.
struct LumaGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        _VariadicView.Tree(LumaGroupLayout()) { content() }
            .background(LumaPanel(radius: 22))
    }
}

private struct LumaGroupLayout: _VariadicView_MultiViewRoot {
    @ViewBuilder
    func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        VStack(spacing: 0) {
            ForEach(children) { child in
                child
                if child.id != last {
                    Rectangle().fill(Luma.line).frame(height: 1).padding(.leading, 16)
                }
            }
        }
    }
}

struct LumaDivider: View {
    var body: some View { Rectangle().fill(Luma.line).frame(height: 1) }
}

/// What an empty state should do: say what is missing and offer the way to fill it.
struct LumaEmpty: View {
    let symbol: String
    let title: String
    let message: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Luma.mist)
                .frame(width: 60, height: 60)
                .background(Circle().fill(Color.white.opacity(0.06)))
            Text(title).font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
            Text(message).font(LumaFont.body(14)).foregroundStyle(Luma.mist).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let action, let onAction {
                Button(action, action: onAction).buttonStyle(LumaPrimaryButtonStyle(compact: true)).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
    }
}

/// A horizontal progress bar with an optional target tick.
struct LumaBar: View {
    var value: Double
    var total: Double
    var color: Color
    var height: CGFloat = 8
    @State private var shown: Double = 0

    var body: some View {
        GeometryReader { geo in
            let frac = total > 0 ? min(1, max(0, shown / total)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(LinearGradient(colors: [color.opacity(0.75), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geo.size.width * frac))
                    .opacity(frac > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .onAppear { withAnimation(.easeOut(duration: 0.8)) { shown = value } }
        .onChange(of: value) { _, new in withAnimation(.easeOut(duration: 0.4)) { shown = new } }
    }
}

/// A compact tile: label, figure, and one line of context.
struct LumaTile<Footer: View>: View {
    let label: String
    let value: Double?
    var decimals: Int = 0
    var unit: String = ""
    var color: Color = Luma.frost
    var symbol: String? = nil
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(color) }
                LumaLabel(label)
                Spacer(minLength: 0)
            }
            LumaFigure(value: value, decimals: decimals, unit: unit, size: 36, color: Luma.frost)
            footer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LumaPanel(radius: 22))
    }
}

/// A text field styled for the night field.
struct LumaField: View {
    let title: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var axis: Axis = .horizontal

    var body: some View {
        TextField(title, text: $text, prompt: Text(title).foregroundStyle(Luma.smoke), axis: axis)
            .font(LumaFont.body(16))
            .foregroundStyle(Luma.frost)
            .keyboardType(keyboard)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: Luma.radiusControl, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: Luma.radiusControl, style: .continuous).strokeBorder(Luma.line, lineWidth: 1))
    }
}

/// Sheet chrome: a title row with a close button over the night field.
struct LumaSheet<Content: View>: View {
    let title: String
    var tone: LumaTone = .neutral
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            LumaBackdrop(tone: tone, strength: 0.8)
            VStack(spacing: 0) {
                HStack {
                    Text(title).font(LumaFont.heading(18)).foregroundStyle(Luma.frost)
                    Spacer()
                    LumaIconButton(symbol: "xmark") { dismiss() }
                }
                .padding(.horizontal, Luma.gutter)
                .padding(.top, 18)
                .padding(.bottom, 10)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) { content() }
                        .padding(.horizontal, Luma.gutter)
                        .padding(.bottom, 40)
                        .offset(y: -LumaLaunch.scrollOffset)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Luma.night)
    }
}

// MARK: - Formatting helpers used across screens

enum LumaText {
    static func dayTitle(_ key: String, today: String) -> String {
        if key == today { return "Today" }
        if key == LDate.adding(-1, to: today) { return "Yesterday" }
        if key == LDate.adding(1, to: today) { return "Tomorrow" }
        guard let d = LDate.date(key) else { return key }
        return d.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    static func shortDay(_ key: String) -> String {
        guard let d = LDate.date(key) else { return key }
        return d.formatted(.dateTime.day().month(.abbreviated))
    }

    static func weekdayLetter(_ key: String) -> String {
        guard let d = LDate.date(key) else { return "" }
        return String(d.formatted(.dateTime.weekday(.narrow)).prefix(1))
    }

    static func time(_ ts: Double) -> String {
        Date(timeIntervalSince1970: ts).formatted(date: .omitted, time: .shortened)
    }

    static func duration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func pace(_ sPerKm: Double?) -> String {
        guard let p = sPerKm, p.isFinite, p > 0, p < 3600 else { return "–:––" }
        let s = Int(p.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func km(_ metres: Double, decimals: Int = 2) -> String { String(format: "%.\(decimals)f", metres / 1000) }

    /// Facts on one line, separated by dots. A value and its unit stay together when the line wraps.
    static func line(_ parts: [String]) -> String {
        parts.filter { !$0.isEmpty }.map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") }.joined(separator: " · ")
    }

    static func greeting(_ date: Date = Date()) -> String {
        let h = Calendar.current.component(.hour, from: date)
        return h < 5 ? "Late night" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
    }
}

extension LSportKind {
    var tone: LumaTone {
        switch self {
        case .run, .hyrox: return .run
        case .strength: return .strain
        case .conditioning, .row, .cycle, .swim, .other: return .heart
        case .walk, .mobility: return .fuel
        }
    }
}

extension LMetric {
    var tone: LumaTone {
        switch self {
        case .recovery: return .recovery
        case .strain, .activeKcal, .steps: return .strain
        case .sleepScore, .sleepHours, .deepMin, .remMin, .sleepEfficiency: return .sleep
        case .hrv: return .hrv
        case .restingHR: return .heart
        case .respRate, .skinTempDev, .spo2: return .stress
        }
    }
}
