import CatalogJSON

/// Rules for a command set's messages: names used twice, standard commands and direct messages
/// that share a command, values in the wrong place or with an encoding that doesn't fit their
/// kind, user data bytes filled twice, and names of flags and enumerations that don't exist.
enum MessageRules {
  static func problems(in commandSet: JSONValue) -> [String] {
    var problems: [String] = []
    let standard = commandSet.list("standardCommands")
    let extended = commandSet.list("extendedCommands")
    let direct = commandSet.list("directMessages")
    let serial = commandSet.list("serialCommands")
    let enumerations = Enumerations(commandSet)
    let flagNames = Set(commandSet.list("operatingFlags").compactMap { $0.text("name") })

    let names = (standard + extended + direct + serial).map { $0.text("name") ?? "" }

    if Set(names).count != names.count {
      problems.append("a command or message name appears more than once")
    }

    if enumerations.ordered.count != enumerations.count {
      problems.append("an enumeration name appears more than once")
    }

    for enumeration in enumerations.ordered {
      let values = enumeration.list("values")
      let name = enumeration.text("name") ?? ""

      if Set(values.map { $0.text("value") ?? "" }).count != values.count {
        problems.append("the \(name) enumeration names a value twice")
      }

      if Set(values.map { $0.text("name") ?? "" }).count != values.count {
        problems.append("the \(name) enumeration uses a name twice")
      }
    }

    problems += sharedCommandProblems(standard, enumerations: enumerations)
    problems += extendedKeyProblems(extended)

    for item in commandSet.list("operatingFlags") + commandSet.list("flagCommands") {
      if let when = item.text("extendedWhen"), !flagNames.contains(when) {
        problems.append("the \(item.text("name") ?? "") flag names the operating flag \(pythonRepr(when)), which doesn't exist")
      }
    }

    if Set(direct.map { $0.text("command1") ?? "" }).count != direct.count {
      problems.append("two direct messages share a cmd1")
    }

    let fields = FieldRules(enumerations: enumerations)

    for command in standard {
      let owner = "the \(command.text("name") ?? "") command"

      for key in ["parameter", "reply", "followUp"] {
        if let field = command[key] {
          problems += fields.problems(field, owner: owner, extendedMessage: false)
        }
      }

      if let when = command.text("extendedWhen"), !flagNames.contains(when) {
        problems.append("\(owner): it names the operating flag \(pythonRepr(when)), which doesn't exist")
      }
    }

    for json in extended {
      problems += extendedProblems(CommandView(json: json), fields: fields)
    }

    let serialCommands = serial.map(CommandView.init)

    for command in serialCommands {
      problems += SerialRules.commandProblems(command, fields: fields)
    }

    problems += SerialRules.frameProblems(serialCommands)

    for message in direct {
      if let value = message["value"] {
        problems += fields.problems(value, owner: "the \(message.text("name") ?? "") message", extendedMessage: false)
      }
    }

    if let scale = commandSet["displayScale"] {
      let replyValues = extended.flatMap { $0["reply"]?.list("values") ?? [] }
      var known = flagNames
      known.formUnion(replyValues.compactMap { $0.text("name") })
      known.formUnion(replyValues.flatMap { $0.list("bits") }.compactMap { $0.text("name") })
      known.formUnion((commandSet["extendedSettings"]?.list("values") ?? []).compactMap { $0.text("name") })
      let celsiusWhen = scale.text("celsiusWhen") ?? ""

      if !known.contains(celsiusWhen) {
        problems.append("the displayScale names \(pythonRepr(celsiusWhen)), which isn't a flag, value or bit")
      }
    }

    return problems
  }

  /// The cmd2 values a standard command sends, or `nil` for any.
  private static func command2s(_ command: JSONValue, enumerations: Enumerations) -> Set<String>? {
    guard let parameter = command["parameter"] else {
      return [command.text("command2") ?? "0x00"]
    }
    return enumerations.valueSet(named: parameter.text("enumeration"))
  }

  /// Standard commands that share a cmd1 and can send the same cmd2.
  private static func sharedCommandProblems(_ standard: [JSONValue], enumerations: Enumerations) -> [String] {
    var problems: [String] = []

    for (index, command) in standard.enumerated() {
      for other in standard[(index + 1)...] where command.text("command1") == other.text("command1") {
        let mine = command2s(command, enumerations: enumerations)
        let theirs = command2s(other, enumerations: enumerations)

        if mine == nil || theirs == nil || !mine!.isDisjoint(with: theirs!) {
          problems.append("the \(command.text("name") ?? "") and \(other.text("name") ?? "") commands share a cmd1 and cmd2")
        }
      }
    }

    return problems
  }

  private static func extendedKey(_ command1: String, _ command2: String, _ fixed: [FixedByte]) -> String {
    "\(command1)|\(command2)|\(fixed.frameKey)"
  }

  /// Extended requests and replies that can't be told apart.
  private static func extendedKeyProblems(_ extended: [JSONValue]) -> [String] {
    var problems: [String] = []
    let requests = extended.map { command in
      extendedKey(command.text("command1") ?? "", command.text("command2") ?? "", CommandView(json: command).fixedBytes)
    }
    let replies = extended.compactMap { command -> String? in
      guard let reply = command["reply"] else { return nil }
      let match = reply.list("match").map { FixedByte(position: $0.number("position") ?? 0, value: $0.text("value") ?? "") }
      return extendedKey(reply.text("command1") ?? command.text("command1") ?? "", reply.text("command2") ?? "", match)
    }

    if Set(requests).count != requests.count {
      problems.append("two extended commands send the same cmd1, cmd2 and fixed bytes")
    }

    if Set(replies).count != replies.count {
      problems.append("two extended replies can't be told apart by their cmd1, cmd2 and match bytes")
    }

    return problems
  }

  /// An extended command's values, the user data bytes it fills and the bytes its reply reads.
  private static func extendedProblems(_ command: CommandView, fields: FieldRules) -> [String] {
    var problems: [String] = []
    let owner = "the \(command.name) command"

    for field in command.parameters {
      problems += fields.problems(field, owner: owner, extendedMessage: true)
    }

    var filled = FieldRules.positions(command.parameters) + command.fixedBytes.map { ($0.position, 0xFF) }
    filled += FieldRules.reserved(command.integrity)
    if command.isPerButton {
      filled.append((1, 0xFF))
    }

    if FieldRules.overlaps(filled) {
      problems.append("\(owner): it fills a user data byte twice")
    }

    if let reply = command.json["reply"] {
      let values = reply.list("values")

      for field in values {
        problems += fields.problems(field, owner: "\(owner)'s reply", extendedMessage: true)
      }

      let read = FieldRules.positions(values)
        + reply.list("match").map { ($0.number("position") ?? 0, 0xFF) }
        + FieldRules.reserved(reply.text("integrity"))

      if FieldRules.overlaps(read) {
        problems.append("\(owner)'s reply reads a user data byte twice")
      }
    }

    return problems
  }
}
