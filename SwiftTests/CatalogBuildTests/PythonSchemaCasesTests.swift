import CatalogBuild
import CatalogJSON
import CatalogSchema
import Foundation
import Testing

/// The schema failure cases of the Python build's tests (`tests/test_build.py`), run against the
/// Swift validator with the same inputs.
struct PythonSchemaCasesTests {
  static let root = RepositoryRoot(url: CatalogRepository.url)

  static func commandSet(_ id: String) throws -> JSONValue {
    try #require(try root.commandSetFiles().first { $0.stem == id }).value
  }

  static func profile(_ model: String) throws -> JSONValue {
    try #require(try root.deviceFiles().first { $0.stem == model }).value
  }

  static func commandSetErrors(_ value: JSONValue) throws -> [SchemaError] {
    try SchemaValidator(schema: root.schema(.commandSet)).errors(in: value)
  }

  static func profileErrors(_ value: JSONValue) throws -> [SchemaError] {
    try SchemaValidator(schema: root.schema(.deviceProfile)).errors(in: value)
  }

  /// An invented command set with serial commands, as the Python tests build it.
  static func serialCommandSet() throws -> JSONValue {
    try JSONParser.parse(#"""
    {"id": "invented", "name": "Invented", "description": "An invented modem.", "sources": ["An invented guide"],
     "serialCommands": [
       {"name": "readInfo", "description": "Asks for the identity.", "effect": "readOnly", "idempotent": true, "number": "0x60",
        "reply": [{"name": "identity", "description": "The identity.", "bytes": [1, 2, 3]}]},
       {"name": "startThing", "description": "Starts a thing.", "effect": "link", "idempotent": false, "number": "0x64",
        "fixed": [{"position": 1, "value": "0x01"}], "parameters": [{"name": "group", "description": "The group.", "byte": 2}]},
       {"name": "deleteThing", "description": "Deletes a thing.", "effect": "destructive", "idempotent": true, "number": "0x64",
        "fixed": [{"position": 1, "value": "0xFF"}], "parameters": [{"name": "group", "description": "The group.", "byte": 2}]}
     ]}
    """#)
  }

  // EffectSchemaTests.test_a_flag_command_without_an_effect_fails_the_schema
  @Test func aFlagCommandWithoutAnEffectFailsTheSchema() throws {
    let base = try Self.commandSet("globalLine")
    let steps = base.steps(toNamed: "yakityYakOff", in: "flagCommands")
    let errors = try Self.commandSetErrors(base.changing(steps + [.key("effect")], to: nil))

    #expect(errors.map(\.message) == ["'effect' is a required property"])
    #expect(errors.map(\.keyword) == ["required"])
    #expect(errors.first?.path.hasPrefix("$.flagCommands[") == true)
  }

  // EffectSchemaTests.test_a_standard_command_without_idempotent_fails_the_schema
  @Test func aStandardCommandWithoutIdempotentFailsTheSchema() throws {
    let base = try Self.commandSet("globalLine")
    let steps = base.steps(toNamed: "lightOn", in: "standardCommands")
    let errors = try Self.commandSetErrors(base.changing(steps + [.key("idempotent")], to: nil))

    #expect(errors.map(\.message) == ["'idempotent' is a required property"])
    #expect(errors.first?.path.hasPrefix("$.standardCommands[") == true)
  }

  // EffectSchemaTests.test_an_extended_command_with_an_effect_the_schema_does_not_name_fails
  @Test func anExtendedCommandWithAnEffectTheSchemaDoesNotNameFails() throws {
    let base = try Self.commandSet("globalLine")
    let steps = base.steps(toNamed: "triggerGroup", in: "extendedCommands")
    let errors = try Self.commandSetErrors(base.changing(steps + [.key("effect")], to: .string("sideEffect")))

    #expect(errors.map(\.message) == ["'sideEffect' is not one of ['readOnly', 'configuration', 'link', 'actuation', 'destructive']"])
    #expect(errors.map(\.keyword) == ["enum"])
    #expect(errors.first?.path.hasSuffix(".effect") == true)
  }

  // EffectSchemaTests.test_a_raw_keep_awake_message_without_an_effect_fails_the_schema
  @Test func aRawKeepAwakeMessageWithoutAnEffectFailsTheSchema() throws {
    let base = try Self.profile("2441ZTH")
    let errors = try Self.profileErrors(base.changing([.key("lifecycle"), .key("fromHub"), .key("keepAwake"), .key("send"), .key("effect")], to: nil))

    #expect(!errors.isEmpty)
    #expect(errors.allSatisfy { $0.path.hasPrefix("$.lifecycle.fromHub.keepAwake.send") })
  }

  // EffectSchemaTests.test_a_raw_keep_awake_message_without_idempotent_fails_the_schema
  @Test func aRawKeepAwakeMessageWithoutIdempotentFailsTheSchema() throws {
    let base = try Self.profile("2441ZTH")
    let errors = try Self.profileErrors(base.changing([.key("lifecycle"), .key("fromHub"), .key("keepAwake"), .key("release"), .key("idempotent")], to: nil))

    #expect(!errors.isEmpty)
    #expect(errors.allSatisfy { $0.path.hasPrefix("$.lifecycle.fromHub.keepAwake.release") })
  }

  // EffectSchemaTests.test_a_named_keep_awake_message_carries_no_effect_of_its_own
  @Test func aNamedKeepAwakeMessageCarriesNoEffectOfItsOwn() throws {
    let base = try Self.profile("2852")
    let errors = try Self.profileErrors(base.changing([.key("lifecycle"), .key("fromHub"), .key("keepAwake"), .key("send"), .key("effect")], to: .string("configuration")))

    #expect(!errors.isEmpty)
    #expect(errors.allSatisfy { $0.path.hasPrefix("$.lifecycle.fromHub.keepAwake.send") })
  }

  // SerialCommandSchemaTests.test_a_serial_command_set_passes
  @Test func aSerialCommandSetPasses() throws {
    #expect(try Self.commandSetErrors(Self.serialCommandSet()) == [])
  }

  // SerialCommandSchemaTests.test_a_serial_command_without_an_effect_fails_the_schema
  @Test func aSerialCommandWithoutAnEffectFailsTheSchema() throws {
    let base = try Self.serialCommandSet()
    let steps = base.steps(toNamed: "readInfo", in: "serialCommands")
    let errors = try Self.commandSetErrors(base.changing(steps + [.key("effect")], to: nil))

    #expect(errors.map(\.message) == ["'effect' is a required property"])
    #expect(errors.map(\.path) == ["$.serialCommands[0]"])
  }

  // SerialCommandSchemaTests.test_a_serial_command_without_idempotent_fails_the_schema
  @Test func aSerialCommandWithoutIdempotentFailsTheSchema() throws {
    let base = try Self.serialCommandSet()
    let steps = base.steps(toNamed: "readInfo", in: "serialCommands")
    let errors = try Self.commandSetErrors(base.changing(steps + [.key("idempotent")], to: nil))

    #expect(errors.map(\.message) == ["'idempotent' is a required property"])
    #expect(errors.map(\.path) == ["$.serialCommands[0]"])
  }

  // SerialCommandSchemaTests.test_a_serial_command_without_a_number_fails_the_schema
  @Test func aSerialCommandWithoutANumberFailsTheSchema() throws {
    let base = try Self.serialCommandSet()
    let steps = base.steps(toNamed: "readInfo", in: "serialCommands")
    let errors = try Self.commandSetErrors(base.changing(steps + [.key("number")], to: nil))

    #expect(errors.map(\.message) == ["'number' is a required property"])
    #expect(errors.map(\.path) == ["$.serialCommands[0]"])
  }

  // SerialCommandSchemaTests.test_a_serial_command_with_an_effect_the_schema_does_not_name_fails
  @Test func aSerialCommandWithAnEffectTheSchemaDoesNotNameFails() throws {
    let base = try Self.serialCommandSet()
    let steps = base.steps(toNamed: "readInfo", in: "serialCommands")
    let errors = try Self.commandSetErrors(base.changing(steps + [.key("effect")], to: .string("sideEffect")))

    #expect(errors.map(\.message) == ["'sideEffect' is not one of ['readOnly', 'configuration', 'link', 'actuation', 'destructive']"])
    #expect(errors.map(\.path) == ["$.serialCommands[0].effect"])
  }

  // SerialCommandSchemaTests.test_a_serial_command_has_no_cmd1
  @Test func aSerialCommandHasNoCmd1() throws {
    let base = try Self.serialCommandSet()
    let steps = base.steps(toNamed: "readInfo", in: "serialCommands")
    let errors = try Self.commandSetErrors(base.changing(steps + [.key("command1")], to: .string("0x11")))

    #expect(errors.map(\.message) == ["Additional properties are not allowed ('command1' was unexpected)"])
    #expect(errors.map(\.path) == ["$.serialCommands[0]"])
  }
}
