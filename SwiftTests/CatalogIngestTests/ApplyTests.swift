import CatalogBuild
import CatalogIngest
import CatalogJSON
import Foundation
import Testing

/// A stand-in for the catalog check that records its calls and passes or fails.
final class RecordingChecker: CatalogChecking, @unchecked Sendable {
  let passes: Bool
  private(set) var roots: [URL] = []

  init(passes: Bool = true) {
    self.passes = passes
  }

  func check(root: URL) -> CatalogCheckResult {
    roots.append(root)

    return CatalogCheckResult(passed: passes, output: passes ? "" : "invented check failure")
  }
}

/// A working tree whose state a test chooses.
struct FixedTree: WorkingTreeReading {
  let lines: [String]?

  func statusLines(in root: URL) throws -> [String] {
    guard let lines else { throw TreeUnreadable() }

    return lines
  }

  struct TreeUnreadable: Error {}
}

/// A git repository that holds `devices/<model>.json` for each profile, written as the repository writes them.
func committedRepository(_ scratch: Scratch, _ profiles: [String: JSONValue]) throws -> URL {
  for (model, content) in profiles {
    try scratch.write("devices/\(model).json", ProfileFile.text(of: content))
  }

  try Git.run(scratch.url, "init", "--quiet")
  try Git.commitAll(scratch.url)

  return scratch.url
}

func draftedReport(_ catalog: ProfileCatalog, _ data: JSONValue? = nil) throws -> JSONValue {
  let scratch = try Scratch()
  let file = try scratch.write("a.json", json: data ?? observation())

  return ReportDrafting.draft([file], in: catalog).report.json
}

struct PatchingTests {
  @Test func everyProfileInTheCatalogIsWrittenBackByteForByte() throws {
    let files = try RepositoryRoot(url: Fixtures.repository).deviceFiles()

    #expect(!files.isEmpty)

    for file in files {
      let text = try String(contentsOf: Fixtures.repository.appendingPathComponent(file.path), encoding: .utf8)

      #expect(ProfileFile.text(of: file.value) == text, "\(file.name)")
    }
  }

  @Test func theTextHasTwoSpacesOfIndentCharactersAsWrittenAndOneFinalNewline() {
    let text = ProfileFile.text(of: json(#"{"a": ["café", {"b": 1}]}"#))

    #expect(text == "{\n  \"a\": [\n    \"caf\u{00E9}\",\n    {\n      \"b\": 1\n    }\n  ]\n}\n")
  }
}

struct ApplyTests {
  let scratch: Scratch
  let root: URL
  let catalog: ProfileCatalog
  let report: JSONValue

  init() throws {
    scratch = try Scratch()
    let identity = #"{"category": "0x7E", "subcategory": "0x7F", "productKey": "0x00001A", "region": "US"}"#
    catalog = inventedCatalog(identity: identity)
    var profiles = catalog.profiles
    profiles["8888"] = profile("8888", identities: #"[{"category": "0x01", "subcategory": "0x01"}]"#)
    root = try committedRepository(scratch, profiles)
    report = try draftedReport(catalog)
  }

  func apply(_ report: JSONValue? = nil, checker: RecordingChecker, tree: any WorkingTreeReading = ProcessWorkingTree(), allowed: Set<String> = []) -> ApplyOutcome {
    ReportApplication.apply(report ?? self.report, in: root, checker: checker, tree: tree, allowed: allowed)
  }

  func profileText(_ model: String = "9999") throws -> String {
    try scratch.read("devices/\(model).json")
  }

  func profileValue(_ model: String = "9999") throws -> JSONValue {
    try JSONParser.parse(try profileText(model))
  }

  @Test func theMarksAreWrittenAndTheCheckRunsOnce() throws {
    let checker = RecordingChecker()
    let outcome = apply(checker: checker)
    let written = try profileValue()

    #expect(outcome.status == 0)
    #expect(written["identities"]?[0]?["verification"]?["status"] == .string("observed"))
    #expect(written["identities"]?[0]?["productKeyVerification"]?["status"] == .string("observed"))
    #expect(written["engines"]?[0]?["verification"]?["status"] == .string("observed"))
    #expect(checker.roots == [root])
    #expect(outcome.messages == ["applied 3 changes to 1 files and the build passed", "  devices/9999.json"])
  }

  @Test func theKeyVerificationSitsNextToTheKeyAndTheFileKeepsTheRepositoryFormatting() throws {
    _ = apply(checker: RecordingChecker())
    let written = try profileValue()

    #expect(written["identities"]?[0]?.keys == ["category", "subcategory", "productKey", "productKeyVerification", "region", "verification"])
    #expect(try profileText() == ProfileFile.text(of: written))
  }

  @Test func aFileNoChangeNamesIsNotTouched() throws {
    let before = try profileText("8888")
    _ = apply(checker: RecordingChecker())

    #expect(try profileText("8888") == before)
    #expect(try Git.run(root, "diff", "--name-only").split(separator: "\n").map(String.init) == ["devices/9999.json"])
  }

  @Test func nothingButVerificationChanges() throws {
    _ = apply(checker: RecordingChecker())
    let after = try profileValue()
    let before = catalog.profiles["9999"] ?? .null

    for key in ["category", "subcategory", "productKey", "region"] {
      #expect(after["identities"]?[0]?[key] == before["identities"]?[0]?[key])
    }

    #expect(after["engines"]?[0]?.setting("verification", to: nil) == before["engines"]?[0])
  }

  @Test func aWorkingTreeWithOtherChangesIsRefusedAndNothingIsWritten() throws {
    try scratch.write("devices/8888.json", "{}\n")
    let checker = RecordingChecker()
    let outcome = apply(checker: checker)

    #expect(outcome.status == 1)
    #expect(outcome.messages == ["the working tree has changes of its own; commit or stash them first"])
    #expect(checker.roots.isEmpty)
    #expect(try profileText() == ProfileFile.text(of: catalog.profiles["9999"] ?? .null))
  }

  @Test func anUntrackedFileIsAlsoOtherWork() throws {
    try scratch.write("notes.txt", "x")

    #expect(apply(checker: RecordingChecker()).status == 1)
  }

  @Test func theReportFileItselfMayStayUntrackedInTheTree() throws {
    try scratch.write("report.json", "{}")

    #expect(apply(checker: RecordingChecker(), allowed: ["report.json"]).status == 0)
  }

  @Test func aTreeThatCannotBeReadIsRefused() {
    let checker = RecordingChecker()
    let outcome = apply(checker: checker, tree: FixedTree(lines: nil))

    #expect(outcome.status == 1)
    #expect(outcome.messages == ["cannot tell whether the working tree is clean"])
    #expect(checker.roots.isEmpty)
  }

  @Test func aTreeLineIsComparedByItsPathAfterTheStatusColumns() {
    #expect(apply(checker: RecordingChecker(), tree: FixedTree(lines: ["?? report.json"]), allowed: ["report.json"]).status == 0)
    #expect(apply(checker: RecordingChecker(), tree: FixedTree(lines: [" M devices/8888.json"]), allowed: ["report.json"]).status == 1)
  }

  @Test func aCatalogThatMovedSinceTheReportIsRefusedAndNothingIsWritten() throws {
    let moved = try profileValue().setting(["identities", "0", "verification"], to: json(observed(["0x10"])))
    try scratch.write("devices/9999.json", ProfileFile.text(of: moved))
    try Git.commitAll(root, "moved")
    let after = try profileText()
    let outcome = apply(checker: RecordingChecker())

    #expect(outcome.status == 1)
    #expect(outcome.messages == ["devices/9999.json: the entry does not hold what the report was drafted from"])
    #expect(try profileText() == after)
  }

  @Test func aReportAlreadyAppliedAndCommittedIsANoOp() throws {
    _ = apply(checker: RecordingChecker())
    try Git.commitAll(root, "applied")
    let checker = RecordingChecker()
    let outcome = apply(checker: checker)

    #expect(outcome.status == 0)
    #expect(outcome.messages == ["already applied: the catalog holds every change in the report"])
    #expect(checker.roots.isEmpty)
  }

  @Test func aFailingCheckPutsEveryFileBack() throws {
    let original = try profileText()
    let outcome = apply(checker: RecordingChecker(passes: false))

    #expect(outcome.status == 1)
    #expect(outcome.messages == ["the build failed, so every file was put back:", "invented check failure"])
    #expect(try profileText() == original)
    #expect(try Git.run(root, "status", "--porcelain") == "")
  }

  @Test func aReportWithNothingDraftedAppliesNothing() throws {
    let nothing = try draftedReport(catalog, observation(["category": .string("0x70")]))
    let checker = RecordingChecker()
    let outcome = apply(nothing, checker: checker)

    #expect(outcome.status == 0)
    #expect(outcome.messages == ["nothing to apply: the report drafts no changes"])
    #expect(checker.roots.isEmpty)
  }

  @Test func aRejectedObservationInTheReportBlocksTheWholeApply() {
    let item = json(#"{"input": "observation 2 (00000000)", "outcome": "rejected", "errors": ["x"], "changes": []}"#)
    let rejected = report.setting("observations", to: .array((report["observations"]?.elements ?? []) + [item]))
    let outcome = apply(rejected, checker: RecordingChecker())

    #expect(outcome.status == 1)
    #expect(outcome.messages == ["the report holds a rejected observation; fix it and draft again"])
  }

  @Test func aReportOfAnotherFormatIsRefused() {
    let outcome = apply(json(#"{"format": "other"}"#), checker: RecordingChecker())

    #expect(outcome == ApplyOutcome(status: 1, messages: ["not an observation report this tool wrote"]))
    #expect(apply(json("[]"), checker: RecordingChecker()).status == 1)
    #expect(apply(report.setting("lane", to: .string("other")), checker: RecordingChecker()).status == 1)
  }

  @Test func aReportWithoutAListOfObservationsIsRefused() {
    let outcome = apply(report.setting("observations", to: .string("none")), checker: RecordingChecker())

    #expect(outcome == ApplyOutcome(status: 1, messages: ["the report has no observations"]))
  }

  @Test func aChangeNamingAProfileThatCannotBeReadIsRefusedBeforeAnythingIsWritten() throws {
    try FileManager.default.removeItem(at: root.appendingPathComponent("devices/9999.json"))
    try Git.commitAll(root, "gone")
    let checker = RecordingChecker()

    #expect(apply(checker: checker) == ApplyOutcome(status: 1, messages: ["cannot read devices/9999.json"]))
    #expect(checker.roots.isEmpty)
  }

  @Test(arguments: ["status", "extra field", "free note", "line break", "no firmware", "firmware not a byte", "firmware not a list", "other field", "key verification of an engine", "other file", "other model", "other entry", "selector", "no selector", "change not an object", "after not an object"])
  func aHandEditedReportMayOnlySetAnObservedVerificationFromTheTemplate(name: String) throws {
    let change = ["observations", "0", "changes", "0"]
    let edits: [String: ([String], JSONValue?)] = [
      "status": (change + ["after", "status"], .string("documented")),
      "extra field": (change + ["after", "value"], .string("0x01")),
      "free note": (change + ["after", "note"], .string("Anything at all.")),
      "line break": (change + ["after", "note"], .string("Seen on a device running firmware 0x41: one\ntwo")),
      "no firmware": (change + ["after", "firmware"], .array([])),
      "firmware not a byte": (change + ["after", "firmware"], json(#"["0x4"]"#)),
      "firmware not a list": (change + ["after", "firmware"], .string("0x41")),
      "other field": (change + ["field"], .string("productKey")),
      "key verification of an engine": (change + ["field"], .string("productKeyVerification")),
      "other file": (change + ["file"], .string("devices/../README.md")),
      "other model": (change + ["file"], .string("devices/8888.json")),
      "other entry": (change + ["entry"], .string("commandSet")),
      "selector": (change + ["selector"], json(#"{"category": "0x7E", "subcategory": "0x7F", "name": "x"}"#)),
      "no selector": (change + ["selector"], nil),
      "change not an object": (change, .int(5)),
      "after not an object": (change + ["after"], .null)
    ]
    var (path, value) = try #require(edits[name])
    // The engine change is the second one drafted, so the engine-only tamperings aim at it.
    if name == "key verification of an engine" { path = ["observations", "0", "changes", "1", "field"]; value = .string("productKeyVerification") }
    let checker = RecordingChecker()
    let outcome = apply(report.setting(path, to: value), checker: checker)

    #expect(outcome.status == 1, "\(name)")
    #expect(try Git.run(root, "status", "--porcelain") == "", "\(name)")
    #expect(checker.roots.isEmpty, "\(name)")
  }
}

struct ApplyEndToEndTests {
  /// Drafts the bench files against a copy of this repository's catalog, applies the report and runs
  /// the real check.
  @Test func theBenchReportAppliesAndTheCatalogStillChecks() throws {
    let scratch = try Scratch()
    let copy = scratch.url.appendingPathComponent("catalog")
    try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)

    for name in ["devices", "schema", "commandSets", "documents", "templates", "VERSION"] {
      try FileManager.default.copyItem(at: Fixtures.repository.appendingPathComponent(name), to: copy.appendingPathComponent(name))
    }

    try Git.run(copy, "init", "--quiet")
    try Git.commitAll(copy)

    let files = ["dimmer-plug-2457D2.json", "io-module-2450.json", "on-off-plug-2635-222.json", "silent-sensor.json"]
      .map { Fixtures.observations.appendingPathComponent($0) }
    let catalog = try ProfileCatalog.load(from: RepositoryRoot(url: copy))
    let report = ReportDrafting.draft(files, in: catalog).report.json
    let outcome = ReportApplication.apply(report, in: copy, checker: RepositoryChecker(), tree: ProcessWorkingTree(), allowed: [])

    #expect(outcome.status == 0, "\(outcome.messages)")
    #expect(try Git.run(copy, "diff", "--name-only").split(separator: "\n").map(String.init) == ["devices/2450.json", "devices/2635-222.json"])

    let written = try JSONParser.parse(try String(contentsOf: copy.appendingPathComponent("devices/2450.json"), encoding: .utf8))
    #expect(written["engines"]?[0]?["verification"]?["status"] == .string("observed"))
  }

  @Test func theRealCheckRefusesACatalogThatBreaksARule() throws {
    let scratch = try Scratch()
    let copy = scratch.url.appendingPathComponent("catalog")
    try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)

    for name in ["devices", "schema", "commandSets", "documents", "templates", "VERSION"] {
      try FileManager.default.copyItem(at: Fixtures.repository.appendingPathComponent(name), to: copy.appendingPathComponent(name))
    }

    let healthy = RepositoryChecker().check(root: copy)
    #expect(healthy.passed)

    try scratch.write("catalog/devices/2450.json", ProfileFile.text(of: JSONValue.object([])))
    let broken = RepositoryChecker().check(root: copy)

    #expect(!broken.passed)
    #expect(broken.output.contains("devices") || broken.output.contains("2450.json"))
  }
}
