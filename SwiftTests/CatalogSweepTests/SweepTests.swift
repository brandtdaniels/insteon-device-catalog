import CatalogBuild
import CatalogSweep
import Foundation
import Testing

/// A sweep over the catalog's own files, with `true` standing in for the Python interpreter so
/// no test depends on Python.
struct SweepTests {
  static let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

  @Test func aSweepReportsEachRoundAndRepeatsWithTheSameSeed() throws {
    func mutations(seed: UInt64) throws -> [[String]] {
      var rounds: [[String]] = []
      try Sweep(repository: Self.repository, interpreter: "true", seed: seed, mutationsPerRound: 5)
        .run(rounds: 2) { rounds.append($0.mutations.map(\.description)) }
      return rounds
    }

    let first = try mutations(seed: 11)

    #expect(first.count == 2)
    #expect(first.allSatisfy { $0.count == 5 })
    #expect(try mutations(seed: 11) == first)
    #expect(try mutations(seed: 12) != first)
  }

  @Test func eachRoundReportsItsRuleChangesAndRepeatsWithTheSameSeed() throws {
    func changes(seed: UInt64) throws -> [[String]] {
      var rounds: [[String]] = []
      try Sweep(repository: Self.repository, interpreter: "true", seed: seed, mutationsPerRound: 0, ruleMutationsPerRound: 3)
        .run(rounds: 2) { rounds.append($0.ruleMutations.map(\.description)) }
      return rounds
    }

    let first = try changes(seed: 21)

    #expect(first.count == 2)
    #expect(first.allSatisfy { !$0.isEmpty && $0.count <= 3 })
    #expect(try changes(seed: 21) == first)
    #expect(try changes(seed: 22) != first)
  }

  @Test func aSweepLeavesTheRepositoryAsItWas() throws {
    let before = try RepositoryRoot(url: Self.repository).problems()

    try Sweep(repository: Self.repository, interpreter: "true", seed: 1, mutationsPerRound: 10).run(rounds: 1) { _ in }

    #expect(try RepositoryRoot(url: Self.repository).problems() == before)
  }
}
