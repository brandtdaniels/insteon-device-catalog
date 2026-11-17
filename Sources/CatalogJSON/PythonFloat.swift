/// Formats floating-point numbers the way Python's `repr(float)` does.
///
/// Both languages print the shortest digits that read back as the same value. They differ in
/// where they switch to exponent notation, so the digits are taken from Swift and laid out by
/// Python's rule: fixed notation when the decimal exponent is from -4 up to 15, exponent
/// notation otherwise.
public enum PythonFloat {
  /// The text Python prints for `value`, or `nil` when the value is not finite.
  public static func format(_ value: Double) -> String? {
    guard value.isFinite else { return nil }
    let sign = value.sign == .minus ? "-" : ""
    let (digits, pointPosition) = decimalDigits(of: value.magnitude)
    guard !digits.isEmpty else { return sign + "0.0" }

    let exponent = pointPosition - 1
    if (-4..<16).contains(exponent) {
      return sign + fixed(digits: digits, pointPosition: pointPosition)
    }
    return sign + scientific(digits: digits, exponent: exponent)
  }

  /// The significant digits of `magnitude` with no leading or trailing zeros, and the number of
  /// digits that sit before the decimal point (zero or negative when the value is below 1).
  private static func decimalDigits(of magnitude: Double) -> (digits: [Character], pointPosition: Int) {
    let text = magnitude.description
    let parts = text.split(separator: "e", maxSplits: 1)
    let exponent = parts.count == 2 ? Int(parts[1])! : 0
    let mantissa = parts[0]
    let integerPart = mantissa.prefix { $0 != "." }
    var digits = Array(mantissa.filter { $0 != "." })
    var pointPosition = integerPart.count + exponent
    while digits.first == "0" {
      digits.removeFirst()
      pointPosition -= 1
    }
    while digits.last == "0" {
      digits.removeLast()
    }
    return (digits, pointPosition)
  }

  private static func fixed(digits: [Character], pointPosition: Int) -> String {
    if pointPosition <= 0 {
      return "0." + String(repeating: "0", count: -pointPosition) + String(digits)
    }
    if pointPosition >= digits.count {
      return String(digits) + String(repeating: "0", count: pointPosition - digits.count) + ".0"
    }
    return String(digits[..<pointPosition]) + "." + String(digits[pointPosition...])
  }

  private static func scientific(digits: [Character], exponent: Int) -> String {
    var text = String(digits[0])
    if digits.count > 1 {
      text += "." + String(digits[1...])
    }
    let magnitude = String(abs(exponent))
    return text + "e" + (exponent < 0 ? "-" : "+") + (magnitude.count < 2 ? "0" : "") + magnitude
  }
}
