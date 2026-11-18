import CatalogBuild
import CatalogJSON
import CatalogSite
@testable import CatalogSweep
import Foundation
import Testing

/// A page sweep over the catalog's own files, with stand-ins for the Python build so no test
/// depends on Python.
struct PageSweepTests {
  static let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

  /// A build that renders the copy with the Swift renderer, so the two pages are the same.
  struct SwiftOracle: PageBuilding {
    let patch = 0
    let tamper: @Sendable (String) -> String

    func build(in directory: URL) throws -> PageOracleOutcome {
      .page(tamper(try RepositoryRoot(url: directory).indexPage(patch: patch)))
    }
  }

  /// A build that gives the same outcome for every copy.
  struct FixedOracle: PageBuilding {
    let patch = 0
    let outcome: PageOracleOutcome

    func build(in directory: URL) throws -> PageOracleOutcome { outcome }
  }

  static func results(
    oracle: any PageBuilding, rounds: Int, seed: UInt64 = 1, content: Int = 2, data: Int = 0, checksRules: Bool = false
  ) throws -> [PageRoundResult] {
    var results: [PageRoundResult] = []
    try PageSweep(
      repository: repository, oracle: oracle, seed: seed, contentMutationsPerRound: content, dataMutationsPerRound: data,
      checksRules: checksRules
    )
      .run(rounds: rounds) { results.append($0) }
    return results
  }

  @Test func roundZeroIsTheRepositoryItselfAndEachLaterRoundHasItsChanges() throws {
    let results = try Self.results(oracle: SwiftOracle(tamper: { $0 }), rounds: 2)

    #expect(results.map(\.round) == [0, 1, 2])
    #expect(results[0].mutations.isEmpty)
    #expect(results[1].mutations.count == 2)
    #expect(results[2].mutations.count == 2)
  }

  @Test func twoPagesThatAreTheSameBytesAreIdentical() throws {
    let results = try Self.results(oracle: SwiftOracle(tamper: { $0 }), rounds: 1, checksRules: true)

    for result in results {
      guard case .identical(let bytes) = result.verdict else {
        Issue.record("round \(result.round): \(result.verdict)")
        continue
      }
      #expect(bytes > 100_000)
      #expect(result.round > 0 || result.agrees)
    }
  }

  @Test func aDifferingPageIsReportedWithTheOffsetAndTheFragmentThatDiffers() throws {
    let oracle = SwiftOracle(tamper: { $0.replacingOccurrences(of: #"<span class="model mono">2242</span>"#, with: #"<span class="model mono">2242X</span>"#) })
    let result = try #require(try Self.results(oracle: oracle, rounds: 0).first)

    guard case .different(let difference, let fragments) = result.verdict else {
      Issue.record("\(result.verdict)")
      return
    }

    #expect(difference.pythonExcerpt.contains("2242[HERE]X"))
    #expect(fragments.filter { !$0.agrees }.map(\.name) == ["cards"])
    #expect(!result.agrees)
  }

  @Test func dataTheBuildRefusesIsNotComparedAndAgreesOnlyWhenTheSwiftRulesRefuseIt() throws {
    let result = try #require(try Self.results(oracle: FixedOracle(outcome: .rejected(["x.json: bad"])), rounds: 0, checksRules: true).first)

    #expect(result.verdict == .rejected(["x.json: bad"]))
    #expect(result.swiftAccepted)
    #expect(!result.buildsAgree)
    #expect(!result.agrees)
  }

  @Test func aBuildThatWritesNoPageOrCrashesIsNotAnAgreement() throws {
    #expect(try #require(try Self.results(oracle: FixedOracle(outcome: .noPage), rounds: 0).first).verdict == .noPage)
    #expect(try #require(try Self.results(oracle: FixedOracle(outcome: .crashed), rounds: 0).first).verdict == .crashed)
    #expect(try #require(try Self.results(oracle: FixedOracle(outcome: .noPage), rounds: 0).first).agrees == false)
  }

  @Test func theSameSeedMakesTheSameChanges() throws {
    func changes(seed: UInt64) throws -> [[String]] {
      try Self.results(oracle: FixedOracle(outcome: .noPage), rounds: 3, seed: seed).map(\.mutations)
    }

    let first = try changes(seed: 31)

    #expect(try changes(seed: 31) == first)
    #expect(try changes(seed: 32) != first)
  }

  @Test func dataChangesFromTheRuleSweepsMutatorAreMadeAsWell() throws {
    let results = try Self.results(oracle: FixedOracle(outcome: .noPage), rounds: 2, seed: 4, content: 1, data: 2)

    for result in results.dropFirst() {
      #expect(result.mutations.count >= 1)
      #expect(result.mutations.contains { $0.contains(" in ") && $0.contains(":") || $0.contains("$") })
    }
  }

  @Test func theSweepLeavesTheRepositoryAsItWas() throws {
    let before = try RepositoryRoot(url: Self.repository).indexPage(patch: 0)

    _ = try Self.results(oracle: FixedOracle(outcome: .noPage), rounds: 2)

    #expect(try RepositoryRoot(url: Self.repository).indexPage(patch: 0) == before)
  }

  @Test func aStubbedInterpreterThatWritesNothingLeavesNoPage() throws {
    let result = try #require(try PageSweepRound.run(interpreter: "true"))

    #expect(result.verdict == .noPage)
  }
}

/// One round with the real oracle type and a stand-in interpreter.
enum PageSweepRound {
  static func run(interpreter: String) throws -> PageRoundResult? {
    var first: PageRoundResult?
    try PageSweep(repository: PageSweepTests.repository, interpreter: interpreter, contentMutationsPerRound: 1, checksRules: false).run(rounds: 0) { first = first ?? $0 }
    return first
  }
}
