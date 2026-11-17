import CatalogSweep
import Testing

/// How the sweep sets the Swift rules' lines against the Python build's.
struct ComparisonTests {
  @Test func schemaErrorsAreKeyedByFileAndPathWithoutTheMessage() {
    let outcome = Comparison.outcome(of: [
      "b.json: $.name: 'x' is not of type 'integer'",
      "a.json: $: 'id' is a required property",
      "a.json: the file name must be the id, 'b'"
    ])

    #expect(outcome.schemaErrors == ["a.json: $", "b.json: $.name"])
    #expect(outcome.ruleMessages == ["a.json: the file name must be the id, 'b'"])
  }

  @Test func linesOfTheChecksTheRulesDoNotCoverAreLeftOut() {
    let outcome = Comparison.outcome(of: [
      "x.json: 'INSTEON' in name; use Insteon",
      "x.json: source 'A guide' is not in documents/registry.json; register the document or cite its exact title",
      "devices/x.json: has an em or en dash; use a hyphen, comma or colon",
      "x.json: a capability kind appears more than once"
    ])

    #expect(outcome.ruleMessages == ["x.json: a capability kind appears more than once"])
    #expect(outcome.schemaErrors == [])
  }

  @Test func ruleMessagesMustMatchInOrder() {
    let first = Comparison.outcome(of: ["a.json: one", "a.json: two"])
    let second = Comparison.outcome(of: ["a.json: two", "a.json: one"])

    #expect(!Comparison.agree(swift: first, python: second))
    #expect(Comparison.agree(swift: first, python: first))
  }

  @Test func aSwiftSchemaErrorBelowAPythonOneMatches() {
    #expect(Comparison.schemaErrorsMatch(
      swift: ["a.json: $.capabilities[0].events[0]"], python: ["a.json: $.capabilities[0]"]
    ))
  }

  @Test func aSwiftSchemaErrorAboveAPythonOneDoesNot() {
    #expect(!Comparison.schemaErrorsMatch(
      swift: ["a.json: $.capabilities[0]"], python: ["a.json: $.capabilities[0].events[0]"]
    ))
  }

  @Test func aPathThatOnlySharesATextPrefixIsAnotherPlace() {
    #expect(!Comparison.schemaErrorsMatch(swift: ["a.json: $.capabilities[10]"], python: ["a.json: $.capabilities[1]"]))
  }

  @Test func aFileOneSideFlagsAndTheOtherDoesNotDoesNotMatch() {
    #expect(!Comparison.schemaErrorsMatch(swift: [], python: ["a.json: $.name"]))
    #expect(!Comparison.schemaErrorsMatch(swift: ["a.json: $.name"], python: []))
  }

  @Test func linesNotInCountsRepeats() {
    #expect(Comparison.lines(["a", "a", "b"], notIn: ["a"]) == ["a", "b"])
  }
}
