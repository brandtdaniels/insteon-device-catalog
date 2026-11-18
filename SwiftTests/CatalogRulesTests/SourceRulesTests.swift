import CatalogJSON
import CatalogRules
import Testing

/// The citation rule: every `sources` string is a registered title. Ports the source tests of the
/// Python `DocumentRegistryTests`.
struct SourceRulesTests {
  static let titles = RegisteredTitles(["Leak Sensor Developer Notes"])

  // DocumentRegistryTests.test_a_registered_title_is_accepted
  @Test func aRegisteredTitleIsAccepted() throws {
    let data = try JSONParser.parse(#"{"sources": ["Leak Sensor Developer Notes"]}"#)

    #expect(SourceRules.problems(label: "2852.json", in: data, titles: Self.titles) == [])
  }

  // DocumentRegistryTests.test_an_unregistered_title_names_the_file_and_the_string
  @Test func anUnregisteredTitleNamesTheFileAndTheString() throws {
    let data = try JSONParser.parse(#"{"sources": ["Leak Sensor Developer Notes (draft)"]}"#)

    #expect(SourceRules.problems(label: "2852.json", in: data, titles: Self.titles) == [
      "2852.json: source 'Leak Sensor Developer Notes (draft)' is not in documents/registry.json; register the document or cite its exact title"
    ])
  }

  // DocumentRegistryTests.test_a_title_matches_exactly
  @Test(arguments: ["leak sensor developer notes", "Leak Sensor Developer Notes ", "Leak Sensor  Developer Notes"])
  func aTitleMatchesExactly(near: String) throws {
    let data = JSONValue.object([JSONMember(key: "sources", value: .array([.string(near)]))])

    #expect(SourceRules.problems(label: "2852.json", in: data, titles: Self.titles).count == 1)
  }

  @Test func aTitleMatchesByCodePointsNotByCanonicalEquivalence() throws {
    let registered = RegisteredTitles(["Caf\u{E9} Manual"])
    let decomposed = JSONValue.object([JSONMember(key: "sources", value: .array([.string("Cafe\u{301} Manual")]))])
    let precomposed = JSONValue.object([JSONMember(key: "sources", value: .array([.string("Caf\u{E9} Manual")]))])

    #expect(SourceRules.problems(label: "a.json", in: decomposed, titles: registered).count == 1)
    #expect(SourceRules.problems(label: "a.json", in: precomposed, titles: registered) == [])
  }

  // DocumentRegistryTests.test_nested_sources_are_checked
  @Test func nestedSourcesAreChecked() throws {
    let data = try JSONParser.parse(#"{"commands": [{"name": "x", "sources": ["Missing Title"]}]}"#)

    #expect(SourceRules.problems(label: "set.json", in: data, titles: RegisteredTitles([])).count == 1)
  }

  @Test func aSourcesStringThatIsNotInAListIsChecked() throws {
    let data = try JSONParser.parse(#"{"sources": "Missing"}"#)

    #expect(SourceRules.problems(label: "f.json", in: data, titles: RegisteredTitles([])) == [
      "f.json: source 'Missing' is not in documents/registry.json; register the document or cite its exact title"
    ])
  }

  @Test func onlyStringsUnderSourcesAreChecked() throws {
    let data = try JSONParser.parse(#"{"notes": ["Missing"], "sources": [{"notes": "Missing"}, 3, null]}"#)

    #expect(SourceRules.problems(label: "f.json", in: data, titles: RegisteredTitles([])) == [])
  }

  @Test func eachUnregisteredStringIsReportedInFileOrder() throws {
    let data = try JSONParser.parse(#"{"sources": ["B", "A"], "x": {"sources": ["C", "A"]}}"#)

    #expect(SourceRules.problems(label: "f.json", in: data, titles: RegisteredTitles(["A"])).map { $0.split(separator: ";")[0] } == [
      "f.json: source 'B' is not in documents/registry.json",
      "f.json: source 'C' is not in documents/registry.json"
    ])
  }
}
