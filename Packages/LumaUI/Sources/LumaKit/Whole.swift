import Foundation

/// A whole number from a figure that may not be one. `Int(x)` stops the process when `x` is not a
/// number or is infinite, and in a widget that blanks the widget; a wrong digit is the smaller harm.
/// (The same rule as LumaCore's `LNum.int`, which this target cannot see.)
func whole<T: BinaryFloatingPoint>(_ value: T) -> Int {
    let v = Double(value)
    guard v.isFinite else { return 0 }
    return Int(max(-9.0e15, min(9.0e15, v)))
}

/// A figure that is already whole, so that one spelling serves wherever a whole number is wanted.
func whole<T: BinaryInteger>(_ value: T) -> Int { Int(clamping: value) }
