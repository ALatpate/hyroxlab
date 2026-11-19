import SwiftUI
import Combine
import UIKit

/// Where the keyboard is, and the field being typed in.
///
/// SwiftUI moves a page or a sheet out of the keyboard's way by itself. Luma does not replace that.
/// It hides its own tab bar while a keyboard is up (the bar floats over the page, so it rose with the
/// keyboard and sat on top of whatever was being typed in), and it keeps two checks behind SwiftUI:
/// `lumaKeyboardRoom` looks at where a page's foot really lies on the screen once SwiftUI has had its
/// turn and makes up whatever the keyboard still covers, and the field being typed in is scrolled
/// into view if it is still hidden. Where SwiftUI has done the whole job, both come to nothing.
@MainActor
final class LumaKeyboard: ObservableObject {
    static let shared = LumaKeyboard()

    /// How far the keyboard reaches above the bottom safe area of the window; 0 while it is away.
    @Published private(set) var lift: CGFloat = 0
    var isUp: Bool { lift > 0 }
    /// Counts the times the keyboard has come to rest, up or away: a moment to look again at what it covers.
    @Published private(set) var rested = 0

    /// The text field or text view being typed in.
    private weak var field: UIView?
    private var bag: Set<AnyCancellable> = []

    private init() {
        let center = NotificationCenter.default
        center.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .sink { [weak self] note in self?.moved(note, hiding: false) }
            .store(in: &bag)
        center.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] note in self?.moved(note, hiding: true) }
            .store(in: &bag)
        // Once the keyboard has come to rest, and whenever typing moves to another field under it.
        center.publisher(for: UIResponder.keyboardDidShowNotification)
            .sink { [weak self] _ in
                self?.rested += 1
                self?.reveal()
            }
            .store(in: &bag)
        center.publisher(for: UIResponder.keyboardDidHideNotification)
            .sink { [weak self] _ in self?.rested += 1 }
            .store(in: &bag)
        center.publisher(for: UITextField.textDidBeginEditingNotification)
            .merge(with: center.publisher(for: UITextView.textDidBeginEditingNotification))
            .sink { [weak self] note in
                self?.field = note.object as? UIView
                // After the layout that follows the change of focus.
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    guard let self, self.isUp else { return }
                    self.reveal()
                }
            }
            .store(in: &bag)
    }

    private func moved(_ note: Notification, hiding: Bool) {
        let info = note.userInfo ?? [:]
        let duration = (info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        var target: CGFloat = 0
        if !hiding, let end = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect, let window = Self.window {
            // The keyboard's frame is given in the screen's coordinates.
            let frame = window.convert(end, from: nil)
            let overlap = max(0, window.bounds.maxY - frame.minY)
            target = max(0, overlap - window.safeAreaInsets.bottom)
        }
        // A bar a few points high (a hardware keyboard's) is not worth moving a screen for.
        if target < 60 { target = 0 }
        guard abs(target - lift) > 0.5 else { return }
        if duration > 0 {
            withAnimation(.easeOut(duration: duration)) { lift = target }
        } else {
            lift = target
        }
    }

    private static var window: UIWindow? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
        return windows.first { $0.isKeyWindow } ?? windows.first
    }

    /// Scrolls the field being typed in into view, when a scroll view holds it and the keyboard, or
    /// the foot of that scroll view, hides it. Does nothing when the field can already be seen.
    private func reveal() {
        guard let field, let window = field.window else { return }
        var holder: UIView? = field.superview
        var scroll: UIScrollView?
        while let view = holder {
            if let candidate = view as? UIScrollView, candidate.isScrollEnabled,
               candidate.contentSize.height > candidate.bounds.height || candidate.alwaysBounceVertical {
                scroll = candidate
                break
            }
            holder = view.superview
        }
        guard let scroll else { return }
        let keyboardTop = window.bounds.maxY - window.safeAreaInsets.bottom - lift
        let frame = scroll.convert(scroll.bounds, to: window)
        let seenTo = min(frame.maxY - scroll.adjustedContentInset.bottom, keyboardTop)
        let seenFrom = frame.minY + scroll.adjustedContentInset.top
        let place = field.convert(field.bounds, to: window)
        var offset = scroll.contentOffset
        if place.maxY + 18 > seenTo {
            offset.y += place.maxY + 18 - seenTo
        } else if place.minY - 12 < seenFrom {
            offset.y -= seenFrom - (place.minY - 12)
        } else {
            return
        }
        let lowest = -scroll.adjustedContentInset.top
        let highest = max(lowest, scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height)
        offset.y = min(max(offset.y, lowest), highest)
        guard abs(offset.y - scroll.contentOffset.y) > 1 else { return }
        scroll.setContentOffset(offset, animated: true)
    }

    /// Puts the keyboard away.
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// Keeps what it wraps clear of the keyboard: whatever of it the keyboard still covers, once SwiftUI
/// has moved things, is added as room at its foot.
///
/// What is covered is read from where the view's foot actually lies on the screen, not worked out
/// from heights before and after: SwiftUI and this both hear of the keyboard at the same moment, in
/// no fixed order, and a "before" taken a moment late doubled the move.
private struct LumaKeyboardRoom: ViewModifier {
    @ObservedObject private var keyboard = LumaKeyboard.shared
    @State private var extra: CGFloat = 0
    @State private var probe = FootProbe.Box()

    func body(content: Content) -> some View {
        content
            .padding(.bottom, extra)
            // Behind the padded view, so it has that view's frame: the padding is inside what it measures.
            .background(FootProbe(box: probe) { settleSoon() })
            .onChange(of: keyboard.lift) { _, _ in settleSoon() }
            .onChange(of: keyboard.rested) { _, _ in settleSoon() }
    }

    /// On the next turn of the run loop: after SwiftUI's own move for the keyboard has landed, and
    /// never in the middle of a view update.
    private func settleSoon() {
        Task { @MainActor in settle() }
    }

    private func settle() {
        var covered: CGFloat = 0
        if keyboard.lift > 0, let view = probe.view, let window = view.window {
            let foot = view.convert(view.bounds, to: window).maxY
            let keyboardTop = window.bounds.maxY - window.safeAreaInsets.bottom - keyboard.lift
            covered = max(0, foot - keyboardTop)
        }
        guard abs(covered - extra) > 0.5 else { return }
        withAnimation(.easeOut(duration: 0.22)) { extra = covered }
    }
}

/// A clear view with no size of its own, placed behind another to say where that one lies on screen.
private struct FootProbe: UIViewRepresentable {
    final class Box {
        weak var view: UIView?
    }

    final class Probe: UIView {
        var onLayout: (() -> Void)?

        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?()
        }
    }

    let box: Box
    let onLayout: () -> Void

    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onLayout = onLayout
        box.view = view
        return view
    }

    func updateUIView(_ view: Probe, context: Context) {
        view.onLayout = onLayout
        box.view = view
    }
}

extension View {
    /// Keeps a page or sheet clear of the keyboard, whether or not SwiftUI has moved it.
    func lumaKeyboardRoom() -> some View { modifier(LumaKeyboardRoom()) }
}
