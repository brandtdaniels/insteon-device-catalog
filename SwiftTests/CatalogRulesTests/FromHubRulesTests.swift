import CatalogJSON
import Testing

@testable import CatalogRules

/// The fromHub rules: the flow alone, and against the command sets the profile uses. The first five
/// tests are the keepAwake cases of `EffectRuleTests` and `EffectRuleGapTests` in the Python
/// build's tests.
struct FromHubRulesTests {
  // EffectRuleTests.test_a_named_keep_awake_command_must_be_idempotent
  @Test func aNamedKeepAwakeCommandMustBeIdempotent() throws {
    let commandSet = try Fixtures.commandSet("openCloseSensor").settingCommand("stayAwake", "idempotent", "false")

    #expect(FromHubRules.commandSetProblems(for: try Fixtures.profile("2843"), commandSets: ["openCloseSensor": commandSet]) == [
      "fromHub keepAwake send names 'stayAwake', which isn't configuration and idempotent in openCloseSensor"
    ])
  }

  // EffectRuleTests.test_a_named_keep_awake_command_must_be_configuration
  @Test func aNamedKeepAwakeCommandMustBeConfiguration() throws {
    let commandSet = try Fixtures.commandSet("openCloseSensor").settingCommand("stayAwake", "effect", "\"actuation\"")

    #expect(FromHubRules.commandSetProblems(for: try Fixtures.profile("2843"), commandSets: ["openCloseSensor": commandSet]) == [
      "fromHub keepAwake send names 'stayAwake', which isn't configuration and idempotent in openCloseSensor"
    ])
  }

  // EffectRuleTests.test_a_raw_keep_awake_message_must_be_configuration_and_idempotent
  @Test func aRawKeepAwakeMessageMustBeConfigurationAndIdempotent() throws {
    let profile = try Fixtures.profile("2441ZTH")
      .setting(["lifecycle", "fromHub", "keepAwake", "send", "effect"], "\"actuation\"")
      .setting(["lifecycle", "fromHub", "keepAwake", "release", "idempotent"], "false")

    #expect(FromHubRules.problems(in: profile) == [
      "fromHub keepAwake send must be configuration and idempotent",
      "fromHub keepAwake release must be configuration and idempotent"
    ])
  }

  // EffectRuleGapTests.test_a_keep_awake_flag_needs_no_effect_of_its_own
  @Test func aKeepAwakeFlagNeedsNoEffectOfItsOwn() throws {
    let profile = try Fixtures.profile("2444A2WH4")

    #expect(profile["lifecycle"]?["fromHub"]?["keepAwake"]?["send"] == .object([
      JSONMember(key: "flag", value: .string("stayAwake")), JSONMember(key: "set", value: .bool(true))
    ]))
    #expect(FromHubRules.commandSetProblems(for: profile, commandSets: ["remoteLinc2": try Fixtures.commandSet("remoteLinc2")]) == [])
  }

  // EffectRuleGapTests.test_raw_keep_awake_bytes_need_the_effect_of_the_command_set_entry_with_those_bytes
  @Test func rawKeepAwakeBytesNeedTheEffectOfTheCommandSetEntryWithThoseBytes() throws {
    let commandSet = try Fixtures.commandSet("tempLinc").settingCommand("setDisplayCelsius", "effect", "\"actuation\"")

    #expect(FromHubRules.commandSetProblems(for: try Fixtures.profile("2441ZTH"), commandSets: ["tempLinc": commandSet]) == [
      "fromHub keepAwake send has the bytes of tempLinc's setDisplayCelsius, so it needs the same effect and idempotent"
    ])
  }

  // No Python test covers the rules below; the sweep compares them with the Python build.
  @Test func aLegWhoseDeviceGroupIsNotTheProfilesNamesItAndTheMismatchedModemGroup() throws {
    let profile = try Fixtures.profile("2441ZTH").setting(["lifecycle", "fromHub", "legs", .index(0), "deviceGroup"], "\"0x09\"")

    #expect(FromHubRules.problems(in: profile) == [
      "fromHub leg 1 names device group 0x09, which isn't one of the profile's groups",
      "fromHub leg 1: the modem responds to the device's group, so its group must be 0x09"
    ])
  }

  @Test func aDeviceFirstStartNeedsTheModemAsResponderInTheFirstLeg() throws {
    let profile = try Fixtures.profile("2441ZTH").setting(["lifecycle", "fromHub", "legs", .index(0), "modem"], "\"controller\"")

    #expect(FromHubRules.problems(in: profile) == [
      "fromHub leg 1 has the modem control the device's group 0x01, the Enter Linking Mode cmd2, which is only a controller",
      "fromHub starts with the device, so its first leg needs the modem as responder"
    ])
  }

  @Test func aResponderLegWhoseDeviceGroupIsOnlyAResponderIsReported() throws {
    let profile = try Fixtures.profile("2441ZTH").setting(["groups", .index(0), "role"], "\"responder\"")

    #expect(FromHubRules.problems(in: profile) == [
      "fromHub leg 1 has the device control group 0x01, which is only a responder"
    ])
  }

  @Test func keepAwakeNeedsABatteryPoweredDevice() throws {
    let profile = try Fixtures.profile("2441ZTH").setting(["batteryPowered"], "false")

    #expect(FromHubRules.problems(in: profile) == ["fromHub keeps the device awake, but it isn't battery-powered"])
  }

  @Test func aRawKeepAwakeMessageFillsEachUserDataByteOnceAndIsExtendedWhenItHasData() throws {
    let steps: [Step] = ["lifecycle", "fromHub", "keepAwake", "send"]
    let profile = try Fixtures.profile("2441ZTH")
      .setting(steps + ["extended"], "false")
      .setting(steps + ["data"], #"[{"position": 1, "value": "0x01"}, {"position": 1, "value": "0x02"}]"#)

    #expect(FromHubRules.problems(in: profile) == [
      "fromHub keepAwake send fills a user data byte twice",
      "fromHub keepAwake send has user data, so it must be extended"
    ])
  }

  @Test func aLegAndAKeepAwakeNameNeedEveryCommandSetTheProfileUsesToHaveThem() throws {
    let profile = try Fixtures.profile("2843")
    let problems = FromHubRules.commandSetProblems(for: profile, commandSets: [:])

    #expect(problems.contains("fromHub leg 1 depends on 'linkToAllGroups', which not every command set the profile uses has"))
    #expect(problems.contains("fromHub keepAwake send names 'stayAwake', which not every command set the profile uses has"))
  }

  @Test func aProfileWithoutFromHubHasNoFromHubProblems() throws {
    let profile = try Fixtures.profile("2441ZTH").removing(["lifecycle", "fromHub"])

    #expect(FromHubRules.problems(in: profile) == [])
    #expect(FromHubRules.commandSetProblems(for: profile, commandSets: [:]) == [])
  }
}
