import SwiftUI
import Combine
import UIKit

/// Where the keyboard is, and the field being typed in.
///
/// SwiftUI moves content out of the keyboard's way by itself in most places and not in all of them:
/// a field that grows to several lines at the foot of a screen is one it leaves covered. Luma does
/// not replace what SwiftUI does. It measures how much of a screen the keyboard still covers after
/// SwiftUI has had its turn and makes up the difference (`lumaKeyboardRoom`), then scrolls the field
/// being typed in into view if it is still hidden. Where SwiftUI has done the whole job, both come to
/// nothing.
@MainActor
final class LumaKeyboard: ObservableObject {
    static let shared = LumaKeyboard()

    /// How far the keyboard reaches above the bottom safe area of the window; 0 while it is away.
    @Published private(set) var lift: CGFloat = 0
    var isUp: Bool { lift > 0 }

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
            .sink { [weak self] _ in self?.reveal() }
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

/// Keeps what it wraps clear of the keyboard: whatever room SwiftUI has not already made is added at
/// the foot. For a view whose foot sits at the foot of the screen (a page, a sheet).
private struct LumaKeyboardRoom: ViewModifier {
    @ObservedObject private var keyboard = LumaKeyboard.shared
    /// The height of the wrapped view while the keyboard is away, and its height now.
    @State private var resting: CGFloat = 0
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(.bottom, extra)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { measured(geo.size.height) }
                        .onChange(of: geo.size.height) { _, new in measured(new) }
                }
            )
            .onChange(of: keyboard.lift) { _, lift in if lift == 0 { resting = height } }
    }

    /// What the keyboard still covers: how far it reaches up, less the height this view has already
    /// given up to it.
    private var extra: CGFloat {
        guard keyboard.lift > 0, resting > 0 else { return 0 }
        let given = max(0, resting - height)
        return max(0, keyboard.lift - given)
    }

    private func measured(_ new: CGFloat) {
        height = new
        if keyboard.lift == 0 { resting = new }
    }
}

extension View {
    /// Keeps a page or sheet clear of the keyboard, whether or not SwiftUI has moved it.
    func lumaKeyboardRoom() -> some View { modifier(LumaKeyboardRoom()) }
}
