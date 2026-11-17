import CatalogJSON

/// Rules for the serial commands of a modem's command set.
enum SerialRules {
  /// What a serial command's payload bytes can hold: a fixed value, or any value for a parameter.
  /// A byte that is neither is missing from the result.
  static func payload(_ command: CommandView) -> [Int: ByteMatch] {
    var found: [Int: ByteMatch] = [:]

    for position in command.parameterPositions {
      found[position] = .any
    }

    for byte in command.fixedBytes {
      found[byte.position] = .fixed(byte.value)
    }

    return found
  }

  /// The length of the payload: the highest byte position it names.
  static func payloadLength(_ command: CommandView) -> Int {
    payload(command).keys.max() ?? 0
  }

  /// Whether one serial frame can match both commands.
  static func overlap(_ command: CommandView, _ other: CommandView) -> Bool {
    let mine = payload(command), theirs = payload(other)

    return command.number == other.number
      && mine.allSatisfy { position, match in theirs[position].map { match.agrees(with: $0) } ?? true }
  }

  /// Whether every serial frame that matches `other` also matches `command`.
  static func covers(_ command: CommandView, _ other: CommandView) -> Bool {
    let mine = payload(command), theirs = payload(other)

    return command.number == other.number
      && mine.allSatisfy { position, match in match == .any || match == theirs[position] }
  }

  /// Reports a serial command whose number carries a device message, whose values name no payload
  /// byte or fill one twice, whose payload has a byte nothing fills, or whose reply reads a byte twice.
  static func commandProblems(_ command: CommandView, fields: FieldRules) -> [String] {
    let owner = "the \(command.name) serial command"
    var found: [String] = []

    if command.number == "0x61" || command.number == "0x62" {
      found.append("\(owner) has number \(command.number), which carries a device message and so isn't an entry")
    }

    for field in command.parameters {
      found += fields.problems(field, owner: owner, extendedMessage: true)
    }

    let filled = FieldRules.positions(command.parameters) + command.fixedBytes.map { ($0.position, 0xFF) }

    if FieldRules.overlaps(filled) {
      found.append("\(owner): it fills a payload byte twice")
    }

    let bytes = payload(command)
    for position in stride(from: 1, through: payloadLength(command), by: 1) where bytes[position] == nil {
      found.append("\(owner): payload byte \(position) is neither fixed nor a parameter")
    }

    if let reply = command.json["reply"] {
      for field in reply.elements {
        found += fields.problems(field, owner: "\(owner)'s reply", extendedMessage: true)
      }

      if FieldRules.overlaps(FieldRules.positions(reply.elements)) {
        found.append("\(owner)'s reply reads a payload byte twice")
      }
    }

    return found
  }

  /// Reports serial commands that send the same number and fixed bytes, and commands with one
  /// number but different payload lengths, which no frame could tell apart.
  static func frameProblems(_ serial: [CommandView]) -> [String] {
    var found: [String] = []
    let keys = serial.map { "\($0.number)|\($0.fixedBytes.frameKey)" }

    if Set(keys).count != keys.count {
      found.append("two serial commands send the same number and fixed bytes")
    }

    for (index, command) in serial.enumerated() {
      for other in serial[(index + 1)...] where command.number == other.number && payloadLength(command) != payloadLength(other) {
        found.append("the \(command.name) and \(other.name) serial commands share number \(command.number) but differ in payload length")
      }
    }

    return found
  }
}
