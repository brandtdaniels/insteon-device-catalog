import CatalogBuild
import CatalogSite
import Foundation

/// How the Swift site compares with the Python build's site for one copy of the data.
public enum SiteVerdict: Equatable, Sendable {
  /// Both builds wrote the same files with the same bytes.
  case identical(files: Int, bytes: Int)
  /// The sites differ; this is the first difference.
  case different(SiteDifference)
  /// The sites are the same but the two builds printed different summary lines.
  case summaryDiffers(swift: String, python: String?)
  /// Both builds refused the data, so there is no site to compare.
  case refusedByBoth(python: [String], swift: [String])
  /// The Swift build refused data the Python build accepted.
  case swiftRefusedWhatPythonAccepted([String])
  /// The Python build refused data the Swift build accepted; these are the Python build's problems.
  case swiftAcceptedWhatPythonRefused([String])
  /// The Python build stopped with a traceback.
  case crashed
  /// The Python build wrote no site.
  case noSite
  /// The Swift build could not run on the copy.
  case swiftFailed(String)
}

/// One round: the changes made and how the two sites compare.
public struct SiteRoundResult: Sendable {
  /// The round number; round 0 is the repository's own data.
  public let round: Int
  public let mutations: [String]
  public let verdict: SiteVerdict

  /// Whether nothing differs: the sites are the same, or both builds refused the data.
  public var agrees: Bool {
    switch verdict {
    case .identical, .refusedByBoth: true
    default: false
    }
  }
}

/// Builds the site with the Swift build and the Python build on the repository's data and on mutated
/// copies of it, and compares the two directories byte for byte.
///
/// Transitional: `scripts/build.py` is the oracle while the Python build exists.
public struct SiteSweep: Sendable {
  public let repository: URL
  public let oracle: any SiteBuilding
  public let seed: UInt64
  /// How many changes to what a card shows each round makes.
  public let contentMutationsPerRound: Int
  /// How many changes the data sweep's mutator makes each round, on top of the content changes.
  public let dataMutationsPerRound: Int

  /// A sweep that compares with the sites `oracle` builds.
  public init(
    repository: URL, oracle: any SiteBuilding, seed: UInt64 = 1, contentMutationsPerRound: Int = 3, dataMutationsPerRound: Int = 0
  ) {
    self.repository = repository
    self.oracle = oracle
    self.seed = seed
    self.contentMutationsPerRound = contentMutationsPerRound
    self.dataMutationsPerRound = dataMutationsPerRound
  }

  /// A sweep that compares with the Python build run by `interpreter`.
  public init(
    repository: URL, interpreter: String = "python3", patch: Int = 0, built: String? = nil, seed: UInt64 = 1,
    contentMutationsPerRound: Int = 3, dataMutationsPerRound: Int = 0
  ) {
    self.init(
      repository: repository, oracle: PythonSiteOracle(interpreter: interpreter, patch: patch, built: built), seed: seed,
      contentMutationsPerRound: contentMutationsPerRound, dataMutationsPerRound: dataMutationsPerRound
    )
  }

  /// Runs round 0 on the repository's own data, then rounds `1...rounds` on mutated copies.
  public func run(rounds: Int, report: (SiteRoundResult) -> Void) throws {
    let plan = MutationPlan(
      repository: repository, seed: seed, contentMutationsPerRound: contentMutationsPerRound, dataMutationsPerRound: dataMutationsPerRound
    )

    try plan.run(rounds: rounds) { round, mutations, workspace in
      report(SiteRoundResult(round: round, mutations: mutations, verdict: try compare(workspace: workspace)))
    }
  }

  /// Builds and compares one copy. A `nil` workspace is the repository's own data.
  func compare(workspace: MutationPlan.Workspace?) throws -> SiteVerdict {
    let copy = try MutationPlan.temporaryCopy(of: repository, applying: workspace)
    defer { try? FileManager.default.removeItem(at: copy) }

    let python = try oracle.build(in: copy)

    switch python {
    case .crashed: return .crashed
    case .noSite: return .noSite
    default: break
    }

    let swiftOutput = copy.appendingPathComponent("swift-site")
    let swift: SiteBuildResult

    do {
      swift = try RepositoryRoot(url: copy).buildSite(into: swiftOutput, patch: oracle.patch, built: oracle.built)
    } catch {
      return .swiftFailed("\(error)")
    }

    switch (python, swift) {
    case (.rejected(let pythonProblems), .refused(let swiftProblems)):
      return .refusedByBoth(python: pythonProblems, swift: swiftProblems)
    case (.rejected(let pythonProblems), .written):
      return .swiftAcceptedWhatPythonRefused(pythonProblems)
    case (.site, .refused(let swiftProblems)):
      return .swiftRefusedWhatPythonAccepted(swiftProblems)
    case (.site(let directory, let pythonSummary), .written(let profiles, let commandSets)):
      if let difference = try SiteComparison.firstDifference(swift: swiftOutput, python: directory) { return .different(difference) }

      let summary = "\(profiles) profiles and \(commandSets) command sets are valid"
      guard pythonSummary == summary else { return .summaryDiffers(swift: summary, python: pythonSummary) }

      let files = try SiteComparison.files(under: swiftOutput)
      return .identical(files: files.count, bytes: files.values.reduce(0) { $0 + $1.count })
    default:
      return .noSite
    }
  }
}
