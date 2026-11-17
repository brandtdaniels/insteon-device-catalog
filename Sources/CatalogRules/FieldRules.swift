import CatalogJSON

/// Rules for one value of a message: where it sits, what it holds and how it is encoded.
struct FieldRules {
  let enumerations: Enumerations

  /// Reports a value that names no byte or both, a byte in cmd2 where there is none, an
  /// enumeration or bits that don't fit its kind, a bad mask, range or bit list.
  func problems(_ field: JSONValue, owner: String, extendedMessage: Bool) -> [String] {
    var found: [String] = []
    let name = field.text("name") ?? ""
    let located = (field.has("byte") ? 1 : 0) + (field.has("bytes") ? 1 : 0)

    if extendedMessage, located != 1 {
      found.append("\(owner): the \(name) value needs a byte or bytes")
    }

    if !extendedMessage, located != 0 {
      found.append("\(owner): the \(name) value is in cmd2, so it can't name user data bytes")
    }

    let kind = field.text("kind") ?? "number"

    if (kind == "enumeration") != field.has("enumeration") {
      found.append("\(owner): the \(name) value names an enumeration only if its kind is enumeration")
    } else if let enumeration = field.text("enumeration"), !enumerations.contains(enumeration) {
      found.append("\(owner): the \(name) value names the enumeration \(pythonRepr(enumeration)), which doesn't exist")
    }

    if (kind == "flags") != field.has("bits") {
      found.append("\(owner): the \(name) value names bits only if its kind is flags")
    }

    if let mask = field.text("mask"), hexValue(mask) == 0 || field.has("bytes") {
      found.append("\(owner): the \(name) value's mask must pick out some bits of a single byte")
    }

    if kind != "number", ["scale", "unit", "signed"].contains(where: field.has) {
      found.append("\(owner): the \(name) value has a scale, unit or sign, which only a number can have")
    }

    if let range = field["range"], let from = range.text("from"), let through = range.text("through"), codePointPrecedes(through, from) {
      found.append("\(owner): the \(name) value's range runs backward")
    }

    let bits = field.list("bits")

    if Self.hasBadMasksOrNames(bits) {
      found.append("\(owner): the \(name) value's bits must have distinct, nonzero masks and distinct names")
    }

    if kind == "buttons", !extendedMessage {
      found.append("\(owner): the \(name) value can't be buttons in cmd2")
    }

    return found
  }

  /// Whether a list of bits or outputs has a zero mask, or repeats a mask or a name.
  static func hasBadMasksOrNames(_ bits: [JSONValue]) -> Bool {
    bits.contains { hexValue($0.text("mask") ?? "") == 0 }
      || Set(bits.map { $0.text("mask") ?? "" }).count != bits.count
      || Set(bits.map { $0.text("name") ?? "" }).count != bits.count
  }

  /// The user data bytes the values fill, each with the bits it fills.
  static func positions(_ fields: [JSONValue]) -> [(Int, Int)] {
    fields.flatMap { field in
      CommandView.positions(of: field).map { ($0, hexValue(field.text("mask") ?? "0xFF")) }
    }
  }

  /// Whether two of the filled bytes share a position and a bit.
  static func overlaps(_ filled: [(Int, Int)]) -> Bool {
    filled.enumerated().contains { index, a in filled[(index + 1)...].contains { b in a.0 == b.0 && a.1 & b.1 != 0 } }
  }

  /// The bytes a message's integrity check reserves.
  static func reserved(_ integrity: String?) -> [(Int, Int)] {
    switch integrity {
    case "checksum": [(14, 0xFF)]
    case "crc": [(13, 0xFF), (14, 0xFF)]
    default: []
    }
  }
}
