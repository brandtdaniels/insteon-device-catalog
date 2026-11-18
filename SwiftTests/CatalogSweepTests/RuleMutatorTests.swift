import CatalogBuild
import CatalogJSON
import CatalogRules
import CatalogSweep
import Foundation
import Testing

/// The changes aimed at the registry, citation, term and dash rules are chosen by a seed, change
/// the files they name, and make the rule they aim at speak.
struct RuleMutatorTests {
  /// The catalog's profiles, command sets and the two documents files, by path.
  static let workspace: [String: JSONValue] = {
    do {
      let root = RepositoryRoot(url: SweepTests.repository)
      var files: [String: JSONValue] = [:]

      for file in try root.deviceFiles() + root.commandSetFiles() {
        files[file.path] = file.value
      }

      for path in [RuleMutator.registryPath, RuleMutator.reviewedPath] {
        files[path] = try JSONParser.parse([UInt8](Data(contentsOf: SweepTests.repository.appendingPathComponent(path))))
      }

      return files
    } catch {
      fatalError("\(error)")
    }
  }()

  static let titles = RegisteredTitles(
    (workspace[RuleMutator.registryPath]?.elements(of: "documents") ?? []).compactMap { $0.string(of: "title") }
  )

  /// Makes `kind` changes with seeds from 1 until one applies, and returns the changed workspace.
  static func change(_ kind: RuleMutationKind, seed: UInt64 = 1) throws -> (files: [String: JSONValue], applied: AppliedRuleMutation) {
    for attempt in seed..<(seed + 50) {
      var files = workspace
      var random = SplitMix64(seed: attempt)

      if let applied = RuleMutator().mutate(&files, kind: kind, using: &random) {
        return (files, applied)
      }
    }

    throw MutationNotMade(kind: kind)
  }

  struct MutationNotMade: Error {
    let kind: RuleMutationKind
  }

  @Test func theSameSeedMakesTheSameChanges() {
    func run(seed: UInt64) -> [String] {
      var random = SplitMix64(seed: seed)
      var files = Self.workspace

      return (0..<12).compactMap { _ in RuleMutator().mutate(&files, using: &random)?.description }
    }

    #expect(run(seed: 7) == run(seed: 7))
    #expect(run(seed: 7) != run(seed: 8))
  }

  @Test func everyKindOfChangeIsMadeSomewhere() {
    var random = SplitMix64(seed: 5)
    var seen = Set<RuleMutationKind>()

    for _ in 0..<300 {
      var files = Self.workspace
      if let applied = RuleMutator().mutate(&files, using: &random) {
        seen.insert(applied.kind)
      }
    }

    #expect(seen == Set(RuleMutationKind.allCases))
  }

  @Test(arguments: RuleMutationKind.allCases)
  func aChangeAltersEachFileItNames(kind: RuleMutationKind) throws {
    let (files, applied) = try Self.change(kind)

    #expect(applied.kind == kind)
    #expect(!applied.files.isEmpty)
    #expect(applied.files.allSatisfy { Self.workspace[$0] != files[$0] })
    #expect(files.filter { Self.workspace[$0.key] != $0.value }.keys.sorted() == applied.files.sorted())
  }

  @Test func anUnregisteredSourceIsNotAmongTheRegisteredTitles() throws {
    let (files, applied) = try Self.change(.unregisteredSource)
    let file = try #require(applied.files.first)
    let value = try #require(files[file])

    #expect(SourceRules.problems(label: "x.json", in: Self.workspace[file] ?? .null, titles: Self.titles) == [])
    #expect(SourceRules.problems(label: "x.json", in: value, titles: Self.titles).count == 1)
  }

  @Test func aDuplicateRegistryTitleIsReported() throws {
    let (files, _) = try Self.change(.duplicateRegistryTitle)
    let found = RegistryRules.problems(in: try #require(files[RuleMutator.registryPath]))

    #expect(found.count == 1)
    #expect(found.first?.hasSuffix("appears more than once") == true)
  }

  @Test(arguments: [1, 2, 3, 4, 5, 6] as [UInt64])
  func aDashInADataStringIsReported(seed: UInt64) throws {
    let (files, applied) = try Self.change(.dashInDataString, seed: seed)
    let file = try #require(applied.files.first)
    let text = try JSONWriter.write(try #require(files[file]))
    let before = try JSONWriter.write(try #require(Self.workspace[file]))

    #expect(DashRules.problems(file: file, text: text).count == 1)
    #expect(DashRules.problems(file: file, text: before).isEmpty)
  }

  @Test func aNearDuplicateTitleAddsACandidatePair() throws {
    let (files, _) = try Self.change(.nearDuplicateTitle)
    let registry = try #require(files[RuleMutator.registryPath])
    let original = try #require(Self.workspace[RuleMutator.registryPath])

    #expect(RegistryRules.nearDuplicates(in: registry).count > RegistryRules.nearDuplicates(in: original).count)
  }

  @Test(arguments: [1, 2, 3, 4, 5, 6, 7, 8] as [UInt64])
  func aRuledOutTermReachesAStringTheTermRuleReads(seed: UInt64) throws {
    let (files, applied) = try Self.change(.ruledOutTerm, seed: seed)
    let file = try #require(applied.files.first)
    let found = file == RuleMutator.registryPath
      ? RegistryRules.problems(in: try #require(files[file]))
      : TermRules.problems(label: "x.json", in: try #require(files[file]))
    let before = file == RuleMutator.registryPath
      ? RegistryRules.problems(in: try #require(Self.workspace[file]))
      : TermRules.problems(label: "x.json", in: try #require(Self.workspace[file]))

    #expect(before.isEmpty)
    // A form in backticks is left out of the check, so those changes report nothing.
    #expect(applied.detail.hasSuffix("in backticks") || !found.isEmpty)
  }

  @Test func aReviewedPairChangeLeavesTheRegistryAlone() throws {
    let (files, applied) = try Self.change(.reviewedPair)

    #expect(applied.files == [RuleMutator.reviewedPath])
    #expect(files[RuleMutator.registryPath] == Self.workspace[RuleMutator.registryPath])
  }
}

extension JSONValue {
  fileprivate func elements(of key: String) -> [JSONValue] {
    guard case .object(let members) = self, case .array(let elements)? = members.first(where: { $0.key == key })?.value else { return [] }
    return elements
  }

  fileprivate func string(of key: String) -> String? {
    guard case .object(let members) = self, case .string(let text)? = members.first(where: { $0.key == key })?.value else { return nil }
    return text
  }
}
