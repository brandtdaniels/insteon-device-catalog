import CatalogIngest
import CatalogJSON
@testable import CatalogSweep
import Foundation
import Testing

/// The ingestion sweep, with the Swift tool standing in for the Python one so no test depends on Python.
struct IngestSweepTests {
  static let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  static let golden = repository.appendingPathComponent("SwiftTests/CatalogIngestTests/Golden")

  /// A tool that runs the Swift tool and then changes what it printed.
  struct ChangedOutput: IngestRunning {
    let change: @Sendable (String) -> String

    func run(_ arguments: [String], in root: URL) throws -> IngestRun {
      let run = try SwiftIngestRunner().run(arguments, in: root)

      return IngestRun(status: run.status, standardOutput: change(run.standardOutput))
    }
  }

  @Test func theGoldenFormatKeepsEveryPartByteForByte() {
    var golden = IngestGolden()
    golden.add("status", "0")
    golden.add("stdout", "=== not a header 5\nline\n\n")
    golden.add("empty", "")
    golden.add("file devices/2450.json", "caf\u{00E9}\n")

    #expect(IngestGolden.parse(golden.serialized()) == golden)
    #expect(IngestGolden.parse(golden.serialized())?["stdout"] == "=== not a header 5\nline\n\n")
  }

  @Test func aGoldenThatIsCutShortIsNotParsed() {
    var golden = IngestGolden()
    golden.add("stdout", "some text")
    let bytes = golden.serialized()

    #expect(IngestGolden.parse(Array(bytes.dropLast())) == nil)
    #expect(IngestGolden.parse(Array("not a golden\n".utf8)) == nil)
    #expect(IngestGolden.parse([]) == IngestGolden())
  }

  @Test func theSameSeedMakesTheSameFiles() throws {
    let catalog = try ProfileCatalog.load(from: .init(url: Self.repository))
    let example = try ObservationBuilder(fixture: Self.golden.appendingPathComponent("observations/example-invented-product.json"))
    let mutator = ObservationMutator(catalog: catalog, example: example)
    var first = SplitMix64(seed: 5), second = SplitMix64(seed: 5), other = SplitMix64(seed: 6)

    let made = mutator.generate(20, using: &first)

    #expect(made.count == 20)
    #expect(mutator.generate(20, using: &second).map(\.input) == made.map(\.input))
    #expect(mutator.generate(20, using: &other).map(\.input) != made.map(\.input))
  }

  @Test func theFilesMadeIncludeAcceptedAndRefusedOnes() throws {
    let catalog = try ProfileCatalog.load(from: .init(url: Self.repository))
    let example = try ObservationBuilder(fixture: Self.golden.appendingPathComponent("observations/example-invented-product.json"))
    var random = SplitMix64(seed: 1)
    let made = ObservationMutator(catalog: catalog, example: example).generate(200, using: &random)
    var accepted = 0, refused = 0

    for file in made {
      guard case .bytes(let bytes) = file.input, let value = try? JSONParser.parse(bytes) else { refused += 1; continue }

      if ObservationCheck.problems(in: value, models: Set(catalog.profiles.keys)).isEmpty { accepted += 1 } else { refused += 1 }
    }

    #expect(accepted > 20)
    #expect(refused > 20)
  }

  @Test func twoRunsOfTheSameToolDoNotDiffer() throws {
    let sweep = IngestSweep(
      repository: Self.repository, golden: Self.golden, oracle: SwiftIngestRunner(), seed: 3, filesPerRound: 6, applyEvery: 1, applyCases: false
    )
    var rounds: [IngestRoundResult] = []

    try sweep.run(rounds: 2) { rounds.append($0) }

    #expect(rounds.map(\.round) == [0, 1, 2])
    #expect(rounds.allSatisfy { $0.differences.isEmpty })
    #expect(rounds.map(\.compared).allSatisfy { $0 >= 2 })
  }

  @Test func aToolThatPrintsSomethingElseIsReported() throws {
    let sweep = IngestSweep(
      repository: Self.repository, golden: Self.golden, oracle: ChangedOutput { $0 + "extra\n" }, seed: 3, filesPerRound: 3, applyEvery: 0, applyCases: false
    )
    var first: IngestRoundResult?

    try sweep.run(rounds: 0) { first = $0 }

    let differences = try #require(first?.differences)

    #expect(!differences.isEmpty)
    #expect(differences[0].contains("stdout differs"))
  }

  @Test func aDifferenceOnlyInAJSONErrorPositionIsCountedApart() throws {
    let comparer = IngestSweep.Comparer(
      root: Self.repository, oracle: ChangedOutput { $0.replacingOccurrences(of: "column 2", with: "column 9") }, subject: SwiftIngestRunner()
    )

    let totals = try comparer.runs([("check", [.bytes(Array("{".utf8))])])

    #expect(totals.differences.isEmpty)
    #expect(totals.positionOnly == 1)
    #expect(totals.compared == 1)
  }

  @Test func theApplyCasesRunOnBothTools() throws {
    let sweep = IngestSweep(
      repository: Self.repository, golden: Self.golden, oracle: SwiftIngestRunner(), seed: 3, filesPerRound: 1, applyEvery: 0, applyCases: true
    )
    var first: IngestRoundResult?

    try sweep.run(rounds: 0) { first = $0 }

    #expect(first?.differences == [])
    #expect((first?.compared ?? 0) > ApplyCaseBook.cases.count)
  }
}
