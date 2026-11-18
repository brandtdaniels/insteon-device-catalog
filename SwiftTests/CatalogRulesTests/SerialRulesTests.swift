import CatalogJSON
import Testing

/// The serial command rules, with the inputs and messages of `SerialCommandRuleTests` in the
/// Python build's tests.
struct SerialRulesTests {
  static func serialSteps(_ name: String) -> [Step] {
    ["serialCommands", .named(name)]
  }

  // SerialCommandSchemaTests.test_a_serial_command_set_passes (the rules half)
  @Test func theInventedSerialCommandSetHasNoProblems() throws {
    #expect(try Fixtures.problems(Fixtures.serialCommandSet()) == [])
  }

  // SerialCommandRuleTests.test_a_serial_command_never_sent_must_be_destructive
  @Test func aSerialCommandNeverSentMustBeDestructive() throws {
    let commandSet = try Fixtures.serialCommandSet().setting(Self.serialSteps("startThing") + ["guard"], "\"never\"")

    #expect(try Fixtures.problems(commandSet) == ["the startThing serial command is never sent, so its effect must be destructive"])
  }

  // SerialCommandRuleTests.test_a_read_only_serial_command_must_be_idempotent
  @Test func aReadOnlySerialCommandMustBeIdempotent() throws {
    let commandSet = try Fixtures.serialCommandSet().setting(Self.serialSteps("readInfo") + ["idempotent"], "false")

    #expect(try Fixtures.problems(commandSet) == ["the readInfo serial command is readOnly, so it must be idempotent"])
  }

  // SerialCommandRuleTests.test_a_serial_command_that_carries_a_device_message_is_not_an_entry
  @Test(arguments: ["0x61", "0x62"])
  func aSerialCommandThatCarriesADeviceMessageIsNotAnEntry(number: String) throws {
    let commandSet = try Fixtures.serialCommandSet().setting(Self.serialSteps("readInfo") + ["number"], "\"\(number)\"")

    #expect(try Fixtures.problems(commandSet) == ["the readInfo serial command has number \(number), which carries a device message and so isn't an entry"])
  }

  // SerialCommandRuleTests.test_serial_commands_with_one_number_and_different_fixed_bytes_need_not_share_an_effect
  @Test func serialCommandsWithOneNumberAndDifferentFixedBytesNeedNotShareAnEffect() throws {
    #expect(try Fixtures.problems(Fixtures.serialCommandSet()) == [])
  }

  // SerialCommandRuleTests.test_serial_commands_that_send_the_same_number_and_fixed_bytes_fail
  @Test func serialCommandsThatSendTheSameNumberAndFixedBytesFail() throws {
    let commandSet = try Fixtures.serialCommandSet().setting(Self.serialSteps("deleteThing") + ["fixed"], #"[{"position": 1, "value": "0x01"}]"#)

    #expect(try Fixtures.problems(commandSet) == [
      "two serial commands send the same number and fixed bytes",
      "the startThing serial command and the deleteThing serial command can match the same frame, so they need the same effect and idempotent"
    ])
  }

  // SerialCommandRuleTests.test_serial_commands_one_frame_can_match_need_one_effect_and_idempotent
  @Test func serialCommandsOneFrameCanMatchNeedOneEffectAndIdempotent() throws {
    let commandSet = try Fixtures.serialCommandSet().appending(#"""
    [{"name": "anyThing", "description": "Does a thing with any control byte.", "effect": "configuration", "idempotent": true, "number": "0x64",
      "parameters": [{"name": "control", "description": "The control byte.", "byte": 1}, {"name": "group", "description": "The group.", "byte": 2}]}]
    """#, to: "serialCommands")

    #expect(try Fixtures.problems(commandSet) == [
      "the startThing serial command and the anyThing serial command can match the same frame, so they need the same effect and idempotent",
      "the deleteThing serial command and the anyThing serial command can match the same frame, so they need the same effect and idempotent"
    ])
  }

  // SerialCommandRuleTests.test_a_read_only_serial_command_may_not_match_every_frame_a_write_does
  @Test func aReadOnlySerialCommandMayNotMatchEveryFrameAWriteDoes() throws {
    let commandSet = try Fixtures.serialCommandSet().appending(#"""
    [{"name": "readAny", "description": "Reads any.", "effect": "readOnly", "idempotent": true, "number": "0x6F",
      "parameters": [{"name": "control", "description": "The control byte.", "byte": 1}]},
     {"name": "writeOne", "description": "Writes one.", "effect": "destructive", "idempotent": true, "number": "0x6F",
      "fixed": [{"position": 1, "value": "0x80"}]}]
    """#, to: "serialCommands")

    #expect(try Fixtures.problems(commandSet) == ["the readAny serial command is readOnly, but it matches every frame the writeOne serial command does"])
  }

  // SerialCommandRuleTests.test_serial_commands_with_one_number_need_one_payload_length
  @Test func serialCommandsWithOneNumberNeedOnePayloadLength() throws {
    let commandSet = try Fixtures.serialCommandSet().setting(Self.serialSteps("deleteThing") + ["parameters"], "[]")

    #expect(try Fixtures.problems(commandSet) == ["the startThing and deleteThing serial commands share number 0x64 but differ in payload length"])
  }

  // SerialCommandRuleTests.test_a_payload_byte_must_be_fixed_or_a_parameter
  @Test func aPayloadByteMustBeFixedOrAParameter() throws {
    let commandSet = try Fixtures.serialCommandSet()
      .setting(Self.serialSteps("startThing") + ["fixed"], "[]")
      .setting(Self.serialSteps("deleteThing") + ["fixed"], "[]")
      .setting(Self.serialSteps("deleteThing") + ["number"], "\"0x65\"")

    #expect(try Fixtures.problems(commandSet) == [
      "the startThing serial command: payload byte 1 is neither fixed nor a parameter",
      "the deleteThing serial command: payload byte 1 is neither fixed nor a parameter"
    ])
  }

  // SerialCommandRuleTests.test_a_payload_byte_is_filled_once
  @Test func aPayloadByteIsFilledOnce() throws {
    let commandSet = try Fixtures.serialCommandSet().setting(Self.serialSteps("startThing") + ["parameters", .index(0), "byte"], "1")

    #expect(try Fixtures.problems(commandSet) == [
      "the startThing serial command: it fills a payload byte twice",
      "the startThing and deleteThing serial commands share number 0x64 but differ in payload length"
    ])
  }

  // SerialCommandRuleTests.test_a_reply_reads_a_payload_byte_once
  @Test func aReplyReadsAPayloadByteOnce() throws {
    let commandSet = try Fixtures.serialCommandSet().appending(
      to: Self.serialSteps("readInfo") + ["reply"], #"[{"name": "again", "description": "Again.", "byte": 2}]"#
    )

    #expect(try Fixtures.problems(commandSet) == ["the readInfo serial command's reply reads a payload byte twice"])
  }

  // SerialCommandRuleTests.test_a_serial_command_value_names_a_payload_byte
  @Test func aSerialCommandValueNamesAPayloadByte() throws {
    let commandSet = try Fixtures.serialCommandSet().removing(Self.serialSteps("startThing") + ["parameters", .index(0), "byte"])

    #expect(try Fixtures.problems(commandSet) == [
      "the startThing serial command: the group value needs a byte or bytes",
      "the startThing and deleteThing serial commands share number 0x64 but differ in payload length"
    ])
  }

  // SerialCommandRuleTests.test_a_serial_command_name_is_not_used_twice
  @Test func aSerialCommandNameIsNotUsedTwice() throws {
    let commandSet = try Fixtures.serialCommandSet().setting(["standardCommands"], #"""
    [{"name": "readInfo", "description": "A clash.", "effect": "readOnly", "idempotent": true, "command1": "0x19"}]
    """#)

    #expect(try Fixtures.problems(commandSet) == ["a command or message name appears more than once"])
  }
}
