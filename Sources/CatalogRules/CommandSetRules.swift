import CatalogJSON

/// The rules a command set has to satisfy beyond its schema.
public enum CommandSetRules {
  /// The problems in a command set that passed its schema, starting with a file name that isn't
  /// its id, then those of ``problems(in:)``.
  ///
  /// - Parameter stem: The command set's file name without `.json`.
  public static func problems(in commandSet: JSONValue, fileStem stem: String) -> [String] {
    let id = commandSet.text("id") ?? ""
    let name = stem == id ? [] : ["the file name must be the id, \(pythonRepr(id))"]

    return name + problems(in: commandSet)
  }

  /// The command sets by id; a command set listed twice keeps the last.
  public static func byId(_ commandSets: [JSONValue]) -> [String: JSONValue] {
    Dictionary(commandSets.map { ($0.text("id") ?? "", $0) }, uniquingKeysWith: { $1 })
  }

  /// The problems in a command set that passed its schema, one message each, in the order the
  /// rules find them: names used twice, flags sharing a bit or a command, values sharing a byte,
  /// writes sharing a selector or filling a byte twice, then the message, presentation and effect rules.
  public static func problems(in commandSet: JSONValue) -> [String] {
    var problems: [String] = []
    let flags = commandSet.list("operatingFlags")
    let flagCommands = commandSet.list("flagCommands")
    let settings = commandSet["extendedSettings"]
    let values = settings?.list("values") ?? []
    let writes = settings?.list("writes") ?? []

    let groups: [(kind: String, items: [JSONValue])] = [
      ("flag", flags + commandSet.list("readings") + flagCommands),
      ("value", values),
      ("write", writes)
    ]

    for (kind, items) in groups {
      let names = items.map { $0.text("name") ?? "" }

      if Set(names).count != names.count {
        problems.append("a \(kind) name appears more than once")
      }
    }

    let bits = flags.map { "\($0["query"]?.canonical ?? "")|\($0["bit"]?.canonical ?? "")" }

    if Set(bits).count != bits.count {
      problems.append("two operating flags share a bit")
    }

    let commands = flags.flatMap { flag in ["on", "off"].compactMap { flag.text($0) } } + flagCommands.map { $0.text("command2") ?? "" }

    if Set(commands).count != commands.count {
      problems.append("two Set Operating Flags commands share a cmd2")
    }

    if Set(values.map { $0["byte"]?.canonical ?? "" }).count != values.count {
      problems.append("two values share a byte")
    }

    if Set(writes.map { $0["selector"]?.canonical ?? "" }).count != writes.count {
      problems.append("two writes share a selector")
    }

    for write in writes {
      let positions = write.list("bytes").map { $0["position"]?.canonical ?? "" }

      if Set(positions).count != positions.count {
        problems.append("the \(write.text("name") ?? "") write fills a byte twice")
      }
    }

    return problems
      + MessageRules.problems(in: commandSet)
      + PresentationRules.problems(in: commandSet)
      + EffectRules.problems(in: commandSet)
  }
}
