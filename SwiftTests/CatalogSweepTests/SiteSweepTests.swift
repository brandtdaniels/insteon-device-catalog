import CatalogBuild
import CatalogSite
@testable import CatalogSweep
import Foundation
import Testing

/// A site sweep over the catalog's own files, with stand-ins for the Python build so no test
/// depends on Python.
struct SiteSweepTests {
  static let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  static let built = "2000-01-01T00:00:00Z"

  /// A build that writes the copy's site with the Swift build, so the two sites are the same, and then
  /// lets `tamper` change what it wrote.
  struct SwiftOracle: SiteBuilding {
    let patch = 3
    let built: String? = SiteSweepTests.built
    let tamper: @Sendable (URL) throws -> Void
    let summary: @Sendable (String) -> String

    init(tamper: @escaping @Sendable (URL) throws -> Void = { _ in }, summary: @escaping @Sendable (String) -> String = { $0 }) {
      self.tamper = tamper
      self.summary = summary
    }

    func build(in directory: URL) throws -> SiteOracleOutcome {
      let output = directory.appendingPathComponent("oracle-site")

      switch try RepositoryRoot(url: directory).buildSite(into: output, patch: patch, built: built) {
      case .refused(let problems):
        return .rejected(problems)
      case .written(let profiles, let commandSets):
        try tamper(output)
        return .site(directory: output, summary: summary("\(profiles) profiles and \(commandSets) command sets are valid"))
      }
    }
  }

  /// A build that gives the same outcome for every copy.
  struct FixedOracle: SiteBuilding {
    let patch = 3
    let built: String? = SiteSweepTests.built
    let outcome: SiteOracleOutcome

    func build(in directory: URL) throws -> SiteOracleOutcome { outcome }
  }

  static func results(
    oracle: any SiteBuilding, rounds: Int, seed: UInt64 = 1, content: Int = 2, data: Int = 0
  ) throws -> [SiteRoundResult] {
    var results: [SiteRoundResult] = []
    try SiteSweep(
      repository: repository, oracle: oracle, seed: seed, contentMutationsPerRound: content, dataMutationsPerRound: data
    )
      .run(rounds: rounds) { results.append($0) }
    return results
  }

  @Test func roundZeroIsTheRepositoryItselfAndEachLaterRoundHasItsChanges() throws {
    let results = try Self.results(oracle: SwiftOracle(), rounds: 2)

    #expect(results.map(\.round) == [0, 1, 2])
    #expect(results[0].mutations.isEmpty)
    #expect(results[1].mutations.count == 2)
    #expect(results[2].mutations.count == 2)
  }

  @Test func twoSitesThatAreTheSameBytesAreIdentical() throws {
    let result = try #require(try Self.results(oracle: SwiftOracle(), rounds: 0).first)

    guard case .identical(let files, let bytes) = result.verdict else {
      Issue.record("\(result.verdict)")
      return
    }

    #expect(files == 5)
    #expect(bytes > 100_000)
    #expect(result.agrees)
  }

  @Test func aDifferingFileIsReportedWithItsNameAndOffset() throws {
    let oracle = SwiftOracle(tamper: { site in
      let file = site.appendingPathComponent("v0/manifest.json")
      let text = String(decoding: try Data(contentsOf: file), as: UTF8.self)
      try Data(text.replacingOccurrences(of: "\"devices\"", with: "\"Devices\"").utf8).write(to: file)
    })
    let result = try #require(try Self.results(oracle: oracle, rounds: 0).first)

    guard case .different(.bytes(let file, let difference)) = result.verdict else {
      Issue.record("\(result.verdict)")
      return
    }

    #expect(file == "v0/manifest.json")
    #expect(difference.pythonExcerpt.contains("[HERE]Devices"))
    #expect(!result.agrees)
  }

  @Test func aFileThePythonBuildDidNotWriteIsReported() throws {
    let oracle = SwiftOracle(tamper: { site in
      try FileManager.default.removeItem(at: site.appendingPathComponent("index.html"))
    })
    let result = try #require(try Self.results(oracle: oracle, rounds: 0).first)

    #expect(result.verdict == .different(.onlyInSwift("index.html")))
  }

  @Test func aDifferentSummaryLineIsReportedWhenTheFilesAreTheSame() throws {
    let result = try #require(try Self.results(oracle: SwiftOracle(summary: { _ in "1 profiles and 1 command sets are valid" }), rounds: 0).first)

    guard case .summaryDiffers(let swift, let python) = result.verdict else {
      Issue.record("\(result.verdict)")
      return
    }

    #expect(swift.hasSuffix(" command sets are valid"))
    #expect(python == "1 profiles and 1 command sets are valid")
    #expect(!result.agrees)
  }

  @Test func dataThePythonBuildRefusesIsNotComparedAndAgreesOnlyWhenTheSwiftBuildRefusesItToo() throws {
    let accepted = try #require(try Self.results(oracle: FixedOracle(outcome: .rejected(["x.json: bad"])), rounds: 0).first)

    #expect(accepted.verdict == .swiftAcceptedWhatPythonRefused(["x.json: bad"]))
    #expect(!accepted.agrees)
  }

  @Test func dataBothBuildsRefuseIsAnAgreement() throws {
    let results = try Self.results(oracle: SwiftOracle(), rounds: 4, seed: 5, content: 0, data: 3)
    let refused = results.filter { if case .refusedByBoth = $0.verdict { true } else { false } }

    #expect(!refused.isEmpty)
    #expect(refused.allSatisfy { $0.agrees })
  }

  @Test func dataTheSwiftBuildRefusesAndThePythonBuildAcceptsIsADisagreement() throws {
    let noProblems = FixedOracle(outcome: .site(directory: URL(fileURLWithPath: "/nonexistent/site"), summary: "x"))
    let results = try Self.results(oracle: noProblems, rounds: 4, seed: 5, content: 0, data: 3)
    let refused = results.filter { if case .swiftRefusedWhatPythonAccepted = $0.verdict { true } else { false } }

    #expect(!refused.isEmpty)
    #expect(refused.allSatisfy { !$0.agrees })
  }

  @Test func aBuildThatWritesNoSiteOrCrashesIsNotAnAgreement() throws {
    #expect(try #require(try Self.results(oracle: FixedOracle(outcome: .noSite), rounds: 0).first).verdict == .noSite)
    #expect(try #require(try Self.results(oracle: FixedOracle(outcome: .crashed), rounds: 0).first).verdict == .crashed)
    #expect(try #require(try Self.results(oracle: FixedOracle(outcome: .noSite), rounds: 0).first).agrees == false)
  }

  @Test func theSameSeedMakesTheSameChanges() throws {
    func changes(seed: UInt64) throws -> [[String]] {
      try Self.results(oracle: FixedOracle(outcome: .noSite), rounds: 3, seed: seed).map(\.mutations)
    }

    let first = try changes(seed: 31)

    #expect(try changes(seed: 31) == first)
    #expect(try changes(seed: 32) != first)
  }

  @Test func theSweepLeavesTheRepositoryAsItWas() throws {
    let before = try RepositoryRoot(url: Self.repository).indexPage(patch: 0)

    _ = try Self.results(oracle: SwiftOracle(), rounds: 2)

    #expect(try RepositoryRoot(url: Self.repository).indexPage(patch: 0) == before)
  }

  @Test func aStubbedInterpreterThatWritesNothingLeavesNoSite() throws {
    var first: SiteRoundResult?
    try SiteSweep(repository: Self.repository, interpreter: "true", patch: 3, built: Self.built, contentMutationsPerRound: 1)
      .run(rounds: 0) { first = first ?? $0 }

    #expect(first?.verdict == .noSite)
  }
}
