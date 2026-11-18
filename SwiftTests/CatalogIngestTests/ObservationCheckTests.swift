import CatalogIngest
import CatalogJSON
import Foundation
import Testing

struct ObservationCheckTests {
  static let models: Set<String> = ["2457D2", "2450", "2635-222"]

  func errors(_ data: JSONValue, models: Set<String> = []) -> [String] {
    ObservationCheck.problems(in: data, models: models)
  }

  static let benchFiles = ["dimmer-plug-2457D2.json", "example-invented-product.json", "io-module-2450.json", "on-off-plug-2635-222.json", "silent-sensor.json"]

  @Test(arguments: benchFiles)
  func everyBenchFileIsValid(name: String) {
    #expect(errors(Fixtures.bench(name), models: Self.models) == [])
  }

  @Test func aFileWhereNothingAnsweredIsValid() {
    let data = Fixtures.bench("silent-sensor.json")

    #expect(data["device"]?["firmware"] == .null)
    #expect(errors(data) == [])
  }

  @Test func aNewerFormatVersionIsRejectedNotGuessedAt() {
    let data = Fixtures.bench("io-module-2450.json").setting("format", to: .string("insteon-observation/2"))

    #expect(errors(data) == ["unsupported format version; this tool reads insteon-observation/1"])
  }

  @Test func aFileOfAnotherFormatIsRejected() {
    #expect(errors(json(#"{"format": "something-else"}"#)) == ["not an insteon-observation/1 file"])
    #expect(errors(json("{}")) == ["not an insteon-observation/1 file"])
  }

  @Test func aMissingFieldIsNamed() {
    let data = Fixtures.bench("io-module-2450.json").setting("observedOn", to: nil)

    #expect(errors(data) == ["$: 'observedOn' is a required property"])
  }

  @Test func aFieldTheFormatDoesNotHaveIsRejectedWithoutQuotingIt() {
    let data = Fixtures.bench("io-module-2450.json").setting("hubAddress", to: .string("value"))
    let found = errors(data)

    #expect(found.count == 1)
    #expect(!found[0].contains("hubAddress"))
  }

  @Test func aMalformedProductKeyIsRejectedWithoutQuotingIt() {
    let data = Fixtures.bench("io-module-2450.json").setting("productKey", to: .string("0xZZZZZZ"))
    let found = errors(data)

    #expect(found.count == 1)
    #expect(found[0].contains("$.productKey"))
    #expect(!found[0].contains("ZZZZZZ"))
  }

  @Test(arguments: [("category", "7"), ("subcategory", "0x7"), ("firmware", "0x3b")])
  func identityBytesMustBeWrittenAsTheCatalogWritesThem(field: String, value: String) {
    let data = Fixtures.bench("io-module-2450.json").setting(["device", field], to: .string(value))
    let found = errors(data)

    #expect(found.count == 1)
    #expect(found[0].contains("$.device.\(field)"))
  }

  @Test func anEngineMustBeOneTheProtocolHas() {
    let data = Fixtures.bench("io-module-2450.json").setting(["device", "engine"], to: .string("i4"))

    #expect(errors(data).count == 1)
  }

  @Test func aDateThatDoesNotExistIsRejected() {
    let data = Fixtures.bench("io-module-2450.json").setting("observedOn", to: .string("2026-13-45"))

    #expect(errors(data) == ["$.observedOn: not a calendar date"])
  }

  @Test(arguments: [("2026-02-30", false), ("2023-02-29", false), ("2024-02-29", true), ("0000-01-01", false), ("9999-12-31", true), ("2026-00-10", false), ("2026-01-00", false), ("2026-04-31", false), ("2100-02-29", false), ("2000-02-29", true)])
  func aDateIsValidWhenTheCalendarHasIt(date: String, valid: Bool) {
    let data = Fixtures.bench("io-module-2450.json").setting("observedOn", to: .string(date))

    #expect(errors(data).isEmpty == valid, "\(date)")
  }

  @Test func theFreeTextHasALengthLimit() {
    let data = Fixtures.bench("example-invented-product.json")
      .setting("note", to: .string(String(repeating: "a", count: 281)))
      .setting(["checks", "0", "detail"], to: .string(String(repeating: "b", count: 201)))

    #expect(errors(data) == ["$.note: longer than 280 characters", "$.checks[0].detail: longer than 200 characters"])
  }

  @Test func theLimitCountsCharactersNotBytes() {
    let within = Fixtures.bench("example-invented-product.json").setting("note", to: .string(String(repeating: "\u{00E9}", count: 280)))
    let beyond = Fixtures.bench("example-invented-product.json").setting("note", to: .string(String(repeating: "\u{1F600}", count: 281)))

    #expect(errors(within) == [])
    #expect(errors(beyond) == ["$.note: longer than 280 characters"])
  }

  @Test func aFileCannotHoldMoreThanSixteenChecks() {
    let data = Fixtures.bench("io-module-2450.json")
    let check = data["checks"]?[0] ?? .null

    #expect(errors(data.setting("checks", to: .array(Array(repeating: check, count: 16)))) == [])
    #expect(errors(data.setting("checks", to: .array(Array(repeating: check, count: 20)))) == ["$.checks: more than 16 checks"])
  }

  @Test(arguments: leaks)
  func anAddressHostOrPathInANoteIsRejectedWithoutBeingQuoted(name: String, leak: String) {
    let data = Fixtures.bench("example-invented-product.json").setting("note", to: .string("On the bench next to \(leak) here."))
    let found = errors(data)

    #expect(found.count == 1, "\(name): \(found)")
    #expect(found.first?.hasPrefix("$.note: contains what looks like ") == true, "\(name)")
    #expect(!found.joined(separator: " ").contains(leak), "\(name)")
  }

  @Test func aLeakInACheckDetailIsRejectedAndTheCheckIsNamed() {
    let data = Fixtures.bench("example-invented-product.json").setting(["checks", "2", "detail"], to: .string("Answered by 2F.9A.C1."))
    let found = errors(data)

    #expect(found.count == 1)
    #expect(found[0].hasPrefix("$.checks[2].detail: "))
    #expect(!found[0].contains("2F.9A.C1"))
  }

  @Test func aLeakInTheToolOrCatalogFieldsIsRejected() {
    let data = Fixtures.bench("example-invented-product.json")
      .setting(["tool", "version"], to: .string("10.0.0.7"))
      .setting(["catalog", "version"], to: .string("user@example.test"))

    #expect(errors(data) == [
      "$.catalog.version: contains what looks like an email address; remove it and run the observation again",
      "$.tool.version: contains what looks like an IP address; remove it and run the observation again"
    ])
  }

  @Test(arguments: plainTexts)
  func plainTextPassesTheScan(text: String) {
    let data = Fixtures.bench("example-invented-product.json").setting("note", to: .string(text))

    #expect(errors(data) == [])
  }

  @Test func aSerialNumberLikeTokenInANoteIsRejected() {
    let data = Fixtures.bench("example-invented-product.json").setting("note", to: .string("Label reads SN12345678 on the back."))

    #expect(errors(data) == ["$.note: contains what looks like a serial number; remove it and run the observation again"])
  }

  @Test func aSerialNumberLikeTokenOutsideTheNoteIsNotLookedFor() {
    let data = Fixtures.bench("example-invented-product.json").setting(["checks", "0", "detail"], to: .string("Label reads SN12345678 on the back."))

    #expect(errors(data) == [])
  }

  @Test func theIdentityTheProductKeyAndTheFlagBytesAreNotScanned() {
    let data = Fixtures.bench("example-invented-product.json")

    #expect(data["productKey"] == .string("0x00001A"))
    #expect(errors(data) == [])
  }

  @Test func aModelNameThatHoldsACatalogModelIsNotAnAddress() {
    let data = Fixtures.bench("dimmer-plug-2457D2.json")

    #expect(errors(data).count == 1)
    #expect(errors(data, models: ["2457D2"]) == [])
  }

  @Test func anAddressInTheModelNameIsRejectedEvenWithModelsKnown() {
    let data = Fixtures.bench("dimmer-plug-2457D2.json").setting(["device", "model"], to: .string("Dimmer Plug 2457D2 at 2F9AC1"))

    #expect(errors(data, models: ["2457D2"]).count == 1)
  }

  @Test func theModelAllowanceAppliesOnlyToTheModelName() {
    let data = Fixtures.bench("example-invented-product.json").setting("note", to: .string("Unit 2457D2 here"))

    #expect(errors(data, models: ["2457D2"]).count == 1)
  }

  @Test func aLeakInAFieldTheFormatDoesNotHaveIsNamedByItsKeyOnly() {
    let data = Fixtures.bench("example-invented-product.json").setting("hubAddress", to: .string("2F.9A.C1"))
    let found = errors(data)

    #expect(found.contains("$.hubAddress: contains what looks like an Insteon address; remove it and run the observation again"))
    #expect(found.allSatisfy { !$0.contains("2F.9A.C1") })
  }

  @Test func theScanRunsEvenWhenTheSchemaFindsErrors() {
    let data = Fixtures.bench("example-invented-product.json")
      .setting("observedOn", to: nil)
      .setting("note", to: .string("At 192.168.7.20 here."))

    #expect(errors(data) == [
      "$: 'observedOn' is a required property",
      "$.note: contains what looks like an IP address; remove it and run the observation again"
    ])
  }

  @Test func theValueRulesWaitForTheSchemaToPass() {
    let data = Fixtures.bench("io-module-2450.json")
      .setting("observedOn", to: .string("2026-13-45"))
      .setting(["device", "engine"], to: .int(2))

    #expect(errors(data).count == 1)
    #expect(errors(data).first?.hasPrefix("$.device.engine: ") == true)
  }
}

let leaks: [(String, String)] = [
  ("dotted address", "2F.9A.C1"),
  ("bare address", "2F9AC1"),
  ("upper-case letter address", "FACADE"),
  ("IPv4 address", "192.168.7.20"),
  ("IPv6 address", "fe80::1:2:3:4"),
  ("MAC address", "a4:5e:60:11:22:33"),
  ("URL", "https://hub.example.test/status"),
  ("host name", "hub.example.com"),
  ("email address", "someone@example.test"),
  ("home path", "/Users/someone/notes.txt"),
  ("Linux path", "/home/someone/notes"),
  ("Windows path", "C:\\Users\\someone")
]

let plainTexts = [
  "Fresh battery, device on the bench.",
  "Seen on a device running firmware 0x34, key 0x00001A.",
  "Tested at 12:30 with a decade of use.",
  "I/O Module 2450 (I/O Linc)",
  "It reported 2A 00."
]
