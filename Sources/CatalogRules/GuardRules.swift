import CatalogJSON

/// The guards that keep software from writing a flag that can cut a device off.
enum GuardRules {
  /// Operating flags that can cut a device off, lock it or change the message form it accepts,
  /// and the guard each needs wherever an app can write it: as a flag, or as a bit of a flags parameter.
  static let guardedFlags: [String: String] = [
    "programmingLock": "neverSet",
    "radioOff": "keep",
    "powerLineOff": "keep",
    "powerlineOff": "keep",
    "checksumRequired": "keep",
    "checksumRequiredOn": "keep",
    "extendedCommandsOnly": "keep"
  ]

  /// Kept flags that are a supported mode rather than a fault: no Set Operating Flags command that
  /// sets one is dangerous, and the flag needs no default.
  static let keptModes: Set<String> = ["extendedCommandsOnly"]

  /// Kept flags whose command set's sources give no factory state, so they carry no default. Every
  /// other kept flag needs one, so software can report a device whose flag differs from it.
  static let keptWithoutDocumentedDefault: [String: Set<String>] = [
    "fanLinc": ["checksumRequired"],
    "inLineLinc": ["radioOff", "powerLineOff", "checksumRequired"],
    "inLineLincRelay": ["checksumRequired"],
    "keypadLinc": ["checksumRequired"],
    "ledBulb": ["radioOff", "powerLineOff", "checksumRequired"],
    "outletLinc": ["checksumRequired"],
    "switchLincDimmer": ["radioOff", "powerLineOff", "checksumRequired"],
    "switchLincRelay": ["radioOff", "powerLineOff", "checksumRequired"]
  ]

  /// Set Operating Flags commands that turn one of those on, which an app never sends.
  static let neverSent: Set<String> = ["programmingLockOn", "radioOff", "powerLineOff", "powerlineOff", "checksumOn", "checksumRequiredOn"]

  /// Reports guarded flags without their guard, kept flags without a default, commands that turn a
  /// guarded flag on without `guard: never`, bits of a flags parameter without their guard, and
  /// `linkingChanges` that name a flag a linking flow may not change.
  static func problems(in commandSet: JSONValue) -> [String] {
    var problems: [String] = []
    let operatingFlags = commandSet.list("operatingFlags")
    let undocumented = keptWithoutDocumentedDefault[commandSet.text("id") ?? ""] ?? []

    for flag in operatingFlags {
      let name = flag.text("name") ?? ""

      if let needed = guardedFlags[name], flag.text("guard") != needed {
        problems.append("the \(name) flag needs guard \(pythonRepr(needed))")
      }

      if guardedFlags[name] == "keep", !keptModes.union(undocumented).contains(name), !flag.has("default") {
        problems.append("the \(name) flag is kept, so it needs a default")
      }
    }

    // Set Operating Flags commands, found by the bytes they send: every flag command, and any
    // standard or extended command with cmd1 0x20. One that turns a guarded flag on, by its name or
    // by a cmd2 that the command set's own flags or named on-commands use for that, is never sent.
    let standardAndExtended = ["standardCommands", "extendedCommands"].flatMap { commandSet.list($0).map(CommandView.init) }
    let setFlags = commandSet.list("flagCommands").map(CommandView.init)
      + standardAndExtended.filter { $0.command1 == "0x20" && $0.command2 != nil }

    var dangerous = Set(operatingFlags.compactMap { flag -> String? in
      let name = flag.text("name") ?? ""
      return guardedFlags[name] != nil && !keptModes.contains(name) ? flag.text("on") : nil
    })
    dangerous.formUnion(setFlags.filter { neverSent.contains($0.name) }.compactMap(\.command2))

    for command in setFlags {
      if neverSent.contains(command.name) || dangerous.contains(command.command2 ?? ""), command.guardKind != "never" {
        problems.append("the \(command.name) command turns a guarded flag on, so it needs guard 'never'")
      }
    }

    for command in standardAndExtended where neverSent.contains(command.name) && command.command1 != "0x20" && command.guardKind != "never" {
      problems.append("the \(command.name) command needs guard 'never'")
    }

    for command in commandSet.list("extendedCommands").map(CommandView.init) {
      for field in command.parameters {
        for bit in field.list("bits") {
          let name = bit.text("name") ?? ""

          if let needed = guardedFlags[name], bit.text("guard") != needed {
            problems.append("the \(command.name) command's \(name) bit needs guard \(pythonRepr(needed))")
          }
        }
      }
    }

    return problems + linkingChangeProblems(in: commandSet)
  }

  /// A linking flow may change only a flag with no guard that Set Operating Flags sets both ways.
  private static func linkingChangeProblems(in commandSet: JSONValue) -> [String] {
    var problems: [String] = []
    var flags: [String: JSONValue] = [:]
    for flag in commandSet.list("operatingFlags") {
      flags[flag.text("name") ?? ""] = flag
    }
    let changed = commandSet.list("linkingChanges").map { $0.text("flag") ?? "" }

    if Set(changed).count != changed.count {
      problems.append("linkingChanges names a flag twice")
    }

    for name in changed {
      guard let flag = flags[name] else {
        problems.append("linkingChanges names \(pythonRepr(name)), which isn't an operating flag")
        continue
      }

      if flag.has("guard") {
        problems.append("linkingChanges names \(pythonRepr(name)), which has a guard, so no linking flow may change it")
      } else if !flag.has("on") || !flag.has("off") {
        problems.append("linkingChanges names \(pythonRepr(name)), which Set Operating Flags can't set both ways")
      }
    }

    return problems
  }
}
