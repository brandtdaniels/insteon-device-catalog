import CatalogJSON
import Testing

/// The guard, default, operating flags byte and state holding rules, with the inputs and messages
/// of `OperatingFlagsByteTests`, `GuardedNameVariantTests`, `KeptFlagDefaultTests` and
/// `StateHoldingTests` in the Python build's tests.
struct GuardRulesTests {
  /// A copy of the I/O Linc command set with the relay group type's stateHolding replaced.
  static func ioLinc(stateHolding json: String) throws -> JSONValue {
    let base = try Fixtures.commandSet("ioLinc")
    let index = try #require(base["groupTypes"]?.elements.firstIndex { $0["kind"] == .string("relay") })

    return try base.setting(["groupTypes", .index(index), "stateHolding"], json)
  }

  /// A copy with the flag, flag command or setting value called `old` renamed.
  static func renamed(_ commandSet: JSONValue, in key: String, _ old: String, to new: String) throws -> JSONValue {
    try commandSet.setting([.key(key), .named(old), "name"], "\"\(new)\"")
  }

  // OperatingFlagsByteTests.test_a_value_whose_reply_field_holds_operating_flags_needs_flags_query
  @Test func aValueWhoseReplyFieldHoldsOperatingFlagsNeedsFlagsQuery() throws {
    let commandSet = try Fixtures.commandSet("openCloseSensor").removing(["extendedSettings", "values", .named("configuration"), "flagsQuery"])

    #expect(try Fixtures.problems(commandSet) == ["the configuration value holds the operating flags byte, so it needs flagsQuery"])
  }

  // OperatingFlagsByteTests.test_a_value_named_operating_flags_needs_flags_query
  @Test func aValueNamedOperatingFlagsNeedsFlagsQuery() throws {
    let commandSet = try Fixtures.commandSet("hiddenDoorSensor").removing(["extendedSettings", "values", .named("operatingFlags"), "flagsQuery"])

    #expect(try Fixtures.problems(commandSet) == ["the operatingFlags value holds the operating flags byte, so it needs flagsQuery"])
  }

  // OperatingFlagsByteTests.test_a_value_named_operating_flags_needs_flags_query_without_a_reply_field
  @Test func aValueNamedOperatingFlagsNeedsFlagsQueryWithoutAReplyField() throws {
    let commandSet = try Fixtures.commandSet("remoteLinc2").setting(["extendedSettings", "values", .named("configuration"), "name"], "\"operatingFlags\"")

    #expect(try Fixtures.problems(commandSet) == ["the operatingFlags value holds the operating flags byte, so it needs flagsQuery"])
  }

  // GuardedNameVariantTests.test_a_flag_named_powerline_off_needs_guard_keep
  @Test func aFlagNamedPowerlineOffNeedsGuardKeep() throws {
    let commandSet = try Self.renamed(Fixtures.commandSet("globalLine"), in: "operatingFlags", "powerLineOff", to: "powerlineOff")
      .removing(["operatingFlags", .named("powerlineOff"), "guard"])

    #expect(try Fixtures.problems(commandSet) == ["the powerlineOff flag needs guard 'keep'"])
  }

  // GuardedNameVariantTests.test_a_flag_named_checksum_required_on_needs_guard_keep
  @Test func aFlagNamedChecksumRequiredOnNeedsGuardKeep() throws {
    let commandSet = try Self.renamed(Fixtures.commandSet("globalLine"), in: "operatingFlags", "checksumRequired", to: "checksumRequiredOn")
      .removing(["operatingFlags", .named("checksumRequiredOn"), "guard"])

    #expect(try Fixtures.problems(commandSet) == ["the checksumRequiredOn flag needs guard 'keep'"])
  }

  // GuardedNameVariantTests.test_a_command_named_powerline_off_needs_guard_never
  @Test func aCommandNamedPowerlineOffNeedsGuardNever() throws {
    let commandSet = try Self.renamed(Fixtures.commandSet("outdoorApplianceLinc"), in: "flagCommands", "powerLineOff", to: "powerlineOff")
      .removing(["flagCommands", .named("powerlineOff"), "guard"])

    #expect(try Fixtures.problems(commandSet) == ["the powerlineOff command turns a guarded flag on, so it needs guard 'never'"])
  }

  // GuardedNameVariantTests.test_a_command_named_checksum_required_on_needs_guard_never
  @Test func aCommandNamedChecksumRequiredOnNeedsGuardNever() throws {
    let commandSet = try Self.renamed(Fixtures.commandSet("outdoorApplianceLinc"), in: "flagCommands", "checksumOn", to: "checksumRequiredOn")
      .removing(["flagCommands", .named("checksumRequiredOn"), "guard"])

    #expect(try Fixtures.problems(commandSet) == ["the checksumRequiredOn command turns a guarded flag on, so it needs guard 'never'"])
  }

  // KeptFlagDefaultTests.test_a_kept_flag_needs_a_default
  @Test func aKeptFlagNeedsADefault() throws {
    let commandSet = try Fixtures.commandSet("globalLine").removing(["operatingFlags", .named("radioOff"), "default"])

    #expect(try Fixtures.problems(commandSet) == ["the radioOff flag is kept, so it needs a default"])
  }

  // KeptFlagDefaultTests.test_a_kept_flag_under_a_variant_name_needs_a_default
  @Test func aKeptFlagUnderAVariantNameNeedsADefault() throws {
    let commandSet = try Self.renamed(Fixtures.commandSet("globalLine"), in: "operatingFlags", "checksumRequired", to: "checksumRequiredOn")
      .removing(["operatingFlags", .named("checksumRequiredOn"), "default"])

    #expect(try Fixtures.problems(commandSet) == ["the checksumRequiredOn flag is kept, so it needs a default"])
  }

  // StateHoldingTests.test_a_relay_no_flag_releases_always_holds_its_state
  @Test func aRelayNoFlagReleasesAlwaysHoldsItsState() throws {
    let commandSet = try Self.ioLinc(stateHolding: #"{"releasedBy": [], "restState": "off"}"#)

    #expect(try Fixtures.problems(commandSet) == [])
  }

  // StateHoldingTests.test_a_relay_no_flag_releases_cannot_pulse_on_every_command
  @Test func aRelayNoFlagReleasesCannotPulseOnEveryCommand() throws {
    let commandSet = try Self.ioLinc(stateHolding: #"{"releasedBy": [], "restState": "off", "pulsesOnEveryCommandWhen": [["momentary"]]}"#)

    #expect(try Fixtures.problems(commandSet) == [
      "the relay group type's stateHolding has pulsesOnEveryCommandWhen, but no releasedBy flag releases the relay"
    ])
  }
}
