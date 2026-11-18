import CatalogBuild
import CatalogJSON
import CatalogSite
import Foundation

/// How the Swift page compares with the Python build's page for one copy of the data.
public enum PageVerdict: Equatable, Sendable {
  /// The two pages are the same bytes.
  case identical(bytes: Int)
  /// The pages differ; the fragment results say where.
  case different(PageDifference, [FragmentResult])
  /// The Python build refused the data, so there is no page to compare.
  case rejected([String])
  /// The Python build stopped with a traceback.
  case crashed
  /// The Python build wrote no page.
  case noPage
  /// The Swift renderer could not render the copy.
  case swiftFailed(String)
}

/// One round: the changes made and how the two pages compare.
public struct PageRoundResult: Sendable {
  /// The round number; round 0 is the repository's own data.
  public let round: Int
  public let mutations: [String]
  public let verdict: PageVerdict
  /// Whether the Swift rules found no problem in the copy. A copy the Python build refused and the
  /// Swift rules accept, or the other way round, is a difference between the two rule sets.
  public let swiftAccepted: Bool

  /// Whether the two builds took or refused the copy together.
  public var buildsAgree: Bool {
    switch verdict {
    case .rejected: !swiftAccepted
    case .identical, .different: swiftAccepted
    default: true
    }
  }

  /// Whether nothing differs: the pages are the same, or the data was refused by both builds.
  public var agrees: Bool {
    switch verdict {
    case .identical: buildsAgree
    case .rejected: buildsAgree
    default: false
    }
  }
}

/// Renders the landing page with the Swift renderer and the Python build on the repository's data
/// and on mutated copies of it, and compares the two pages byte for byte.
///
/// Transitional: `scripts/build.py` is the oracle while the Python build exists.
public struct PageSweep: Sendable {
  public let repository: URL
  public let oracle: any PageBuilding
  public let seed: UInt64
  /// How many changes to what a card shows each round makes.
  public let contentMutationsPerRound: Int
  /// How many changes the data sweep's mutator makes each round, on top of the content changes.
  public let dataMutationsPerRound: Int
  /// Whether each round also runs the Swift rules on its copy, to see that both builds take or refuse it together.
  public let checksRules: Bool

  /// A sweep that compares with the pages `oracle` builds.
  public init(
    repository: URL, oracle: any PageBuilding, seed: UInt64 = 1, contentMutationsPerRound: Int = 3, dataMutationsPerRound: Int = 0,
    checksRules: Bool = true
  ) {
    self.checksRules = checksRules
    self.repository = repository
    self.oracle = oracle
    self.seed = seed
    self.contentMutationsPerRound = contentMutationsPerRound
    self.dataMutationsPerRound = dataMutationsPerRound
  }

  /// A sweep that compares with the Python build run by `interpreter`.
  public init(
    repository: URL, interpreter: String = "python3", patch: Int = 0, seed: UInt64 = 1, contentMutationsPerRound: Int = 3,
    dataMutationsPerRound: Int = 0, checksRules: Bool = true
  ) {
    self.init(
      repository: repository, oracle: PageOracle(interpreter: interpreter, patch: patch), seed: seed,
      contentMutationsPerRound: contentMutationsPerRound, dataMutationsPerRound: dataMutationsPerRound, checksRules: checksRules
    )
  }

  /// Runs round 0 on the repository's own data, then rounds `1...rounds` on mutated copies.
  public func run(rounds: Int, report: (PageRoundResult) -> Void) throws {
    let plan = MutationPlan(
      repository: repository, seed: seed, contentMutationsPerRound: contentMutationsPerRound, dataMutationsPerRound: dataMutationsPerRound
    )

    try plan.run(rounds: rounds) { round, mutations, workspace in
      report(try compare(round: round, mutations: mutations, workspace: workspace))
    }
  }

  /// Renders and compares one copy. A `nil` workspace is the repository's own data.
  func compare(round: Int, mutations: [String], workspace: MutationPlan.Workspace?) throws -> PageRoundResult {
    let copy = try makeCopy(applying: workspace)
    defer { try? FileManager.default.removeItem(at: copy) }

    let root = RepositoryRoot(url: copy)
    let swiftAccepted = checksRules ? ((try? root.problems().isEmpty) ?? false) : true
    let python = try oracle.build(in: copy)

    guard case .page(let pythonPage) = python else {
      let verdict: PageVerdict = switch python {
      case .rejected(let problems): .rejected(problems)
      case .crashed: .crashed
      default: .noPage
      }
      return PageRoundResult(round: round, mutations: mutations, verdict: verdict, swiftAccepted: swiftAccepted)
    }

    let input: SiteInput
    let swiftPage: String

    do {
      input = try root.siteInput(patch: oracle.patch)
      swiftPage = try SitePage.render(input, template: try root.pageTemplate())
    } catch {
      return PageRoundResult(round: round, mutations: mutations, verdict: .swiftFailed("\(error)"), swiftAccepted: swiftAccepted)
    }

    guard let difference = PageComparison.firstDifference(swift: swiftPage, python: pythonPage) else {
      return PageRoundResult(round: round, mutations: mutations, verdict: .identical(bytes: swiftPage.utf8.count), swiftAccepted: swiftAccepted)
    }

    let fragments = (try? SitePage.fragments(input)).map { FragmentComparison.compare(swift: $0, pythonPage: pythonPage) } ?? []
    return PageRoundResult(round: round, mutations: mutations, verdict: .different(difference, fragments), swiftAccepted: swiftAccepted)
  }

  /// A copy of what the Python build reads, in a temporary folder.
  public static func temporaryCopy(of repository: URL) throws -> URL {
    let copy = FileManager.default.temporaryDirectory.appendingPathComponent("catalog-page-sweep-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)

    for name in Sweep.copied {
      do {
        try FileManager.default.copyItem(at: repository.appendingPathComponent(name), to: copy.appendingPathComponent(name))
      } catch {
        throw SweepError.copyFailed("\(name): \(error.localizedDescription)")
      }
    }

    return copy
  }

  /// A copy of what the Python build reads, with the workspace's changes written into it.
  private func makeCopy(applying workspace: MutationPlan.Workspace?) throws -> URL {
    try MutationPlan.temporaryCopy(of: repository, applying: workspace)
  }
}
