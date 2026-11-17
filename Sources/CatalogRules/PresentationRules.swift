import CatalogJSON

/// Rules for what software shows of a command set: value tables, extended settings values, group
/// types with their state, outputs, record data and actions.
enum PresentationRules {
  static func problems(in commandSet: JSONValue) -> [String] {
    var problems: [String] = []
    let tables = NamedList(commandSet.list("valueTables"))
    let groupTypes = commandSet.list("groupTypes")
    let standard = commandSet.list("standardCommands")
    let extended = commandSet.list("extendedCommands")
    let flagNames = Set(commandSet.list("operatingFlags").compactMap { $0.text("name") })
    let commandNames = Set((standard + extended).map { $0.text("name") ?? "" })
    let standardNames = Set(standard.map { $0.text("name") ?? "" })
    let values = commandSet["extendedSettings"]?.list("values") ?? []

    problems += valueTableProblems(tables)
    problems += defaultProblems(values, tables: tables)

    if Set(groupTypes.map { $0.text("name") ?? "" }).count != groupTypes.count {
      problems.append("a group type name appears more than once")
    }

    let context = GroupTypeContext(
      commandSet: commandSet, tables: tables, flagNames: flagNames, commandNames: commandNames,
      standardNames: standardNames,
      replies: Dictionary(standard.map { ($0.text("name") ?? "", $0["reply"]) }, uniquingKeysWith: { $1 }),
      takesParameter: Dictionary((standard + extended).map { ($0.text("name") ?? "", $0.has("parameter")) }, uniquingKeysWith: { $1 })
    )

    for groupType in groupTypes {
      problems += groupTypeProblems(groupType, context: context)
    }

    problems += settingsValueProblems(in: commandSet, tables: tables, flagNames: flagNames)
    problems += GuardRules.problems(in: commandSet)

    for flag in commandSet.list("operatingFlags") {
      for key in ["onCommand", "offCommand"] {
        if let command = flag.text(key), !standardNames.contains(command) {
          problems.append("the \(flag.text("name") ?? "") flag's \(key) names \(pythonRepr(command)), which isn't a standard command")
        }
      }
    }

    return problems
  }

  /// Value tables that are named twice, or name a value twice.
  private static func valueTableProblems(_ tables: NamedList) -> [String] {
    var problems: [String] = []

    if tables.unique.count != tables.listed {
      problems.append("a value table name appears more than once")
    }

    for table in tables.unique {
      let values = table.list("values").map { $0.text("value") ?? "" }

      if Set(values).count != values.count {
        problems.append("the \(table.text("name") ?? "") value table names a value twice")
      }
    }

    return problems
  }

  /// Settings values whose table doesn't exist, and defaults outside their range or table.
  private static func defaultProblems(_ values: [JSONValue], tables: NamedList) -> [String] {
    var problems: [String] = []

    for value in values {
      let name = value.text("name") ?? ""
      let table = value.text("table")

      if let table, tables[table] == nil {
        problems.append("the \(name) value names the value table \(pythonRepr(table)), which doesn't exist")
      }

      guard let defaultValue = value.text("default") else { continue }
      let number = hexValue(defaultValue)

      if let bounds = value["range"], bounds.isTruthy, !within(number, bounds) {
        problems.append("the \(name) value's default is outside its range")
      }

      if let table, let found = tables[table], !found.list("values").contains(where: { $0.text("value") == defaultValue }) {
        problems.append("the \(name) value's default isn't in its value table")
      }
    }

    return problems
  }

  /// Whether `number` is from `from` through `through`, both as hex strings.
  private static func within(_ number: Int, _ bounds: JSONValue) -> Bool {
    hexValue(bounds.text("from") ?? "") <= number && number <= hexValue(bounds.text("through") ?? "")
  }

  /// What the group type checks need to look up.
  private struct GroupTypeContext {
    let commandSet: JSONValue
    let tables: NamedList
    let flagNames: Set<String>
    let commandNames: Set<String>
    let standardNames: Set<String>
    let replies: [String: JSONValue?]
    let takesParameter: [String: Bool]
  }

  private static func groupTypeProblems(_ groupType: JSONValue, context: GroupTypeContext) -> [String] {
    var problems: [String] = []
    let label = "the \(groupType.text("name") ?? "") group type"
    let state = groupType["state"]
    let kind = groupType.text("kind") ?? ""

    if let state {
      let command = state.text("command") ?? ""

      if !context.standardNames.contains(command) {
        problems.append("\(label) reads its state with \(pythonRepr(command)), which isn't a standard command")
      } else if (context.replies[command] ?? nil) == nil {
        problems.append("\(label) reads its state with \(pythonRepr(command)), which has no reply")
      } else if state.isSet("bitPerGroup"), (context.replies[command] ?? nil)?.text("kind") != "flags" {
        problems.append("\(label) reads one bit per group from a reply that isn't flags")
      }
    }

    if let onWhen = state?["onWhen"], let state {
      if hexValue(onWhen.text("value") ?? "") & ~hexValue(onWhen.text("mask") ?? "") != 0 {
        problems.append("\(label)'s onWhen value has bits outside its mask")
      }

      if state.isSet("bitPerGroup") || state.has("ranges") {
        problems.append("\(label)'s state has onWhen with bitPerGroup or ranges")
      }
    }

    if groupType.has("armModes") != (kind == "alarm" || kind == "arming") {
      problems.append("\(label) has armModes only if it's an alarm or arming group")
    }

    let actions = groupType.list("actions")

    if let outputs = groupType["outputs"] {
      problems += outputProblems(outputs, label: label, actions: actions, context: context)
    }

    problems += rangeProblems(state, label: label)

    for member in groupType["linkData"]?.members ?? [] {
      problems += linkDataProblems(side: member.key, entries: member.value.elements, label: label, tables: context.tables)
    }

    let names = actions.map { $0.text("name") ?? "" }

    if Set(names).count != names.count {
      problems.append("\(label) names an action twice")
    }

    if let holding = groupType["stateHolding"] {
      problems += stateHoldingProblems(holding, kind: kind, names: names, label: label, flagNames: context.flagNames)
    }

    for action in actions {
      let command = action.text("command") ?? ""

      if !context.commandNames.contains(command) {
        problems.append("\(label)'s \(action.text("name") ?? "") action names the command \(pythonRepr(command)), which doesn't exist")
      } else if action.has("value"), context.takesParameter[command] != true {
        problems.append("\(label)'s \(action.text("name") ?? "") action gives a value to \(pythonRepr(command)), which takes none")
      }
    }

    return problems
  }

  private static func outputProblems(_ outputs: JSONValue, label: String, actions: [JSONValue], context: GroupTypeContext) -> [String] {
    var problems: [String] = []

    if FieldRules.hasBadMasksOrNames(outputs.list("bits")) {
      problems.append("\(label)'s outputs must have distinct, nonzero masks and distinct names")
    }

    if let flag = outputs["activeWhen"]?.text("flag"), !context.flagNames.contains(flag) {
      problems.append("\(label)'s outputs depend on \(pythonRepr(flag)), which isn't an operating flag")
    }

    let selects = actions.contains { context.takesParameter[$0.text("command") ?? ""] == true && !$0.has("value") }

    if !selects {
      problems.append("\(label) has outputs, but no action takes a parameter to select them in")
    }

    return problems
  }

  /// State ranges that are reversed or overlap.
  private static func rangeProblems(_ state: JSONValue?, label: String) -> [String] {
    let ranges = (state?.list("ranges") ?? []).map { (hexValue($0.text("from") ?? ""), hexValue($0.text("through") ?? "")) }
    let sorted = ranges.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
    let reversed = ranges.contains { $0.0 > $0.1 }
    let overlapping = zip(sorted, sorted.dropFirst()).contains { $0.1 >= $1.0 }

    return reversed || overlapping ? ["\(label)'s state ranges are reversed or overlap"] : []
  }

  /// The ALL-Link record data of a group type for one side, controller or responder.
  private static func linkDataProblems(side: String, entries: [JSONValue], label: String, tables: NamedList) -> [String] {
    var problems: [String] = []
    let numbers = entries.map { $0["byte"]?.canonical ?? "" }

    if Set(numbers).count != numbers.count {
      problems.append("\(label)'s \(side) record data names a byte twice")
    }

    for entry in entries {
      let bounds = entry["range"].flatMap { $0.isTruthy ? $0 : nil }
      let what = "\(label)'s \(side) record data \(entry.text("name") ?? "")"
      let hasKeys = ["value", "range", "table"].contains(where: entry.has)

      if let table = entry.text("table"), tables[table] == nil {
        problems.append("\(label)'s \(side) record data names the value table \(pythonRepr(table)), which doesn't exist")
      }

      if !hasKeys, !entry.isSet("perGroup") {
        problems.append("\(what) gives no value, range, table or perGroup")
      }

      if entry.isSet("perGroup"), ["value", "range", "table", "unit"].contains(where: entry.has) {
        problems.append("\(what) is perGroup but also gives a value, range, table or unit")
      }

      if entry.has("table"), entry.has("unit") {
        problems.append("\(what) has both a table and a unit")
      }

      if entry.has("scale"), !entry.has("unit") {
        problems.append("\(what) has a scale but no unit")
      }

      if let bounds, hexValue(bounds.text("from") ?? "") > hexValue(bounds.text("through") ?? "") {
        problems.append("\(what)'s range is reversed")
      }

      if let value = entry.text("value"), let bounds, !within(hexValue(value), bounds) {
        problems.append("\(what) is outside its range")
      }

      if let name = entry.text("table"), let table = tables[name] {
        let values = table.list("values").map { hexValue($0.text("value") ?? "") }

        if let value = entry.text("value"), !values.contains(hexValue(value)) {
          problems.append("\(what)'s value isn't in its table")
        }

        if let bounds, values.contains(where: { !within($0, bounds) }) {
          problems.append("\(what)'s table has values outside its range")
        }
      }
    }

    return problems
  }

  private static func stateHoldingProblems(_ holding: JSONValue, kind: String, names: [String], label: String, flagNames: Set<String>) -> [String] {
    var problems: [String] = []
    let restState = holding.text("restState") ?? ""
    let releasedBy = holding.list("releasedBy").compactMap(\.string)

    if kind != "relay" {
      problems.append("\(label) has stateHolding, which only a relay group type has")
    }

    if !names.contains(restState) {
      problems.append("\(label)'s stateHolding rests in \(pythonRepr(restState)), which isn't one of its actions")
    }

    if releasedBy.isEmpty, holding.has("pulsesOnEveryCommandWhen") {
      problems.append("\(label)'s stateHolding has pulsesOnEveryCommandWhen, but no releasedBy flag releases the relay")
    }

    for name in releasedBy + holding.list("pulsesOnEveryCommandWhen").flatMap({ $0.elements.compactMap(\.string) }) where !flagNames.contains(name) {
      problems.append("\(label)'s stateHolding names \(pythonRepr(name)), which isn't an operating flag")
    }

    return problems
  }

  /// Extended settings values that hold the operating flags byte without saying which query reads
  /// it, or mix fields a kind of value can't have.
  private static func settingsValueProblems(in commandSet: JSONValue, tables: NamedList, flagNames: Set<String>) -> [String] {
    var problems: [String] = []
    let extended = commandSet.list("extendedCommands")
    let extendedNames = Set(extended.map { $0.text("name") ?? "" })
    let queries = Set(commandSet.list("operatingFlags").compactMap { $0["query"]?.canonical })

    // Extended message fields that hold the operating flags byte: a flags field with a bit named
    // for one of the command set's operating flags.
    let flagsBytes = Set(extended.flatMap { command in
      command.list("parameters") + (command["reply"]?.list("values") ?? [])
    }.filter { field in
      field.list("bits").contains { flagNames.contains($0.text("name") ?? "") }
    }.map { $0.text("name") ?? "" })

    for value in commandSet["extendedSettings"]?.list("values") ?? [] {
      let name = value.text("name") ?? ""
      let label = "the \(name) value"

      if name == "operatingFlags" || flagsBytes.contains(name), !value.has("flagsQuery") {
        problems.append("\(label) holds the operating flags byte, so it needs flagsQuery")
      }

      if value.text("kind") == "buttons", value.has("unit") || value.has("table") {
        problems.append("\(label) is buttons but has a unit or table")
      }

      if value.has("table"), value.has("unit") {
        problems.append("\(label) has both a table and a unit")
      }

      if value.has("scale"), !value.has("unit") {
        problems.append("\(label) has a scale but no unit")
      }

      if let write = value.text("write"), !extendedNames.contains(write) {
        problems.append("\(label) is written by \(pythonRepr(write)), which isn't an extended command")
      }

      if let query = value["flagsQuery"] {
        if !queries.contains(query.canonical) {
          problems.append("\(label) is the operating flags byte for query \(query.messageText), which no operating flag reads")
        }

        if ["kind", "range", "table", "unit", "scale"].contains(where: value.has) {
          problems.append("\(label) is an operating flags byte, so it can't have a kind, range, table, unit or scale")
        }
      }

      if let tableName = value.text("table"), let table = tables[tableName], let bounds = value["range"], bounds.isTruthy {
        if table.list("values").contains(where: { !within(hexValue($0.text("value") ?? ""), bounds) }) {
          problems.append("\(label)'s table has a value outside its range")
        }
      }
    }

    return problems
  }
}

/// A list of named entries as Python's `{name: entry}` dictionary holds it: a name used twice
/// keeps its first position and its last entry.
struct NamedList {
  /// How many entries the file lists, repeats included.
  let listed: Int
  /// One entry per name, in the order each name first appears.
  let unique: [JSONValue]
  private let byName: [String: JSONValue]

  init(_ entries: [JSONValue]) {
    var byName: [String: JSONValue] = [:]
    var order: [String] = []

    for entry in entries {
      let name = entry.text("name") ?? ""
      if byName[name] == nil {
        order.append(name)
      }
      byName[name] = entry
    }

    self.listed = entries.count
    self.byName = byName
    self.unique = order.compactMap { byName[$0] }
  }

  subscript(name: String) -> JSONValue? {
    byName[name]
  }
}
