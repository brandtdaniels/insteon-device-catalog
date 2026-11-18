import CatalogBuild
import CatalogJSON
import Foundation

/// The mutated copies of the repository's data that a sweep compares, one per round.
///
/// Round 0 is the repository's own data. Round `n` changes the data files the same way every time for
/// the same seed: first with the data sweep's mutator, then with changes to what a card shows.
struct MutationPlan: Sendable {
  /// The data files of a copy before and after a round's changes, by path.
  typealias Workspace = (before: [String: JSONValue], after: [String: JSONValue])

  let repository: URL
  let seed: UInt64
  /// How many changes to what a card shows each round makes.
  let contentMutationsPerRound: Int
  /// How many changes the data sweep's mutator makes each round, on top of the content changes.
  let dataMutationsPerRound: Int

  /// Calls `body` for round 0, which has no changes and no workspace, then for rounds `1...rounds`,
  /// with the changes the round made and the data files before and after them.
  func run(rounds: Int, _ body: (_ round: Int, _ mutations: [String], _ workspace: Workspace?) throws -> Void) throws {
    let root = RepositoryRoot(url: repository)
    let files = try root.deviceFiles().map { (path: $0.path, value: $0.value) } + root.commandSetFiles().map { (path: $0.path, value: $0.value) }
    let mutator = Mutator(pool: ValuePool(files: files.map(\.value)))

    try body(0, [], nil)

    for round in 1...max(rounds, 1) where rounds > 0 {
      var random = SplitMix64(seed: seed &+ UInt64(round) &* 0x1_0000_0001)
      var workspace = Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0.value) })
      var applied: [String] = []
      let before = workspace

      for _ in 0..<dataMutationsPerRound {
        let paths = workspace.keys.sorted()
        guard let path = paths.randomElement(using: &random), let value = workspace[path],
              let (changed, mutation) = mutator.mutate(value, name: path, using: &random)
        else { continue }
        workspace[path] = changed
        applied.append(mutation.description)
      }

      let content = PageMutator()
      var attempts = 0

      while applied.count < dataMutationsPerRound + contentMutationsPerRound, attempts < contentMutationsPerRound * 10 {
        attempts += 1
        let kind = PageMutationKind.allCases.randomElement(using: &random)!
        if let change = content.mutate(&workspace, kind: kind, using: &random) { applied.append(change.description) }
      }

      try body(round, applied, (before, workspace))
    }
  }

  /// A copy of what the Python build reads, in a temporary folder, with the workspace's changes written into it.
  static func temporaryCopy(of repository: URL, applying workspace: Workspace?) throws -> URL {
    let copy = try PageSweep.temporaryCopy(of: repository)

    guard let (before, after) = workspace else { return copy }

    for path in before.keys where after[path] == nil {
      try FileManager.default.removeItem(at: copy.appendingPathComponent(path))
    }

    for (path, value) in after where before[path] != value {
      try Data((try JSONWriter.write(value) + "\n").utf8).write(to: copy.appendingPathComponent(path))
    }

    return copy
  }
}
