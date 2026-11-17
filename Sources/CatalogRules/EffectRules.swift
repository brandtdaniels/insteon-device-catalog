import CatalogJSON

/// Rules that hold a command's effect and idempotent to what the protocol and the rest of the
/// command set say about it.
enum EffectRules {
  /// The problems in the effect and idempotent of a command set's commands, in the order they are
  /// found: each command alone, serial commands that one frame can match, group type actions and
  /// state reads, flag and value commands, Set Operating Flags senders that share a cmd2, and
  /// extended commands that one message can match.
  static func problems(in commandSet: JSONValue) -> [String] {
    var problems: [String] = []
    let flagCommands = commandSet.list("flagCommands").map(CommandView.init)
    let standard = commandSet.list("standardCommands").map(CommandView.init)
    let extended = commandSet.list("extendedCommands").map(CommandView.init)
    let entries: [(kind: Kind, commands: [CommandView])] = [(.flag, flagCommands), (.standard, standard), (.extended, extended)]

    var effects: [String: String] = [:]
    for command in entries.flatMap(\.commands) {
      effects[command.name] = command.effect
    }

    for (kind, commands) in entries {
      for command in commands {
        problems += commandProblems(command, kind: kind)
      }
    }

    let serial = commandSet.list("serialCommands").map(CommandView.init)
    problems += serialCommandProblems(serial)
    problems += overlappingSerialProblems(serial)
    problems += groupTypeProblems(in: commandSet, effects: effects)
    problems += flagAndValueProblems(in: commandSet, effects: effects)
    problems += setOperatingFlagsProblems(in: commandSet, flagCommands: flagCommands, standard: standard, extended: extended)
    problems += overlappingExtendedProblems(extended)

    return problems
  }

  enum Kind {
    case flag, standard, extended
  }

  /// The problems of one flag, standard or extended command taken alone: never sent without being
  /// destructive, Set Operating Flags or a write that is readOnly, and readOnly that isn't idempotent.
  private static func commandProblems(_ command: CommandView, kind: Kind) -> [String] {
    var problems: [String] = []
    let label = "the \(command.name) command"
    let setsFlags = kind == .flag || command.command1 == "0x20"
    var fixed: [Int: String] = [:]
    for byte in command.fixedBytes {
      fixed[byte.position] = byte.value
    }
    let given = Set(command.parameterPositions)
    let isExtended = kind == .extended
    let selector = (fixed[2] ?? "0x00") != "0x00" || given.contains(2)
    let extendedSet = isExtended && command.command1 == "0x2E" && command.command2 == "0x00" && selector
    let propertiesWrite = isExtended && command.command1 == "0x2E" && command.command2 == "0x01" && fixed[1] == "0x02"
    let databaseWrite = isExtended && command.command1 == "0x2F" && (fixed[2] == "0x02" || given.contains(2))

    if command.guardKind == "never", command.effect != "destructive" {
      problems.append("\(label) is never sent, so its effect must be destructive")
    }

    if command.effect == "readOnly" {
      if setsFlags {
        problems.append("\(label) is Set Operating Flags, which is never readOnly")
      } else if extendedSet {
        problems.append("\(label) is an extended Set, which is never readOnly")
      } else if propertiesWrite {
        problems.append("\(label) writes properties (cmd1 0x2E, cmd2 0x01, D1 0x02), which is never readOnly")
      } else if databaseWrite {
        problems.append("\(label) writes with cmd1 0x2F and D2 0x02, which is never readOnly")
      }

      if !command.idempotent {
        problems.append("\(label) is readOnly, so it must be idempotent")
      }
    }

    return problems
  }

  private static func serialCommandProblems(_ serial: [CommandView]) -> [String] {
    var problems: [String] = []

    for command in serial {
      let label = "the \(command.name) serial command"

      if command.guardKind == "never", command.effect != "destructive" {
        problems.append("\(label) is never sent, so its effect must be destructive")
      }

      if command.effect == "readOnly", !command.idempotent {
        problems.append("\(label) is readOnly, so it must be idempotent")
      }
    }

    return problems
  }

  /// Serial commands one frame can match: the same number and no fixed byte that differs.
  private static func overlappingSerialProblems(_ serial: [CommandView]) -> [String] {
    var problems: [String] = []

    for (index, command) in serial.enumerated() {
      for other in serial[(index + 1)...] {
        if command.behavior == other.behavior || !SerialRules.overlap(command, other) {
          continue
        }

        if command.effect == "readOnly", SerialRules.covers(command, other) {
          problems.append("the \(command.name) serial command is readOnly, but it matches every frame the \(other.name) serial command does")
        } else if other.effect == "readOnly", SerialRules.covers(other, command) {
          problems.append("the \(other.name) serial command is readOnly, but it matches every frame the \(command.name) serial command does")
        } else {
          problems.append("the \(command.name) serial command and the \(other.name) serial command can match the same frame, so they need the same effect and idempotent")
        }
      }
    }

    return problems
  }

  /// Actions must be actuation and state reads readOnly.
  private static func groupTypeProblems(in commandSet: JSONValue, effects: [String: String]) -> [String] {
    var problems: [String] = []

    for groupType in commandSet.list("groupTypes") {
      let label = "the \(groupType.text("name") ?? "") group type"

      for action in groupType.list("actions") {
        let command = action.text("command") ?? ""

        if (effects[command] ?? "actuation") != "actuation" {
          problems.append("\(label)'s \(action.text("name") ?? "") action names \(pythonRepr(command)), which isn't actuation")
        }
      }

      if let state = groupType["state"] {
        let command = state.text("command") ?? ""

        if (effects[command] ?? "readOnly") != "readOnly" {
          problems.append("\(label) reads its state with \(pythonRepr(command)), which isn't readOnly")
        }
      }
    }

    return problems
  }

  /// A flag's on and off commands and a value's write command must be configuration.
  private static func flagAndValueProblems(in commandSet: JSONValue, effects: [String: String]) -> [String] {
    var problems: [String] = []

    for flag in commandSet.list("operatingFlags") {
      for key in ["onCommand", "offCommand"] {
        guard let command = flag.text(key) else { continue }

        if (effects[command] ?? "configuration") != "configuration" {
          problems.append("the \(flag.text("name") ?? "") flag's \(key) names \(pythonRepr(command)), which isn't configuration")
        }
      }
    }

    for value in commandSet["extendedSettings"]?.list("values") ?? [] {
      guard let write = value.text("write") else { continue }

      if (effects[write] ?? "configuration") != "configuration" {
        problems.append("the \(value.text("name") ?? "") value is written by \(pythonRepr(write)), which isn't configuration")
      }
    }

    return problems
  }

  /// One sender of Set Operating Flags: what it is called, the cmd2 values it can send (`nil` for
  /// any), and the effect it has.
  private struct Sender {
    let label: String
    let sent: Set<String>?
    let behavior: Behavior
  }

  /// Set Operating Flags messages by the cmd2 each entry sends: an operating flag's on and off,
  /// which are configuration, and the flag, standard and extended commands with cmd1 0x20. A flag
  /// command goes as a standard or an extended message, so it can match entries of either kind.
  private static func setOperatingFlagsProblems(
    in commandSet: JSONValue, flagCommands: [CommandView], standard: [CommandView], extended: [CommandView]
  ) -> [String] {
    var problems: [String] = []
    let enumerations = Enumerations(commandSet)
    var senders: [Sender] = []

    for flag in commandSet.list("operatingFlags") where flag.has("on") || flag.has("off") {
      let sent = Set(["on", "off"].compactMap { flag.text($0) })
      senders.append(Sender(label: "the \(flag.text("name") ?? "") flag", sent: sent, behavior: Behavior(effect: "configuration", idempotent: true)))
    }

    for command in flagCommands {
      senders.append(Sender(label: "the \(command.name) command", sent: [command.command2 ?? ""], behavior: command.behavior))
    }

    for command in standard + extended where command.command1 == "0x20" {
      let sent: Set<String>?

      if let parameter = command.json["parameter"] {
        sent = enumerations.valueSet(named: parameter.text("enumeration"))
      } else {
        sent = [command.command2 ?? "0x00"]
      }

      senders.append(Sender(label: "the \(command.name) command", sent: sent, behavior: command.behavior))
    }

    for (index, sender) in senders.enumerated() {
      for other in senders[(index + 1)...] {
        let shared: Set<String>?

        if let sent = sender.sent, let otherSent = other.sent {
          shared = sent.intersection(otherSent)
        } else {
          shared = firstTruthy(sender.sent, other.sent)
        }

        let canMatch = shared.map { !$0.isEmpty } ?? true
        guard sender.behavior != other.behavior, canMatch else { continue }

        let location = shared.map { "cmd2 " + $0.codePointSorted().joined(separator: ", ") } ?? "any cmd2"
        problems.append("\(sender.label) and \(other.label) both send Set Operating Flags with \(location), so they need the same effect and idempotent")
      }
    }

    return problems
  }

  /// Python's `first or second` over sets and `nil`: the first when it holds something.
  private static func firstTruthy(_ first: Set<String>?, _ second: Set<String>?) -> Set<String>? {
    if let first, !first.isEmpty {
      return first
    }
    return second
  }

  /// Extended commands one message can match: an unfixed user data byte that isn't a parameter, a
  /// perButton D1 or integrity is 0x00, so commands overlap only where every byte can agree.
  private static func overlappingExtendedProblems(_ extended: [CommandView]) -> [String] {
    var problems: [String] = []

    for (index, command) in extended.enumerated() {
      for other in extended[(index + 1)...] {
        if command.behavior == other.behavior || !extendedOverlap(command, other) {
          continue
        }

        if command.effect == "readOnly", extendedCovers(command, other) {
          problems.append("the \(command.name) command is readOnly, but it matches every message the \(other.name) command does")
        } else if other.effect == "readOnly", extendedCovers(other, command) {
          problems.append("the \(other.name) command is readOnly, but it matches every message the \(command.name) command does")
        } else {
          problems.append("the \(command.name) command and the \(other.name) command can match the same extended message, so they need the same effect and idempotent")
        }
      }
    }

    return problems
  }

  /// What an extended command's user data bytes D1 through D14 can hold: a fixed value, any value
  /// (a parameter, a perButton D1 or integrity), and 0x00 for every other byte.
  static func extendedBytes(_ command: CommandView) -> [Int: ByteMatch] {
    var found = Dictionary(uniqueKeysWithValues: (1...14).map { ($0, ByteMatch.fixed("0x00")) })

    for position in command.parameterPositions {
      found[position] = .any
    }

    if command.isPerButton {
      found[1] = .any
    }

    switch command.integrity {
    case "checksum": found[14] = .any
    case "crc": found[13] = .any; found[14] = .any
    default: break
    }

    for byte in command.fixedBytes {
      found[byte.position] = .fixed(byte.value)
    }

    return found
  }

  /// Whether one extended message can match both commands.
  static func extendedOverlap(_ command: CommandView, _ other: CommandView) -> Bool {
    let mine = extendedBytes(command), theirs = extendedBytes(other)

    return command.command1 == other.command1 && command.command2 == other.command2
      && mine.allSatisfy { position, match in match.agrees(with: theirs[position] ?? .any) }
  }

  /// Whether every extended message that matches `other` also matches `command`.
  static func extendedCovers(_ command: CommandView, _ other: CommandView) -> Bool {
    let mine = extendedBytes(command), theirs = extendedBytes(other)

    return command.command1 == other.command1 && command.command2 == other.command2
      && mine.allSatisfy { position, match in match == .any || match == theirs[position] }
  }
}

/// The enumerations of a command set by name. A name used twice keeps the last.
struct Enumerations {
  private let byName: [String: JSONValue]
  /// How many enumerations the file lists, repeats included.
  let count: Int
  /// The enumerations by name in the order each name first appears, each with its last definition.
  let ordered: [JSONValue]

  init(_ commandSet: JSONValue) {
    let list = commandSet.list("enumerations")
    var byName: [String: JSONValue] = [:]
    var names: [String] = []

    for enumeration in list {
      let name = enumeration.text("name") ?? ""
      if byName[name] == nil {
        names.append(name)
      }
      byName[name] = enumeration
    }

    self.byName = byName
    self.count = list.count
    self.ordered = names.compactMap { byName[$0] }
  }

  func contains(_ name: String) -> Bool {
    byName[name] != nil
  }

  /// The values of the enumeration, or `nil` when no enumeration has this name.
  func valueSet(named name: String?) -> Set<String>? {
    guard let name, let enumeration = byName[name], enumeration.isTruthy else { return nil }
    return Set(enumeration.list("values").compactMap { $0.text("value") })
  }
}
