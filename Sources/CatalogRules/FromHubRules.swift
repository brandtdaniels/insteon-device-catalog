import CatalogJSON

/// The rules for the `lifecycle.fromHub` flow a Hub follows to link a device.
enum FromHubRules {
  /// Reports a leg whose device group isn't one of the profile's groups, a controller leg whose
  /// device group doesn't respond, a responder leg whose groups differ or whose device group can't
  /// be a controller, a device-first start whose first leg doesn't have the device as controller,
  /// and keepAwake on a device without batteries or with a raw message that's malformed or isn't
  /// configuration and idempotent.
  static func problems(in profile: JSONValue) -> [String] {
    guard let fromHub = profile["lifecycle"]?["fromHub"] else { return [] }

    var problems: [String] = []
    let legs = fromHub.list("legs")
    var groups: [String: JSONValue] = [:]
    for group in profile.list("groups") {
      groups[group["number"]?.canonical ?? ""] = group
    }

    for (offset, leg) in legs.enumerated() {
      let index = offset + 1
      let deviceGroup = leg["deviceGroup"]?.messageText ?? ""
      let modem = leg.text("modem")
      let group = groups[leg["deviceGroup"]?.canonical ?? ""]

      if let group {
        if modem == "responder", group.text("role") == "responder" {
          problems.append("fromHub leg \(index) has the device control group \(deviceGroup), which is only a responder")
        } else if modem == "controller", group.text("role") == "controller" {
          problems.append("fromHub leg \(index) has the modem control the device's group \(deviceGroup), the Enter Linking Mode cmd2, which is only a controller")
        }
      } else {
        problems.append("fromHub leg \(index) names device group \(deviceGroup), which isn't one of the profile's groups")
      }

      if modem == "responder", leg["modemGroup"] != leg["deviceGroup"] {
        problems.append("fromHub leg \(index): the modem responds to the device's group, so its group must be \(deviceGroup)")
      }
    }

    if fromHub.isSet("deviceFirst"), legs.first?.text("modem") != "responder" {
      problems.append("fromHub starts with the device, so its first leg needs the modem as responder")
    }

    if let keepAwake = fromHub["keepAwake"] {
      problems += keepAwakeProblems(keepAwake, batteryPowered: profile.isSet("batteryPowered"))
    }

    return problems
  }

  private static func keepAwakeProblems(_ keepAwake: JSONValue, batteryPowered: Bool) -> [String] {
    var problems: [String] = []

    if !batteryPowered {
      problems.append("fromHub keeps the device awake, but it isn't battery-powered")
    }

    for key in ["send", "release"] {
      guard let message = keepAwake[key], message.has("command1") else { continue }

      var positions = message.list("data").map { $0["position"]?.canonical ?? "" }
      if message.text("integrity") == "checksum" {
        positions.append(JSONValue.int(14).canonical)
      }

      if Set(positions).count != positions.count {
        problems.append("fromHub keepAwake \(key) fills a user data byte twice")
      }

      if !message.isSet("extended"), !positions.isEmpty {
        problems.append("fromHub keepAwake \(key) has user data, so it must be extended")
      }

      if message.text("effect") != "configuration" || message["idempotent"] != .bool(true) {
        problems.append("fromHub keepAwake \(key) must be configuration and idempotent")
      }
    }

    return problems
  }

  /// Reports fromHub names that aren't in every command set the profile uses: allGroupsWhen flags,
  /// and keepAwake commands and flags; keepAwake commands that aren't configuration and
  /// idempotent; raw keepAwake bytes where a command set entry sends the same Set Operating Flags
  /// command; and raw keepAwake bytes whose effect differs from a standard or extended entry with
  /// those bytes.
  static func commandSetProblems(for profile: JSONValue, commandSets: [String: JSONValue]) -> [String] {
    guard let fromHub = profile["lifecycle"]?["fromHub"] else { return [] }

    var problems: [String] = []
    let used = Set(profile.list("commandSets").compactMap { $0.text("commandSet") }.filter { commandSets[$0] != nil }).codePointSorted()

    for (offset, leg) in fromHub.list("legs").enumerated() {
      guard let name = leg["allGroupsWhen"]?.text("flag") else { continue }

      let everyoneHasIt = used.allSatisfy { id in
        (commandSets[id]?.list("operatingFlags") ?? []).contains { $0.text("name") == name }
      }

      if used.isEmpty || !everyoneHasIt {
        problems.append("fromHub leg \(offset + 1) depends on \(pythonRepr(name)), which not every command set the profile uses has")
      }
    }

    for key in ["send", "release"] {
      guard let message = fromHub["keepAwake"]?[key] else { continue }

      if let command = message.text("command") {
        problems += namedCommandProblems(key: key, command: command, used: used, commandSets: commandSets)
      } else if let flag = message.text("flag") {
        let lacking = used.contains { id in
          !(commandSets[id]?.list("operatingFlags") ?? []).contains { $0.text("name") == flag && $0.has("on") && $0.has("off") }
        }

        if used.isEmpty || lacking {
          problems.append("fromHub keepAwake \(key) names the flag \(pythonRepr(flag)), which not every command set the profile uses sets both ways")
        }
      } else if message.text("command1") == "0x20" {
        problems += rawMessageProblems(key: key, message: message, used: used, commandSets: commandSets)
      }
    }

    return problems
  }

  private static let commandKinds = ["flagCommands", "standardCommands", "extendedCommands"]

  private static func namedCommandProblems(key: String, command: String, used: [String], commandSets: [String: JSONValue]) -> [String] {
    let named = used.map { id in
      commandKinds.flatMap { commandSets[id]?.list($0) ?? [] }.first { $0.text("name") == command }
    }

    guard !used.isEmpty, !named.contains(where: { $0 == nil }) else {
      return ["fromHub keepAwake \(key) names \(pythonRepr(command)), which not every command set the profile uses has"]
    }

    return zip(used, named).compactMap { id, entry in
      let view = CommandView(json: entry!)
      guard view.effect != "configuration" || !view.idempotent else { return nil }
      return "fromHub keepAwake \(key) names \(pythonRepr(command)), which isn't configuration and idempotent in \(id)"
    }
  }

  private static func rawMessageProblems(key: String, message: JSONValue, used: [String], commandSets: [String: JSONValue]) -> [String] {
    var problems: [String] = []
    let command2 = message.text("command2")
    let behavior = Behavior(effect: message.text("effect") ?? "", idempotent: message["idempotent"] == .bool(true))
    let kind = message.isSet("extended") ? "extendedCommands" : "standardCommands"

    for id in used {
      let commandSet = commandSets[id] ?? .null
      var sent = Set(commandSet.list("flagCommands").compactMap { $0.text("command2") })
      for flag in commandSet.list("operatingFlags") {
        sent.formUnion(["on", "off"].compactMap { flag.text($0) })
      }

      if let command2, sent.contains(command2) {
        problems.append("fromHub keepAwake \(key) gives raw bytes for a Set Operating Flags command \(id) names; name it instead")
      }

      for entry in commandSet.list(kind).map(CommandView.init)
      where entry.command1 == "0x20" && entry.command2 == command2 && entry.behavior != behavior {
        problems.append("fromHub keepAwake \(key) has the bytes of \(id)'s \(entry.name), so it needs the same effect and idempotent")
      }
    }

    return problems
  }
}
