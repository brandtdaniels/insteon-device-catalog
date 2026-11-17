import CatalogBuild
import CatalogJSON
import Foundation

/// What went wrong when a round could not be run at all.
public enum SweepError: Error, CustomStringConvertible {
  case copyFailed(String)
  case oracleMissing(String)

  public var description: String {
    switch self {
    case .copyFailed(let reason): "can't copy the repository: \(reason)"
    case .oracleMissing(let path): "the Python build isn't at \(path)"
    }
  }
}

/// One round: the mutations made, and where the Swift rules and the Python build disagree.
public struct RoundResult: Sendable {
  public let round: Int
  public let mutations: [AppliedMutation]
  public let pythonCrashed: Bool
  public let swiftOutcome: Comparison.Outcome
  public let pythonOutcome: Comparison.Outcome

  /// Whether both builds reported the same rule messages, in order, and matching schema errors.
  public var agrees: Bool {
    Comparison.agree(swift: swiftOutcome, python: pythonOutcome)
  }
}

/// Runs mutated copies of the catalog through the Swift rules and the Python build and compares them.
///
/// Transitional: `scripts/build.py` is the oracle while the Python build exists. Nothing here
/// writes Python; the sweep runs `scripts/build.py` as it is.
public struct Sweep: Sendable {
  public let repository: URL
  public let interpreter: String
  public let seed: UInt64
  public let mutationsPerRound: Int

  public init(repository: URL, interpreter: String = "python3", seed: UInt64 = 1, mutationsPerRound: Int = 30) {
    self.repository = repository
    self.interpreter = interpreter
    self.seed = seed
    self.mutationsPerRound = mutationsPerRound
  }

  /// The data directories and files `scripts/build.py` reads.
  static let copied = ["scripts", "schema", "devices", "commandSets", "documents", "templates", "VERSION"]

  /// Runs rounds `1...rounds`. Each round mutates `mutationsPerRound` data files, one change each.
  public func run(rounds: Int, report: (RoundResult) -> Void) throws {
    let root = RepositoryRoot(url: repository)
    let files = try root.deviceFiles().map { (path: $0.path, value: $0.value) }
      + root.commandSetFiles().map { (path: $0.path, value: $0.value) }
    let mutator = Mutator(pool: ValuePool(files: files.map(\.value)))

    for round in 1...rounds {
      report(try runRound(round, files: files, mutator: mutator))
    }
  }

  private func runRound(_ round: Int, files: [(path: String, value: JSONValue)], mutator: Mutator) throws -> RoundResult {
    var random = SplitMix64(seed: seed &+ UInt64(round) &* 0x1_0000_0001)
    let copy = FileManager.default.temporaryDirectory.appendingPathComponent("catalog-sweep-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: copy) }

    try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
    for name in Self.copied {
      do {
        try FileManager.default.copyItem(at: repository.appendingPathComponent(name), to: copy.appendingPathComponent(name))
      } catch {
        throw SweepError.copyFailed("\(name): \(error.localizedDescription)")
      }
    }

    let commandSetIndexes = files.indices.filter { files[$0].path.hasPrefix("commandSets/") }
    var applied: [AppliedMutation] = []
    var chosen = Set<Int>()
    var attempts = 0

    while chosen.count < min(mutationsPerRound, files.count), attempts < mutationsPerRound * 20 {
      attempts += 1
      // Half the changes go to command sets, which most rules read.
      let pickCommandSet = Bool.random(using: &random) && !commandSetIndexes.isEmpty
      let index = pickCommandSet ? commandSetIndexes.randomElement(using: &random)! : Int.random(in: 0..<files.count, using: &random)
      guard !chosen.contains(index),
            let (value, mutation) = mutator.mutate(files[index].value, name: files[index].path, using: &random)
      else { continue }

      chosen.insert(index)
      applied.append(mutation)
      let text = try JSONWriter.write(value) + "\n"
      try Data(text.utf8).write(to: copy.appendingPathComponent(files[index].path))
    }

    let swiftLines = try RepositoryRoot(url: copy).problems()
    let python = try runPython(in: copy)

    return RoundResult(
      round: round, mutations: applied, pythonCrashed: python.crashed,
      swiftOutcome: Comparison.outcome(of: swiftLines), pythonOutcome: Comparison.outcome(of: python.lines)
    )
  }

  private func runPython(in directory: URL) throws -> (lines: [String], crashed: Bool) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [interpreter, "-I", "scripts/build.py"]
    process.currentDirectoryURL = directory

    let errors = Pipe()
    process.standardError = errors
    process.standardOutput = FileHandle.nullDevice

    try process.run()
    let output = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    let text = String(decoding: output, as: UTF8.self)
    let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    let crashed = text.contains("Traceback (most recent call last)")

    return (crashed ? [] : lines, crashed)
  }
}
