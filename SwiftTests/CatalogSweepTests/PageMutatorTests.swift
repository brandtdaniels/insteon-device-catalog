import CatalogBuild
import CatalogJSON
@testable import CatalogSweep
import Foundation
import Testing

/// The changes the page sweep makes to what a card shows.
struct PageMutatorTests {
  static let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

  static let files: [String: JSONValue] = {
    let root = RepositoryRoot(url: repository)
    let files = (try? root.deviceFiles() + root.commandSetFiles()) ?? []
    return Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0.value) })
  }()

  static func workspace() throws -> [String: JSONValue] {
    files
  }

  static func apply(_ kind: PageMutationKind, seed: UInt64) throws -> (before: [String: JSONValue], after: [String: JSONValue], change: AppliedPageMutation?) {
    let before = try workspace()
    var after = before
    var random = SplitMix64(seed: seed)
    let change = PageMutator().mutate(&after, kind: kind, using: &random)

    return (before, after, change)
  }

  static func changedPaths(_ before: [String: JSONValue], _ after: [String: JSONValue]) -> Set<String> {
    Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }
  }

  @Test(arguments: PageMutationKind.allCases)
  func eachKindChangesOnlyTheFilesItNames(kind: PageMutationKind) throws {
    var applied = 0

    for seed in 1...8 as ClosedRange<UInt64> {
      let result = try Self.apply(kind, seed: seed)
      guard let change = result.change else { continue }
      applied += 1

      #expect(Self.changedPaths(result.before, result.after) == Set(change.files), "\(change)")
    }

    #expect(applied > 0)
  }

  @Test(arguments: PageMutationKind.allCases)
  func theSameSeedMakesTheSameChange(kind: PageMutationKind) throws {
    let first = try Self.apply(kind, seed: 5)
    let second = try Self.apply(kind, seed: 5)

    #expect(first.after == second.after)
    #expect(first.change == second.change)
  }

  @Test func renamingAProfileAddsEveryCharacterThePageEscapesAndNonASCIIOnes() throws {
    let result = try Self.apply(.renameProfile, seed: 3)
    let path = try #require(result.change?.files.first)
    let before = try #require(result.before[path]?.value(at: ["name"]))
    let name = try #require({ () -> String? in if case .string(let text)? = result.after[path]?.value(at: ["name"]) { text } else { nil } }())

    guard case .string(let original) = before else { return }

    #expect(name.hasPrefix(original))
    for character in ["<", ">", "&", "\"", "'", "\u{E9}", "\u{3C9}", "e\u{301}", "\u{65E5}", "\u{1F600}", "\u{3A3}", "\u{130}"] {
      #expect(name.contains(character), "\(character)")
    }
  }

  @Test func aLongDescriptionIsSeveralThousandCharacters() throws {
    let result = try Self.apply(.longDescription, seed: 2)
    let path = try #require(result.change?.files.first)

    guard case .string(let text)? = result.after[path]?.value(at: ["description"]) else {
      Issue.record("no description")
      return
    }

    #expect(text.count > 1_000)
    #expect(text.contains("&"))
    #expect(!text.hasSuffix(" "))
  }

  @Test func droppingCommandSetsRemovesTheMemberFromAProfileThatHasOne() throws {
    let result = try Self.apply(.dropCommandSets, seed: 4)
    let path = try #require(result.change?.files.first)

    #expect(result.before[path]?.value(at: ["commandSets"]) != nil)
    #expect(result.after[path]?.value(at: ["commandSets"]) == nil)
  }

  @Test func anEmptiedCommandSetKeepsOnlyWhatDescribesIt() throws {
    let result = try Self.apply(.emptyCommandSet, seed: 6)
    let path = try #require(result.change?.files.first)
    let keys = Set(result.after[path]?.members.map(\.key) ?? [])

    #expect(path.hasPrefix("commandSets/"))
    #expect(keys.isSubset(of: ["id", "name", "description", "sources", "notes"]))
    #expect(keys.contains("description"))
  }

  @Test func renamingAModelMovesTheFileAndKeepsTheModelEqualToTheFileName() throws {
    let result = try Self.apply(.renameModel, seed: 8)
    let change = try #require(result.change)
    let (removed, added) = (change.files[0], change.files[1])

    #expect(result.after[removed] == nil)
    #expect(result.before[added] == nil)
    #expect(result.after[added]?.value(at: ["model"]) == .string(String(added.dropFirst("devices/".count).dropLast(".json".count))))
  }

  @Test func markingAnIdentityAddsAStatusThePageShows() throws {
    let result = try Self.apply(.markIdentity, seed: 9)
    let path = try #require(result.change?.files.first)
    let marked = (result.after[path]?.value(at: ["identities"]).map { value -> [JSONValue] in
      if case .array(let elements) = value { elements } else { [] }
    } ?? []).compactMap { $0.value(at: ["verification", "status"]) }

    #expect(marked.contains(.string("inferred")) || marked.contains(.string("conflicting")))
  }
}
