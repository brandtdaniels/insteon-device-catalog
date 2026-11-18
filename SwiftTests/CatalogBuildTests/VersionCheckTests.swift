import CatalogBuild
import Testing

/// The version rule: a change to the schemas needs a higher MAJOR.MINOR in `VERSION`.
struct VersionCheckTests {
  static let base = "abc123"

  /// Runs the rule with the base's `VERSION` (`nil` when the base has none), the current text and the changed paths.
  static func problem(
    base baseVersion: String?, current: String, changed: [String]? = []
  ) -> VersionProblem? {
    var git = FakeGit(changed: changed)
    if let baseVersion { git.files["\(base):VERSION"] = baseVersion }
    do {
      try VersionCheck(git: git).verify(base: base, current: current)
      return nil
    } catch {
      return error
    }
  }

  @Test func passesWhenNoSchemaChangedAndVersionIsTheSame() {
    #expect(Self.problem(base: "0.10\n", current: "0.10\n", changed: ["devices/2442.json"]) == nil)
  }

  @Test func passesWhenSchemaChangedWithAMinorBump() {
    #expect(Self.problem(base: "0.10\n", current: "0.11\n", changed: ["schema/device-profile.json"]) == nil)
  }

  @Test func passesWhenSchemaChangedWithAMajorBump() {
    #expect(Self.problem(base: "0.10\n", current: "1.0\n", changed: ["schema/command-set.json"]) == nil)
  }

  @Test func failsWhenSchemaChangedWithoutABump() {
    #expect(
      Self.problem(base: "0.10\n", current: "0.10\n", changed: ["schema/device-profile.json"])
        == .schemaChangedWithoutBump)
  }

  @Test func comparesMinorAsANumber() {
    #expect(Self.problem(base: "0.9\n", current: "0.10\n", changed: ["schema/a.json"]) == nil)
    #expect(Self.problem(base: "0.10\n", current: "0.9\n") == .wentDown)
  }

  @Test func ignoresLeadingZerosWhenComparing() {
    #expect(Self.problem(base: "0.10", current: "00.010", changed: ["schema/a.json"]) == .schemaChangedWithoutBump)
  }

  @Test func comparesNumbersLargerThanAnInteger() {
    let large = "0.99999999999999999999999"
    #expect(Self.problem(base: large, current: "0.100000000000000000000000", changed: ["schema/a.json"]) == nil)
  }

  @Test func failsWhenVersionWentDownWithNoSchemaChange() {
    #expect(Self.problem(base: "0.10\n", current: "0.9\n") == .wentDown)
  }

  @Test func failsWhenMajorWentDown() {
    #expect(Self.problem(base: "1.0\n", current: "0.20\n") == .wentDown)
  }

  @Test func passesWhenVersionRoseWithNoSchemaChange() {
    #expect(Self.problem(base: "0.10\n", current: "0.11\n", changed: ["devices/2442.json"]) == nil)
  }

  @Test func wentDownWinsOverASchemaChange() {
    #expect(Self.problem(base: "0.10\n", current: "0.9\n", changed: ["schema/a.json"]) == .wentDown)
  }

  @Test func countsAnAddedSchemaFile() {
    #expect(Self.problem(base: "0.10\n", current: "0.10\n", changed: ["schema/new.json"]) == .schemaChangedWithoutBump)
  }

  @Test func countsADeletedOrRenamedSchemaFile() {
    #expect(
      Self.problem(base: "0.10\n", current: "0.10\n", changed: ["schema/old.json", "documents/old.json"])
        == .schemaChangedWithoutBump)
  }

  @Test func countsANestedSchemaFile() {
    #expect(Self.problem(base: "0.10\n", current: "0.10\n", changed: ["schema/nested/a.json"]) == .schemaChangedWithoutBump)
  }

  @Test func ignoresPathsOutsideTheSchemaDirectory() {
    let outside = ["schemas/a.json", "schema.json", "devices/schema/a.json", "documents/schema", "VERSION", "README.md"]
    #expect(Self.problem(base: "0.10\n", current: "0.10\n", changed: outside) == nil)
  }

  @Test func acceptsABaseWithoutVersionEvenWhenSchemaChanged() {
    #expect(Self.problem(base: nil, current: "0.1\n", changed: ["schema/a.json"]) == nil)
  }

  @Test func acceptsABaseWithoutVersionWithNoSchemaChange() {
    #expect(Self.problem(base: nil, current: "0.1\n") == nil)
  }

  @Test(arguments: ["", "\n", "1", "1.", ".1", "1.2.3", "v1.2", "1.x", "1,2", "-1.2", "1. 2", "1.2\n3", "0.10.4"])
  func rejectsAMalformedVersion(text: String) {
    #expect(Self.problem(base: "0.10\n", current: text) == .malformed(text.trimmingWhitespace()))
  }

  @Test func rejectsAMalformedVersionBeforeAnyGitWork() {
    #expect(Self.problem(base: "0.10\n", current: "x", changed: nil) == .malformed("x"))
  }

  @Test func rejectsAMalformedBaseVersion() {
    #expect(Self.problem(base: "latest\n", current: "0.10\n") == .malformed("latest"))
  }

  @Test func acceptsSurroundingWhitespace() {
    #expect(Self.problem(base: " 0.10 \n", current: "\t0.10\r\n") == nil)
  }

  @Test func failsWhenGitCantCompareTheSchemas() {
    #expect(Self.problem(base: "0.10\n", current: "0.10\n", changed: nil) == .cannotCompare(base: Self.base))
  }

  @Test func failsWhenGitCantCompareEvenIfTheBaseHasNoVersion() {
    #expect(Self.problem(base: nil, current: "0.10\n", changed: nil) == .cannotCompare(base: Self.base))
  }

  @Test func readsTheBaseVersionAtTheBaseRevision() {
    var git = FakeGit()
    git.files["other:VERSION"] = "9.9\n"
    #expect(throws: Never.self) { try VersionCheck(git: git).verify(base: Self.base, current: "0.1\n") }
  }

  @Test func wordsEachProblemAsTheCheckReportsIt() {
    #expect(VersionProblem.malformed("x y").description == "VERSION must be MAJOR.MINOR, not 'x y'")
    #expect(VersionProblem.malformed("it's").description == #"VERSION must be MAJOR.MINOR, not "it's""#)
    #expect(VersionProblem.malformed(#"a'b"c"#).description == #"VERSION must be MAJOR.MINOR, not 'a\'b"c'"#)
    #expect(VersionProblem.malformed("a\\b\u{1}").description == #"VERSION must be MAJOR.MINOR, not 'a\\b\x01'"#)
    #expect(VersionProblem.malformed("").description == "VERSION must be MAJOR.MINOR, not ''")
    #expect(VersionProblem.wentDown.description == "VERSION went down.")
    #expect(
      VersionProblem.schemaChangedWithoutBump.description
        == "The schemas changed, so VERSION needs a higher MAJOR.MINOR.")
    #expect(VersionProblem.cannotCompare(base: "abc").description == "git couldn't compare schema with abc")
    #expect(VersionProblem.unreadable(file: "VERSION").description == "VERSION can't be read")
  }
}

extension String {
  fileprivate func trimmingWhitespace() -> String {
    var scalars = Substring(self)
    while let first = scalars.first, first.isWhitespace { scalars.removeFirst() }
    while let last = scalars.last, last.isWhitespace { scalars.removeLast() }
    return String(scalars)
  }
}
