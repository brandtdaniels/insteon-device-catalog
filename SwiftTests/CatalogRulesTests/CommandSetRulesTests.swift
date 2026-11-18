import CatalogJSON
import Testing

/// The message, presentation and structure rules of a command set. Each expected message is the text
/// the Python build printed for the same input.
struct CommandSetRulesTests {
  /// A copy with the first element of the array at `key` added to the end of it.
  static func repeatingFirst(_ commandSet: JSONValue, in key: String) throws -> JSONValue {
    let first = try #require(commandSet[key]?.elements.first)
    return commandSet.changing([.key(key)], to: .array((commandSet[key]?.elements ?? []) + [first]))
  }

  @Test func theCatalogsCommandSetsHaveNoStructureProblems() throws {
    for file in try Fixtures.root.commandSetFiles() {
      #expect(try Fixtures.problems(file.value) == [], "\(file.name)")
    }
  }

  // Names and structure

  @Test func aFlagNameUsedTwiceAlsoSharesItsBitAndItsCmd2() throws {
    let commandSet = try Self.repeatingFirst(Fixtures.commandSet("globalLine"), in: "operatingFlags")

    #expect(try Fixtures.problems(commandSet) == [
      "a flag name appears more than once",
      "two operating flags share a bit",
      "two Set Operating Flags commands share a cmd2"
    ])
  }

  @Test func aCommandUsedTwiceSharesItsNameAndItsCmd1AndCmd2() throws {
    let base = try Fixtures.commandSet("globalLine")
    let lightOn = try #require(base.command("lightOn"))
    let commandSet = base.changing(["standardCommands"], to: .array((base["standardCommands"]?.elements ?? []) + [lightOn]))

    #expect(try Fixtures.problems(commandSet) == [
      "a command or message name appears more than once",
      "the lightOn and lightOn commands share a cmd1 and cmd2"
    ])
  }

  // Messages

  @Test func twoDirectMessagesThatShareACmd1AreReported() throws {
    let commandSet = try Fixtures.commandSet("tempLinc").setting(["directMessages", .index(1), "command1"], "\"0x6E\"")

    #expect(try Fixtures.problems(commandSet) == ["two direct messages share a cmd1"])
  }

  @Test func aDisplayScaleThatNamesNothingIsReported() throws {
    let commandSet = try Fixtures.commandSet("tempLinc").setting(["displayScale", "celsiusWhen"], "\"nothing\"")

    #expect(try Fixtures.problems(commandSet) == ["the displayScale names 'nothing', which isn't a flag, value or bit"])
  }

  @Test func anEnumerationThatRepeatsAValueAndANameIsReportedForBoth() throws {
    let base = try Fixtures.commandSet("dualOnOffOutlet")
    let enumeration = try #require(base["enumerations"]?.elements.first)
    let values = enumeration["values"]?.elements ?? []
    guard case .string(let name)? = enumeration["name"] else {
      Issue.record("the first enumeration has no name")
      return
    }
    let commandSet = base.changing(["enumerations", .index(0), "values"], to: .array(values + [values[0]]))

    #expect(try Fixtures.problems(commandSet) == [
      "the \(name) enumeration names a value twice",
      "the \(name) enumeration uses a name twice"
    ])
  }

  // Presentation

  @Test func aValueTableThatNamesAValueTwiceIsReported() throws {
    let base = try Fixtures.commandSet("applianceLinc")
    let table = try #require(base["valueTables"]?.elements.first)
    let values = table["values"]?.elements ?? []
    let commandSet = base.changing(["valueTables", .index(0), "values"], to: .array(values + [values[0]]))

    #expect(try Fixtures.problems(commandSet) == ["the onOff value table names a value twice"])
  }

  @Test func aValueTableNameUsedTwiceIsReported() throws {
    let commandSet = try Self.repeatingFirst(Fixtures.commandSet("applianceLinc"), in: "valueTables")

    #expect(try Fixtures.problems(commandSet) == ["a value table name appears more than once"])
  }

  @Test func aGroupTypeNameUsedTwiceIsReported() throws {
    let commandSet = try Self.repeatingFirst(Fixtures.commandSet("applianceLinc"), in: "groupTypes")

    #expect(try Fixtures.problems(commandSet) == ["a group type name appears more than once"])
  }

  @Test func aGroupTypeThatReadsItsStateWithACommandThatIsNotStandardIsReported() throws {
    let commandSet = try Fixtures.commandSet("applianceLinc").setting(["groupTypes", .index(0), "state", "command"], "\"nothing\"")

    #expect(try Fixtures.problems(commandSet) == [
      "the load group type reads its state with 'nothing', which isn't a standard command"
    ])
  }

  @Test func anActionThatNamesAMissingCommandIsReported() throws {
    let commandSet = try Fixtures.commandSet("applianceLinc").setting(["groupTypes", .index(0), "actions", .index(0), "command"], "\"nothing\"")

    #expect(try Fixtures.problems(commandSet) == [
      "the load group type's on action names the command 'nothing', which doesn't exist"
    ])
  }

  @Test func aStateHoldingThatRestsInNoActionIsReported() throws {
    let commandSet = try GuardRulesTests.ioLinc(stateHolding: #"{"releasedBy": [], "restState": "nowhere"}"#)

    #expect(try Fixtures.problems(commandSet) == [
      "the relay group type's stateHolding rests in 'nowhere', which isn't one of its actions"
    ])
  }

  @Test func aStateHoldingThatNamesAFlagThatDoesNotExistIsReported() throws {
    let commandSet = try GuardRulesTests.ioLinc(stateHolding: #"{"releasedBy": ["gone"], "restState": "off"}"#)

    #expect(try Fixtures.problems(commandSet) == ["the relay group type's stateHolding names 'gone', which isn't an operating flag"])
  }

  @Test func aLinkingChangeThatNamesNoFlagIsReported() throws {
    let commandSet = try Fixtures.commandSet("ioLinc").setting(["linkingChanges", .index(0), "flag"], "\"gone\"")

    #expect(try Fixtures.problems(commandSet) == ["linkingChanges names 'gone', which isn't an operating flag"])
  }

  @Test func aLinkingChangeThatNamesAGuardedFlagIsReported() throws {
    let commandSet = try Fixtures.commandSet("ioLinc").setting(["linkingChanges", .index(0), "flag"], "\"programmingLock\"")

    #expect(try Fixtures.problems(commandSet) == [
      "linkingChanges names 'programmingLock', which has a guard, so no linking flow may change it"
    ])
  }

  @Test func aLinkingChangeNamedTwiceIsReported() throws {
    let commandSet = try Self.repeatingFirst(Fixtures.commandSet("ioLinc"), in: "linkingChanges")

    #expect(try Fixtures.problems(commandSet) == ["linkingChanges names a flag twice"])
  }
}

/// A value's range, which a standard command gives as numbers.
struct RangeRuleTests {
  @Test func aNumericRangeThatRunsBackwardIsReported() throws {
    let base = try Fixtures.commandSet("i3Dial")
    let index = try #require(base["standardCommands"]?.elements.firstIndex { $0["parameter"]?["range"] != nil })
    let steps: [Step] = ["standardCommands", .index(index), "parameter", "range"]
    let backward = try base.setting(steps, #"{"from": 200, "through": 100}"#)
    let owner = try #require(base["standardCommands"]?.elements[index]["name"])

    guard case .string(let name) = owner else { return }
    #expect(try Fixtures.problems(backward).contains("the \(name) command: the \(try parameterName(base, index)) value's range runs backward"))
    #expect(try Fixtures.problems(base) == [])
  }

  private func parameterName(_ commandSet: JSONValue, _ index: Int) throws -> String {
    guard case .string(let name)? = commandSet["standardCommands"]?.elements[index]["parameter"]?["name"] else {
      throw ParameterNameMissing()
    }
    return name
  }

  struct ParameterNameMissing: Error {}
}
