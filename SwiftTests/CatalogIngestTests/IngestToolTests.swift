import CatalogIngest
import CatalogJSON
import Foundation
import Testing

struct CheckCommandTests {
  let scratch: Scratch
  let tool = IngestTool(root: Fixtures.repository)

  init() throws {
    scratch = try Scratch()
  }

  @Test func validFilesExitZeroAndAreNamedByContentNotByFileName() throws {
    let path = try scratch.write("2F.9A.C1.json", try String(contentsOf: Fixtures.observations.appendingPathComponent("io-module-2450.json"), encoding: .utf8))
    let result = tool.check([path])

    #expect(result.status == 0)
    #expect(result.output.contains("valid"))
    #expect(!result.output.contains("2F.9A.C1"))
  }

  @Test func anInvalidFileExitsOneAndSaysWhatToFix() throws {
    let data = Fixtures.bench("example-invented-product.json").setting("note", to: .string("At 192.168.7.20 here."))
    let result = tool.check([try scratch.write("bad.json", json: data)])

    #expect(result.status == 1)
    #expect(result.output.contains("$.note: contains what looks like an IP address"))
    #expect(!result.output.contains("192.168.7.20"))
  }

  @Test func oneBadFileAmongSeveralFailsTheRunAndTheRestAreStillChecked() throws {
    let bad = try scratch.write("bad.json", #"{"format": "other"}"#)
    let result = tool.check([
      Fixtures.observations.appendingPathComponent("io-module-2450.json"), bad, Fixtures.observations.appendingPathComponent("silent-sensor.json")
    ])

    #expect(result.status == 1)
    #expect(result.output.components(separatedBy: ": valid").count - 1 == 2)
  }

  @Test func aMissingFileIsReportedNotRaised() {
    let result = tool.check([scratch.url.appendingPathComponent("absent.json")])

    #expect(result.status == 1)
    #expect(result.output.contains("cannot read the file"))
  }

  @Test func theCatalogsModelNumbersAreReadFromItsDevicesFolder() {
    let dimmer = Fixtures.observations.appendingPathComponent("dimmer-plug-2457D2.json")

    #expect(tool.check([dimmer]).status == 0)
    #expect(IngestTool(root: scratch.url).check([dimmer]).status == 1)
  }
}

struct DraftCommandTests {
  let scratch: Scratch
  let tool = IngestTool(root: Fixtures.repository)
  let silent = Fixtures.observations.appendingPathComponent("silent-sensor.json")

  init() throws {
    scratch = try Scratch()
  }

  @Test func aCleanDraftExitsZeroAndWritesTheReportAndTheMarkdown() throws {
    let report = scratch.url.appendingPathComponent("report.json")
    let markdown = scratch.url.appendingPathComponent("report.md")
    let result = tool.draft([silent], report: report, markdown: markdown)

    #expect(result.status == 0)
    #expect(try JSONParser.parse(try scratch.read("report.json"))["format"] == .string("insteon-catalog-ingest-report/1"))
    #expect(try scratch.read("report.md").contains("says nothing about the device"))
    #expect(result.output.hasPrefix("observation 1 ("))
    #expect(result.output.hasSuffix("): no-change\n"))
  }

  @Test func withoutOutputPathsTheMarkdownGoesToStandardOutput() {
    let result = tool.draft([silent], report: nil, markdown: nil)

    #expect(result.status == 0)
    #expect(result.output.contains("Observation report"))
    #expect(result.output.hasSuffix("\n"))
    #expect(!result.output.hasSuffix("\n\n"))
  }

  @Test func aRejectedFileExitsOne() throws {
    #expect(tool.draft([try scratch.write("bad.json", #"{"format": "other"}"#)], report: nil, markdown: nil).status == 1)
  }

  @Test func aDisagreementExitsTwo() throws {
    let path = try scratch.write("unknown.json", json: observation(["category": .string("0x70")]))
    let result = tool.draft([path], report: nil, markdown: nil)

    #expect(result.status == 2)
    #expect(result.output.contains("unknown-device"))
  }

  @Test func theReportNeverHoldsTheInputFileName() throws {
    let path = try scratch.write("2F.9A.C1.json", json: observation(["category": .string("0x70")]))
    let report = scratch.url.appendingPathComponent("report.json")
    _ = tool.draft([path], report: report, markdown: nil)

    #expect(try !scratch.read("report.json").contains("2F.9A.C1"))
  }

  @Test func aReportFileEndsWithOneNewline() throws {
    let report = scratch.url.appendingPathComponent("report.json")
    _ = tool.draft([silent], report: report, markdown: nil)
    let text = try scratch.read("report.json")

    #expect(text.hasSuffix("}\n"))
    #expect(!text.hasSuffix("\n\n"))
  }

  @Test func everyRealBenchFileDraftsAgainstTheRealCatalogWithoutError() {
    let names = ["dimmer-plug-2457D2.json", "io-module-2450.json", "on-off-plug-2635-222.json", "silent-sensor.json"]
    let result = tool.draft(names.map { Fixtures.observations.appendingPathComponent($0) }, report: nil, markdown: nil)

    #expect([0, 2].contains(result.status))
  }

  @Test func aCatalogThatCannotBeReadIsReportedNotRaised() throws {
    try scratch.write("devices/broken.json", "{")
    let result = IngestTool(root: scratch.url).draft([silent], report: nil, markdown: nil)

    #expect(result.status == 1)
    #expect(result.output.contains("devices/broken.json"))
  }
}

struct ApplyCommandTests {
  @Test func aMissingReportIsReportedNotRaised() {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent("absent-report-\(UUID().uuidString).json")
    let result = IngestTool(root: Fixtures.repository).apply(report: missing)

    #expect(result == IngestResult(status: 1, output: "cannot read the report\n"))
  }

  @Test func aReportInsideTheRootMayStayUntracked() throws {
    let scratch = try Scratch()
    let identity = #"{"category": "0x7E", "subcategory": "0x7F", "productKey": "0x00001A"}"#
    let catalog = inventedCatalog(identity: identity)
    let root = try committedRepository(scratch, catalog.profiles)
    let report = try scratch.write("report.json", try draftedReport(catalog).text + "\n")

    let result = IngestTool(root: root, checker: RecordingChecker()).apply(report: report)

    #expect(result.status == 0)
    #expect(result.output == "applied 3 changes to 1 files and the build passed\n  devices/9999.json\n")
  }

  @Test func aSymbolicLinkToTheRootDoesNotHideTheReportInsideIt() throws {
    let scratch = try Scratch()
    let catalog = inventedCatalog()
    let root = try committedRepository(scratch, catalog.profiles)
    let link = FileManager.default.temporaryDirectory.appendingPathComponent("catalog-link-\(UUID().uuidString)")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
    defer { try? FileManager.default.removeItem(at: link) }
    let report = try scratch.write("report.json", try draftedReport(catalog).text + "\n")

    let result = IngestTool(root: link, checker: RecordingChecker()).apply(report: report)

    #expect(result.status == 0, "\(result.output)")
  }
}
