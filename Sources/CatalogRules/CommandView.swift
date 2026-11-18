import CatalogJSON

/// A command, flag command or serial command of a command set, as the rules read it.
struct CommandView {
  let json: JSONValue

  var name: String { json.text("name") ?? "" }
  var effect: String { json.text("effect") ?? "" }
  var idempotent: Bool { json["idempotent"] == .bool(true) }
  var command1: String? { json.text("command1") }
  var command2: String? { json.text("command2") }
  var number: String { json.text("number") ?? "" }
  var guardKind: String? { json.text("guard") }
  var isPerButton: Bool { json.isSet("perButton") }
  var integrity: String? { json.text("integrity") }

  /// The effect and idempotent flag together, which two entries one message can match must share.
  var behavior: Behavior { Behavior(effect: effect, idempotent: idempotent) }

  /// The bytes the command fixes, in file order.
  var fixedBytes: [FixedByte] {
    json.list("fixed").map { FixedByte(position: $0.number("position") ?? 0, value: $0.text("value") ?? "") }
  }

  /// The fields that take a value from the caller.
  var parameters: [JSONValue] { json.list("parameters") }

  /// The positions the parameters fill.
  var parameterPositions: [Int] { parameters.flatMap(Self.positions(of:)) }

  /// The positions a field names with `byte` or `bytes`.
  static func positions(of field: JSONValue) -> [Int] {
    if let byte = field.number("byte") {
      return [byte]
    }
    return field.list("bytes").compactMap(\.integer)
  }
}

/// One byte a command fixes.
struct FixedByte {
  let position: Int
  let value: String
}

/// The effect of a command and whether sending it twice leaves the device as sending it once.
struct Behavior: Equatable {
  let effect: String
  let idempotent: Bool
}

/// What a message byte can hold when the rules ask whether one message can match two commands.
enum ByteMatch: Equatable {
  case any
  case fixed(String)

  /// Whether one byte can satisfy both.
  func agrees(with other: ByteMatch) -> Bool {
    switch (self, other) {
    case (.any, _), (_, .any): true
    case (.fixed(let left), .fixed(let right)): left == right
    }
  }
}

extension Array where Element == FixedByte {
  /// The bytes as a key that is equal for two commands that fix the same bytes.
  var frameKey: String {
    sorted { $0.position != $1.position ? $0.position < $1.position : codePointPrecedes($0.value, $1.value) }
      .map { "\($0.position)=\($0.value)" }.joined(separator: ";")
  }
}
