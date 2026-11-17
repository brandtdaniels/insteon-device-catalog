import Testing

/// The effect and idempotent rules, with the inputs and messages of `EffectRuleTests` and
/// `EffectRuleGapTests` in the Python build's tests.
struct EffectRulesTests {
  // EffectRuleTests.test_a_command_never_sent_must_be_destructive
  @Test func aCommandNeverSentMustBeDestructive() throws {
    let commandSet = try Fixtures.commandSet("outdoorApplianceLinc").settingCommand("radioOff", "effect", "\"configuration\"")

    #expect(try Fixtures.problems(commandSet) == ["the radioOff command is never sent, so its effect must be destructive"])
  }

  // EffectRuleTests.test_a_flag_command_is_never_read_only
  @Test func aFlagCommandIsNeverReadOnly() throws {
    let commandSet = try Fixtures.commandSet("globalLine").settingCommand("yakityYakOff", "effect", "\"readOnly\"")

    #expect(try Fixtures.problems(commandSet) == ["the yakityYakOff command is Set Operating Flags, which is never readOnly"])
  }

  // EffectRuleTests.test_an_extended_command_with_cmd1_0x20_is_never_read_only
  @Test func anExtendedCommandWithCmd1x20IsNeverReadOnly() throws {
    let commandSet = try Fixtures.commandSet("tempLinc").settingCommand("beepOn", "effect", "\"readOnly\"")

    #expect(try Fixtures.problems(commandSet) == ["the beepOn command is Set Operating Flags, which is never readOnly"])
  }

  // EffectRuleTests.test_an_extended_set_is_never_read_only
  @Test func anExtendedSetIsNeverReadOnly() throws {
    let commandSet = try Fixtures.commandSet("hiddenDoorSensor").settingCommand("setHeartbeatInterval", "effect", "\"readOnly\"")

    #expect(try Fixtures.problems(commandSet) == ["the setHeartbeatInterval command is an extended Set, which is never readOnly"])
  }

  // EffectRuleTests.test_an_extended_get_may_be_read_only
  @Test func anExtendedGetMayBeReadOnly() throws {
    let commandSet = try Fixtures.commandSet("hiddenDoorSensor")

    #expect(commandSet.command("readSettings")?["effect"] == .string("readOnly"))
    #expect(try Fixtures.problems(commandSet) == [])
  }

  // EffectRuleTests.test_a_read_only_command_must_be_idempotent
  @Test func aReadOnlyCommandMustBeIdempotent() throws {
    let commandSet = try Fixtures.commandSet("globalLine").settingCommand("readStatus", "idempotent", "false")

    #expect(try Fixtures.problems(commandSet) == ["the readStatus command is readOnly, so it must be idempotent"])
  }

  // EffectRuleTests.test_a_command_an_action_names_must_be_actuation
  @Test func aCommandAnActionNamesMustBeActuation() throws {
    let commandSet = try Fixtures.commandSet("globalLine").settingCommand("lightOn", "effect", "\"configuration\"")

    #expect(try Fixtures.problems(commandSet) == [
      "the light group type's on action names 'lightOn', which isn't actuation",
      "the load group type's on action names 'lightOn', which isn't actuation"
    ])
  }

  // EffectRuleTests.test_a_command_a_group_type_reads_its_state_with_must_be_read_only
  @Test func aCommandAGroupTypeReadsItsStateWithMustBeReadOnly() throws {
    let commandSet = try Fixtures.commandSet("globalLine").settingCommand("readStatus", "effect", "\"actuation\"")

    #expect(try Fixtures.problems(commandSet) == [
      "the light group type reads its state with 'readStatus', which isn't readOnly",
      "the load group type reads its state with 'readStatus', which isn't readOnly"
    ])
  }

  // EffectRuleTests.test_a_flag_on_command_must_be_configuration
  @Test func aFlagOnCommandMustBeConfiguration() throws {
    let commandSet = try Fixtures.commandSet("i3Dial").settingCommand("nightModeOn", "effect", "\"actuation\"")

    #expect(try Fixtures.problems(commandSet) == ["the nightMode flag's onCommand names 'nightModeOn', which isn't configuration"])
  }

  // EffectRuleTests.test_a_value_write_command_must_be_configuration
  @Test func aValueWriteCommandMustBeConfiguration() throws {
    let commandSet = try Fixtures.commandSet("ledBulb").settingCommand("writeRampRate", "effect", "\"destructive\"")

    #expect(try Fixtures.problems(commandSet) == ["the rampRate value is written by 'writeRampRate', which isn't configuration"])
  }

  // EffectRuleTests.test_a_flag_command_and_an_extended_set_operating_flags_command_with_one_cmd2_need_one_effect
  @Test func aFlagCommandAndAnExtendedSetOperatingFlagsCommandWithOneCmd2NeedOneEffect() throws {
    let commandSet = try Fixtures.commandSet("globalLine").appending(#"""
    [{"name": "yakityYakOffNow", "description": "Turns the Yakity Yak signaling option off.",
      "effect": "actuation", "idempotent": true, "command1": "0x20", "command2": "0x26"}]
    """#, to: "extendedCommands")

    #expect(try Fixtures.problems(commandSet) == [
      "the yakityYakOff command and the yakityYakOffNow command both send Set Operating Flags with cmd2 0x26, so they need the same effect and idempotent"
    ])
  }

  // EffectRuleTests.test_a_flag_and_a_standard_set_operating_flags_command_with_one_cmd2_need_one_effect
  @Test func aFlagAndAStandardSetOperatingFlagsCommandWithOneCmd2NeedOneEffect() throws {
    let commandSet = try Fixtures.commandSet("globalLine").appending(#"""
    [{"name": "keyBeepNow", "description": "Turns the key beep on.",
      "effect": "actuation", "idempotent": true, "command1": "0x20", "command2": "0x0A"}]
    """#, to: "standardCommands")

    #expect(try Fixtures.problems(commandSet) == [
      "the keyBeep flag and the keyBeepNow command both send Set Operating Flags with cmd2 0x0A, so they need the same effect and idempotent"
    ])
  }

  // EffectRuleTests.test_set_operating_flags_entries_with_one_cmd2_and_one_effect_pass
  @Test func setOperatingFlagsEntriesWithOneCmd2AndOneEffectPass() throws {
    let commandSet = try Fixtures.commandSet("globalLine").appending(#"""
    [{"name": "keyBeepAgain", "description": "Turns the key beep on.",
      "effect": "configuration", "idempotent": true, "command1": "0x20", "command2": "0x0A"}]
    """#, to: "standardCommands")

    #expect(try Fixtures.problems(commandSet) == [])
  }

  // EffectRuleTests.test_a_destructive_command_that_turns_a_guarded_flag_on_needs_guard_never_too
  @Test func aDestructiveCommandThatTurnsAGuardedFlagOnNeedsGuardNeverToo() throws {
    let base = try Fixtures.commandSet("outdoorApplianceLinc")
    let commandSet = base.removingFromCommand("radioOff", "guard")

    #expect(base.command("radioOff")?["effect"] == .string("destructive"))
    #expect(try Fixtures.problems(commandSet) == ["the radioOff command turns a guarded flag on, so it needs guard 'never'"])
  }

  // EffectRuleGapTests.test_a_standard_command_never_sent_must_be_destructive
  @Test func aStandardCommandNeverSentMustBeDestructive() throws {
    let commandSet = try Fixtures.commandSet("globalLine").appending(#"""
    [{"name": "exampleLockOn", "description": "Locks the device.", "effect": "configuration", "idempotent": true,
      "command1": "0x20", "command2": "0x7F", "guard": "never"}]
    """#, to: "standardCommands")

    #expect(try Fixtures.problems(commandSet) == ["the exampleLockOn command is never sent, so its effect must be destructive"])
  }

  // EffectRuleGapTests.test_an_extended_command_never_sent_must_be_destructive
  @Test func anExtendedCommandNeverSentMustBeDestructive() throws {
    let commandSet = try Fixtures.commandSet("tempLinc").settingCommand("programmingLockOn", "effect", "\"configuration\"")

    #expect(try Fixtures.problems(commandSet) == ["the programmingLockOn command is never sent, so its effect must be destructive"])
  }

  // EffectRuleGapTests.test_a_standard_command_with_cmd1_0x20_is_never_read_only
  @Test func aStandardCommandWithCmd1x20IsNeverReadOnly() throws {
    let commandSet = try Fixtures.commandSet("globalLine").appending(#"""
    [{"name": "exampleFlagOn", "description": "Sets a flag.", "effect": "readOnly", "idempotent": true,
      "command1": "0x20", "command2": "0x7F"}]
    """#, to: "standardCommands")

    #expect(try Fixtures.problems(commandSet) == ["the exampleFlagOn command is Set Operating Flags, which is never readOnly"])
  }

  // EffectRuleGapTests.test_a_properties_write_is_never_read_only
  @Test func aPropertiesWriteIsNeverReadOnly() throws {
    let commandSet = try Fixtures.commandSet("i3Dial").settingCommand("writeProperties", "effect", "\"readOnly\"")

    #expect(try Fixtures.problems(commandSet) == [
      "the writeProperties command writes properties (cmd1 0x2E, cmd2 0x01, D1 0x02), which is never readOnly"
    ])
  }

  // EffectRuleGapTests.test_a_cmd1_0x2f_write_is_never_read_only
  @Test func aCmd1x2fWriteIsNeverReadOnly() throws {
    let commandSet = try Fixtures.commandSet("energyDisplay").settingCommand("writeMeterId", "effect", "\"readOnly\"")

    #expect(try Fixtures.problems(commandSet) == ["the writeMeterId command writes with cmd1 0x2F and D2 0x02, which is never readOnly"])
  }

  // EffectRuleGapTests.test_an_extended_set_whose_selector_is_a_parameter_is_never_read_only
  @Test func anExtendedSetWhoseSelectorIsAParameterIsNeverReadOnly() throws {
    let base = try Fixtures.commandSet("hiddenDoorSensor")
    let steps = base.commandSteps("setHeartbeatInterval")
    let commandSet = try base
      .setting(steps + ["effect"], "\"readOnly\"")
      .setting(steps + ["fixed"], #"[{"position": 1, "value": "0x02"}]"#)
      .appending(to: steps + ["parameters"], #"[{"name": "selector", "description": "The setting to write.", "byte": 2}]"#)

    #expect(try Fixtures.problems(commandSet) == ["the setHeartbeatInterval command is an extended Set, which is never readOnly"])
  }

  // EffectRuleGapTests.test_a_parameterized_set_operating_flags_command_needs_the_effect_of_every_flag_it_can_send
  @Test func aParameterizedSetOperatingFlagsCommandNeedsTheEffectOfEveryFlagItCanSend() throws {
    let commandSet = try Fixtures.commandSet("globalLine").appending(#"""
    [{"name": "anyFlag", "description": "Sends any Set Operating Flags cmd2.", "effect": "actuation", "idempotent": true,
      "command1": "0x20", "parameter": {"name": "cmd2", "description": "The cmd2."}}]
    """#, to: "standardCommands")
    let problems = try Fixtures.problems(commandSet)

    #expect(problems.contains("the yakityYakOff command and the anyFlag command both send Set Operating Flags with cmd2 0x26, so they need the same effect and idempotent"))
    #expect(problems.contains("the keyBeep flag and the anyFlag command both send Set Operating Flags with cmd2 0x0A, 0x0B, so they need the same effect and idempotent"))
  }

  // EffectRuleGapTests.test_set_operating_flags_entries_with_one_cmd2_need_one_idempotent
  @Test func setOperatingFlagsEntriesWithOneCmd2NeedOneIdempotent() throws {
    let commandSet = try Fixtures.commandSet("globalLine").appending(#"""
    [{"name": "keyBeepToggle", "description": "Turns the key beep on.", "effect": "configuration", "idempotent": false,
      "command1": "0x20", "command2": "0x0A"}]
    """#, to: "standardCommands")

    #expect(try Fixtures.problems(commandSet) == [
      "the keyBeep flag and the keyBeepToggle command both send Set Operating Flags with cmd2 0x0A, so they need the same effect and idempotent"
    ])
  }

  // EffectRuleGapTests.test_extended_commands_one_message_can_match_need_one_effect_and_idempotent
  @Test func extendedCommandsOneMessageCanMatchNeedOneEffectAndIdempotent() throws {
    let commandSet = try Fixtures.commandSet("tempLinc").appending(#"""
    [{"name": "writePage", "description": "Writes a page of settings.", "effect": "configuration", "idempotent": true,
      "command1": "0x2E", "command2": "0x00", "fixed": [{"position": 1, "value": "0x01"}],
      "parameters": [{"name": "page", "description": "The page.", "byte": 3}], "integrity": "checksum"}]
    """#, to: "extendedCommands")

    #expect(try Fixtures.problems(commandSet) == [
      "the readSettings command and the writePage command can match the same extended message, so they need the same effect and idempotent",
      "the readMoreSettings command and the writePage command can match the same extended message, so they need the same effect and idempotent"
    ])
  }

  // EffectRuleGapTests.test_an_unfixed_byte_must_be_0x00_so_differing_fixed_bytes_do_not_overlap
  @Test func anUnfixedByteMustBe0x00SoDifferingFixedBytesDoNotOverlap() throws {
    let commandSet = try Fixtures.commandSet("energyDisplay")

    #expect(commandSet.command("readMeterIds")?["effect"] == .string("readOnly"))
    #expect(try Fixtures.problems(commandSet) == [])
  }

  // EffectRuleGapTests.test_a_read_only_extended_command_may_not_match_every_message_a_write_does
  @Test func aReadOnlyExtendedCommandMayNotMatchEveryMessageAWriteDoes() throws {
    let commandSet = try Fixtures.commandSet("globalLine").appending(#"""
    [{"name": "readThing", "description": "Reads a thing.", "effect": "readOnly", "idempotent": true,
      "command1": "0x50", "command2": "0x00", "parameters": [{"name": "thing", "description": "The thing.", "byte": 1}]},
     {"name": "writeThing", "description": "Writes a thing.", "effect": "configuration", "idempotent": true,
      "command1": "0x50", "command2": "0x00", "fixed": [{"position": 1, "value": "0x01"}]}]
    """#, to: "extendedCommands")

    #expect(try Fixtures.problems(commandSet) == ["the readThing command is readOnly, but it matches every message the writeThing command does"])
  }
}
