import CatalogIngest
import CatalogJSON
import Foundation
import Testing

struct DraftFilesTests {
  let scratch: Scratch

  init() throws {
    scratch = try Scratch()
  }

  func report(_ files: [URL], catalog: ProfileCatalog = inventedCatalog()) -> DraftedFiles {
    ReportDrafting.draft(files, in: catalog)
  }

  @Test func theSameObservationTwiceChangesThingsOnce() throws {
    let first = try scratch.write("a.json", json: observation())
    let second = try scratch.write("b.json", json: observation())

    #expect(report([first, second]).report.observations.map(\.outcome) == [.drafted, .noChange])
  }

  @Test func twoFirmwareVersionsOfOneProductAreAddedInOrder() throws {
    let first = try scratch.write("a.json", json: observation(["firmware": .string("0x41")]))
    let second = try scratch.write("b.json", json: observation(["firmware": .string("0x42")]))
    let catalog = inventedCatalog(identity: #"{"category": "0x7E", "subcategory": "0x7F", "productKey": "0x00001A", "verification": \#(observed(["0x40"]))}"#)
    let drafted = report([first, second], catalog: catalog).report.observations

    #expect(drafted[0].changes[0].after["firmware"] == json(#"["0x40", "0x41"]"#))
    #expect(drafted[1].changes[0].after["firmware"] == json(#"["0x40", "0x41", "0x42"]"#))
  }

  @Test func aRejectedFileIsReportedWithItsErrorsAndTheOthersStillDraft() throws {
    let bad = observation().setting("note", to: .string("Next to 2F.9A.C1."))
    let paths = [try scratch.write("bad.json", json: bad), try scratch.write("ok.json", json: observation())]
    let result = report(paths)

    #expect(result.report.observations.map(\.outcome) == [.rejected, .drafted])
    #expect(result.report.outcome == .rejected)
    #expect(result.report.observations[0].errors.count == 1)
    #expect(!result.report.json.text.contains("2F.9A.C1"))
    #expect(result.notes == [nil, "Fresh battery, device on the bench."])
  }

  @Test func observationsAreNamedByPositionAndContentNeverByFileName() throws {
    let path = try scratch.write("2F.9A.C1.json", json: observation())
    let result = report([path])
    let label = result.report.observations[0].label

    #expect(label.wholeMatch(of: #/observation 1 \([0-9a-f]{8}\)/#) != nil)
    #expect(!result.report.json.text.contains("2F.9A.C1"))
  }

  @Test func theReportNamesItsFormatAndLane() throws {
    let result = report([try scratch.write("a.json", json: observation())]).report

    #expect(result.json["format"] == .string("insteon-catalog-ingest-report/1"))
    #expect(result.json["lane"] == .string("observation"))
  }

  @Test func draftingDoesNotChangeTheCatalogItIsGiven() throws {
    let catalog = inventedCatalog()
    let snapshot = catalog
    _ = report([try scratch.write("a.json", json: observation())], catalog: catalog)

    #expect(catalog == snapshot)
  }

  @Test func theReportOutcomeIsTheMostUrgentOfTheObservations() throws {
    let drafted = try scratch.write("a.json", json: observation())
    let unknown = try scratch.write("b.json", json: observation(["category": .string("0x70")]))
    let quiet = try scratch.write("c.json", json: Fixtures.bench("silent-sensor.json"))

    #expect(report([quiet]).report.outcome == .noChange)
    #expect(report([quiet, unknown]).report.outcome == .needsHuman)
    #expect(report([quiet, unknown, drafted]).report.outcome == .drafted)
  }

  @Test func aMissingFileIsRejectedAndNamedUnreadable() {
    let missing = scratch.url.appendingPathComponent("absent.json")
    let item = report([missing]).report.observations[0]

    #expect(item.outcome == .rejected)
    #expect(item.label == "observation 1 (unreadable)")
    #expect(item.errors == ["cannot read the file"])
  }

  @Test func theReportKeepsTheOrderOfEachItemsMembers() throws {
    let item = report([try scratch.write("a.json", json: observation())]).report.observations[0].json

    #expect(item.keys == ["input", "outcome", "matched", "changes", "unchanged", "disagreements", "skipped", "reportOnly", "warnings", "errors"])
    #expect(item["changes"]?[0]?.keys == ["file", "model", "entry", "selector", "field", "before", "after", "effect", "target"])
    #expect(item["changes"]?[0]?["before"] == .null)
  }
}

struct ReportTextTests {
  let scratch: Scratch

  init() throws {
    scratch = try Scratch()
  }

  func report(for data: JSONValue) throws -> DraftedFiles {
    ReportDrafting.draft([try scratch.write("a.json", json: data)], in: inventedCatalog())
  }

  @Test func theMarkdownListsEachSectionAndShowsTheNoteOnlyToTheMaintainer() throws {
    let data = observation(["engine": .string("i2")]).setting("note", to: .string("Bench note for the maintainer."))
    let result = try report(for: data)
    let text = result.markdown

    #expect(text.contains("Bench note for the maintainer."))
    #expect(text.contains("Needs a maintainer decision"))
    #expect(text.contains("engine-differs"))
    #expect(!result.report.json.text.contains("Bench note"))
  }

  @Test func theMarkdownForACleanObservationSaysWhatWouldChange() throws {
    let text = try report(for: observation()).markdown

    #expect(text.contains("Proposed changes"))
    #expect(text.contains("devices/9999.json"))
  }

  @Test func theMarkdownHasTheLayoutOfTheReport() throws {
    let text = try report(for: observation().setting("note", to: .string("Bench."))).markdown
    let digest = ObservationFile.fingerprint(scratch.url.appendingPathComponent("a.json"))

    #expect(text == """
      # Observation report

      Outcome: drafted

      ## observation 1 (\(digest)): drafted

      Matched 9999 by category 0x7E and subcategory 0x7F.

      Proposed changes:

      - devices/9999.json: identity 0x7E/0x7F, verification: marked observed on firmware 0x41
      - devices/9999.json: engine i2CS 0x7E/0x7F, verification: marked observed on firmware 0x41
      - devices/9999.json: product key of identity 0x7E/0x7F, productKeyVerification: marked observed on firmware 0x41

      Warnings:

      - The file names a different product than the profile its identity matched.

      Contributor's note (for the maintainer; copied nowhere):

      > Bench.

      """)
  }

  @Test func theMarkdownEndsWithOneNewlineWhateverTheLastLineHolds() throws {
    let text = try report(for: observation().setting("note", to: .string("Trailing spaces  \t"))).markdown

    #expect(text.hasSuffix("> Trailing spaces\n"))
    #expect(!text.hasSuffix("\n\n"))
  }

  @Test func anEmptyNoteIsNotShown() throws {
    let text = try report(for: observation().setting("note", to: .string(""))).markdown

    #expect(!text.contains("Contributor's note"))
  }
}
