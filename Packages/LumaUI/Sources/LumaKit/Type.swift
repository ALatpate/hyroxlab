import SwiftUI
import CoreText
#if canImport(UIKit)
import UIKit
#endif

/// The condensed face and how text follows the phone's text size.
public enum LumaType {
    /// Whether labels and running text grow and shrink with the text size chosen in Settings. The app
    /// turns this on at launch. A widget leaves it off: its layout has no room to give.
    public static var followsTextSize = false

    private static let faces = ["BarlowCondensed-Medium", "BarlowCondensed-SemiBold", "BarlowCondensed-Bold", "BarlowCondensed-ExtraBold"]

    /// Registers the bundled fonts with this process, once. A font that cannot be found is not an
    /// error: text set in it falls back to the system face.
    static let registered: Bool = {
        let urls = fontFiles()
        for url in urls { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        return !urls.isEmpty
    }()

    /// The font files, wherever this build put the package's resource bundle: beside the code that is
    /// running, or, for a widget, in the app that contains it.
    private static func fontFiles() -> [URL] {
        let name = "LumaUI_LumaKit.bundle"
        let main = Bundle.main
        var roots: [URL] = []
        if let r = main.resourceURL { roots.append(r) }
        roots.append(main.bundleURL)
        // Luma.app/PlugIns/Widgets.appex: the app is two levels up.
        roots.append(main.bundleURL.deletingLastPathComponent().deletingLastPathComponent())
        for root in roots {
            guard let bundle = Bundle(url: root.appendingPathComponent(name)) else { continue }
            let found = faces.compactMap { bundle.url(forResource: $0, withExtension: "ttf") }
            if !found.isEmpty { return found }
        }
        return []
    }

    static func condensed(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        _ = registered
        let face: String
        switch weight {
        case .heavy, .black: face = "BarlowCondensed-ExtraBold"
        case .bold: face = "BarlowCondensed-Bold"
        case .semibold: face = "BarlowCondensed-SemiBold"
        default: face = "BarlowCondensed-Medium"
        }
        return Font.custom(face, fixedSize: size)
    }

    private static var measured: CGFloat?

    /// How much labels and running text are scaled: 1 at the standard text size, within limits the
    /// layouts hold at.
    public static var textScale: CGFloat {
        guard followsTextSize else { return 1 }
        if let measured { return measured }
        #if canImport(UIKit)
        let raw = UIFontMetrics(forTextStyle: .body).scaledValue(for: 100) / 100
        let value = min(1.2, max(0.92, raw))
        #else
        let value: CGFloat = 1
        #endif
        measured = value
        return value
    }

    /// Titles follow the text size half as far: they are already large.
    static var headingScale: CGFloat { 1 + (textScale - 1) * 0.5 }

    /// The text size was changed in Settings; the next text drawn is measured again.
    public static func textSizeChanged() { measured = nil }
}

/// Luma's timings. One set, so the same kind of change moves the same way everywhere. Each is nil when
/// Reduce Motion is on, and a change made with a nil animation simply happens.
public enum LumaMotion {
    public static var reduced: Bool {
        #if canImport(UIKit)
        return UIAccessibility.isReduceMotionEnabled
        #else
        return false
        #endif
    }

    /// A figure or a ring arriving at its value as a screen appears.
    public static var reveal: Animation? { reduced ? nil : .easeOut(duration: 0.9).delay(0.1) }
    /// A figure moving to a new value.
    public static var update: Animation? { reduced ? nil : .easeOut(duration: 0.5) }
    /// Something opening, closing or toggling in place.
    public static var quick: Animation? { reduced ? nil : .easeOut(duration: 0.2) }
    /// A selection or a card sliding to where it was put.
    public static var snap: Animation? { reduced ? nil : .spring(response: 0.32, dampingFraction: 0.82) }
    /// A control answering a press.
    public static var press: Animation? { reduced ? nil : .spring(response: 0.25, dampingFraction: 0.7) }
    /// A marker travelling to its place on a scale as a screen appears, and moving when its value changes.
    public static var settle: Animation? { reduced ? nil : .spring(response: 0.85, dampingFraction: 0.78).delay(0.2) }
    public static var resettle: Animation? { reduced ? nil : .spring(response: 0.6, dampingFraction: 0.8) }
    /// A small mark landing with a bounce: a tick, a new best.
    public static var pop: Animation? { reduced ? nil : .spring(response: 0.34, dampingFraction: 0.55) }
}
