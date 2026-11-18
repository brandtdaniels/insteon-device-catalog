import CatalogIngest
import CatalogSweep
import Foundation
import Testing

/// The Swift tool against the bytes the Python tool produced for the same cases: its exit status, what
/// it printed, the reports it wrote and the profiles it patched.
struct GoldenTests {
  static let book = IngestCaseBook(fixtures: Fixtures.observations)
  static let cases = (try? book.cases()) ?? []
  static let applyCases = ApplyCaseBook.cases

  static func expected(_ path: String) throws -> IngestGolden {
    let bytes = Array(try Data(contentsOf: Fixtures.golden.appendingPathComponent(path)))

    return try #require(IngestGolden.parse(bytes))
  }

  static func differences(_ actual: IngestGolden, _ expected: IngestGolden) -> [String] {
    var found: [String] = []

    if actual.parts.map(\.name) != expected.parts.map(\.name) {
      found.append("parts \(actual.parts.map(\.name)) instead of \(expected.parts.map(\.name))")
    }

    for part in expected.parts where actual[part.name] != part.text {
      found.append("\(part.name):\n--- expected\n\(part.text)\n--- actual\n\(actual[part.name] ?? "(none)")")
    }

    return found
  }

  @Test func everyCaseHasAGolden() {
    #expect(Self.cases.count >= 100)
    #expect(Set(Self.cases.map(\.name)).count == Self.cases.count)
    #expect(Set(Self.applyCases.map(\.name)).count == Self.applyCases.count)
  }

  @Test(arguments: cases)
  func checkAndDraftCasesMatchThePythonTool(ingestCase: IngestCase) throws {
    let prepared = try ingestCase.prepare(catalogs: Fixtures.catalogs)
    let tool = IngestTool(root: prepared.root)
    let result: IngestResult

    switch ingestCase.action {
    case .check:
      result = tool.check(prepared.inputs)
    case .draft:
      result = tool.draft(prepared.inputs, report: prepared.report, markdown: prepared.markdown)
    }

    let actual = prepared.golden(after: IngestRun(status: result.status, standardOutput: result.output))
    let expected = try Self.expected("cases/\(ingestCase.name).golden")

    #expect(Self.differences(actual, expected) == [], "\(ingestCase.name)")
  }

  @Test(arguments: applyCases)
  func applyCasesMatchThePythonTool(applyCase: ApplyCase) throws {
    let expected = try Self.expected("apply/\(applyCase.name).golden")
    let prepared = try #require(try applyCase.prepare(catalogs: Fixtures.catalogs, repository: nil, drafted: IngestCapture.reader(Fixtures.golden)))
    let checker = GoldenChecker(failing: applyCase.buildFails, expectedOutput: expected["stdout"])
    let tool = IngestTool(root: prepared.root, checker: checker)

    var result = tool.apply(report: prepared.report)

    if prepared.appliesTwice {
      try prepared.commitChanges()
      result = tool.apply(report: prepared.report)
    }

    let actual = try prepared.golden(after: IngestRun(status: result.status, standardOutput: result.output))

    #expect(Self.differences(actual, expected) == [], "\(applyCase.name)")
  }
}

/// The catalog check as the golden's run left it: passing, or failing with what the Python build said.
struct GoldenChecker: CatalogChecking {
  let failing: Bool
  let expectedOutput: String?

  func check(root: URL) -> CatalogCheckResult {
    guard failing else { return CatalogCheckResult(passed: true, output: "") }
    let lines = (expectedOutput ?? "").split(separator: "\n", omittingEmptySubsequences: false).dropFirst()

    return CatalogCheckResult(passed: false, output: lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
  }
}

/// Where the Swift tool is stricter or reads a position differently than the Python tool, on purpose.
/// Each case's Python golden is kept in `known-differences` to show what the Python tool said.
struct KnownDifferenceTests {
  static func output(_ name: String) throws -> String {
    let ingestCase = try #require(try GoldenTests.book.knownDifferenceCases().first { $0.name == name })
    let prepared = try ingestCase.prepare(catalogs: Fixtures.catalogs)

    return IngestTool(root: prepared.root).check(prepared.inputs).output
  }

  @Test func aPatternEndsAtTheEndOfTheText() throws {
    #expect(try Self.output("check-a-pattern-ends-at-the-end-of-the-text") == """
      observation 1 (17205bf7): not valid
        $.observedOn: is not written the way the format requires
      observation 2 (5b6f810e): not valid
        $.productKey: is not written the way the format requires
      observation 3 (9d1ab9ac): not valid
        $.operatingFlags.raw: is not written the way the format requires

      """)
  }

  @Test func jsonThePythonReaderAcceptsIsRefused() throws {
    #expect(try Self.output("check-json-the-python-reader-accepts") == """
      observation 1 (290c3f14): not valid
        the file is not valid JSON (line 1, column 37)
      observation 2 (e40f7f0a): not valid
        the file is not valid JSON (line 1, column 10)
      observation 3 (1db8224b): not valid
        the file is not valid JSON (line 1, column 10)
      observation 4 (395ec54c): not valid
        the file is not valid JSON (line 1, column 10)
      observation 5 (3d6bf7c1): not valid
        the file is not valid JSON (line 1, column 11)
      observation 6 (8de3bd0e): not valid
        the file is not valid JSON (line 1, column 10)
      observation 7 (726cf2ea): not valid
        the file is not valid JSON (line 1, column 10)

      """)
  }

  @Test func aJSONErrorIsPlacedAtTheCharacterThatBreaksTheRule() throws {
    #expect(try Self.output("check-json-error-positions") == """
      observation 1 (6e961bb3): not valid
        the file is not valid JSON (line 1, column 10)
      observation 2 (536a12a5): not valid
        the file is not valid JSON (line 1, column 9)
      observation 3 (ef602461): not valid
        the file is not valid JSON (line 1, column 13)

      """)
  }
}
