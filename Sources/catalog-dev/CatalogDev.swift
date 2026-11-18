import ArgumentParser
import CatalogBuild
import CatalogSite
import CatalogSweep
import Foundation

/// Developer tooling for the catalog repository. Not part of a release.
@main
struct CatalogDev: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "catalog-dev",
    abstract: "Developer tooling for the Insteon device catalog.",
    subcommands: [
      SweepCommand.self, ScenariosCommand.self, ComparePageCommand.self, PageSweepCommand.self, CompareSiteCommand.self
    ]
  )
}

/// Compares the Swift rules with the Python build on mutated copies of the data.
///
/// Transitional: `scripts/build.py` is the oracle while the Python build exists.
struct SweepCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "sweep",
    abstract: "Run the Swift rules and the Python build on mutated copies of the data and compare them."
  )

  @Option(help: "The repository to mutate and check.")
  var root: String = "."

  @Option(help: "How many mutated copies to check.")
  var rounds: Int = 20

  @Option(help: "The seed of the first round. The same seed makes the same mutations.")
  var seed: UInt64 = 1

  @Option(help: "How many data files each round changes.")
  var mutationsPerRound: Int = 30

  @Option(help: "How many changes to the registry, sources, terms and dashes each round makes after its data changes.")
  var ruleMutationsPerRound: Int = 3

  @Option(help: "The Python interpreter that runs scripts/build.py.")
  var python: String = "python3"

  @Option(help: "A file to write the distinct rule messages the sweep compared to, one per line.")
  var messagesFile: String?

  func run() throws {
    let sweep = Sweep(
      repository: URL(fileURLWithPath: root, isDirectory: true), interpreter: python, seed: seed, mutationsPerRound: mutationsPerRound,
      ruleMutationsPerRound: ruleMutationsPerRound
    )
    var divergences = 0
    var crashes = 0
    var checked = 0
    var ruleMessages = 0
    var schemaErrors = 0
    var distinctMessages = Set<String>()

    try sweep.run(rounds: rounds) { result in
      checked += 1
      crashes += result.pythonCrashed ? 1 : 0
      ruleMessages += result.pythonOutcome.ruleMessages.count
      schemaErrors += result.pythonOutcome.schemaErrors.count
      distinctMessages.formUnion(result.pythonOutcome.ruleMessages)

      guard !result.agrees || result.pythonCrashed else { return }
      divergences += result.agrees ? 0 : 1
      print("round \(result.round)\(result.pythonCrashed ? " (the Python build crashed)" : "")")
      result.mutations.forEach { print("  mutation: \($0)") }
      result.ruleMutations.forEach { print("  rule mutation: \($0)") }
      let swift = result.swiftOutcome, python = result.pythonOutcome
      print("  rule messages only in Swift: \(Comparison.lines(swift.ruleMessages, notIn: python.ruleMessages))")
      print("  rule messages only in Python: \(Comparison.lines(python.ruleMessages, notIn: swift.ruleMessages))")
      print("  rule messages in a different order: \(swift.ruleMessages != python.ruleMessages && Set(swift.ruleMessages) == Set(python.ruleMessages))")
      print("  schema errors match: \(Comparison.schemaErrorsMatch(swift: swift.schemaErrors, python: python.schemaErrors))")
      for line in swift.schemaLines { print("    Swift:  \(line)") }
      for line in python.schemaLines { print("    Python: \(line)") }
    }

    if let messagesFile {
      let text = distinctMessages.sorted().joined(separator: "\n") + "\n"
      try Data(text.utf8).write(to: URL(fileURLWithPath: messagesFile))
    }

    print("\(checked) rounds, \(divergences) divergences, \(crashes) Python crashes")
    print("compared \(ruleMessages) rule messages (\(distinctMessages.count) distinct) and \(schemaErrors) schema errors")

    if divergences > 0 {
      throw ExitCode.failure
    }
  }
}

/// Runs the hand-picked scenarios on the Swift rules and the Python build and compares them.
///
/// Transitional: `scripts/build.py` is the oracle while the Python build exists.
struct ScenariosCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "scenarios",
    abstract: "Run the hand-picked scenarios on the Swift rules and the Python build and compare them."
  )

  @Option(help: "The repository to change and check.")
  var root: String = "."

  @Option(help: "The Python interpreter that runs scripts/build.py.")
  var python: String = "python3"

  func run() throws {
    let sweep = Sweep(repository: URL(fileURLWithPath: root, isDirectory: true), interpreter: python)
    var failures = 0
    var checked = 0

    try sweep.runScenarios(Scenarios.all) { result in
      checked += 1
      guard !result.agrees else { return }
      failures += 1
      print("scenario: \(result.scenario.name)")
      print("  expected messages missing: \(result.missing)")
      print("  rule messages only in Swift: \(Comparison.lines(result.swiftOutcome.ruleMessages, notIn: result.pythonOutcome.ruleMessages))")
      print("  rule messages only in Python: \(Comparison.lines(result.pythonOutcome.ruleMessages, notIn: result.swiftOutcome.ruleMessages))")
      print("  schema errors match: \(Comparison.schemaErrorsMatch(swift: result.swiftOutcome.schemaErrors, python: result.pythonOutcome.schemaErrors))")
      result.pythonOutcome.schemaLines.forEach { print("    Python: \($0)") }
    }

    print("\(checked) scenarios, \(failures) failures")

    if failures > 0 {
      throw ExitCode.failure
    }
  }
}

/// Compares the Swift landing page with the Python build's page, one fragment at a time and then
/// byte for byte.
///
/// Transitional: `scripts/build.py` is the oracle while the Python build exists.
struct ComparePageCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "compare-page",
    abstract: "Render the landing page with Swift and with the Python build, and compare the two."
  )

  @Option(help: "The repository to render.")
  var root: String = "."

  @Option(help: "The Python interpreter that runs scripts/build.py.")
  var python: String = "python3"

  @Option(help: "The version's PATCH number.")
  var patch: Int = 0

  @Option(help: "A page the Python build already wrote, to compare with instead of running the build.")
  var pythonPage: String?

  func run() throws {
    let repository = RepositoryRoot(url: URL(fileURLWithPath: root, isDirectory: true))
    let pythonText: String

    if let pythonPage {
      pythonText = String(decoding: try Data(contentsOf: URL(fileURLWithPath: pythonPage)), as: UTF8.self)
    } else {
      switch try PageOracle(interpreter: python, patch: patch).build(in: try PageSweep.temporaryCopy(of: repository.url)) {
      case .page(let page): pythonText = page
      case .rejected(let problems):
        problems.forEach { print($0) }
        throw ExitCode.failure
      case .crashed, .noPage:
        print("the Python build wrote no page")
        throw ExitCode.failure
      }
    }

    let input = try repository.siteInput(patch: patch)
    let swiftPage = try SitePage.render(input, template: try repository.pageTemplate())
    var failed = false

    for result in FragmentComparison.compare(swift: try SitePage.fragments(input), pythonPage: pythonText) {
      print("\(result.name): \(result.identical) of \(result.total) identical")
      if let difference = result.firstDifference {
        failed = true
        print("  \(difference)")
      }
    }

    if let difference = PageComparison.firstDifference(swift: swiftPage, python: pythonText) {
      failed = true
      print("full page: DIFFERENT, \(difference)")
    } else {
      print("full page: identical, \(swiftPage.utf8.count) bytes")
    }

    if failed { throw ExitCode.failure }
  }
}

/// Renders the landing page with Swift and the Python build on the repository's data and on
/// mutated copies of it, and compares the two pages byte for byte.
///
/// Transitional: `scripts/build.py` is the oracle while the Python build exists.
struct PageSweepCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "page-sweep",
    abstract: "Compare the Swift landing page with the Python build's on the data and on mutated copies of it."
  )

  @Option(help: "The repository to mutate and render.")
  var root: String = "."

  @Option(help: "How many mutated copies to render, after the repository's own data.")
  var rounds: Int = 20

  @Option(help: "The seed of the first round. The same seed makes the same mutations.")
  var seed: UInt64 = 1

  @Option(help: "How many changes to what a card shows each round makes.")
  var contentMutationsPerRound: Int = 3

  @Option(help: "How many changes from the data sweep's mutator each round makes as well.")
  var dataMutationsPerRound: Int = 0

  @Option(help: "The Python interpreter that runs scripts/build.py.")
  var python: String = "python3"

  func run() throws {
    let sweep = PageSweep(
      repository: URL(fileURLWithPath: root, isDirectory: true), interpreter: python, seed: seed,
      contentMutationsPerRound: contentMutationsPerRound, dataMutationsPerRound: dataMutationsPerRound
    )
    var compared = 0
    var rejected = 0
    var differences = 0
    var disagreements = 0
    var broken = 0
    var kinds: [String: (compared: Int, refused: Int)] = [:]

    try sweep.run(rounds: rounds) { result in
      switch result.verdict {
      case .identical: compared += 1
      case .different(let difference, let fragments):
        compared += 1
        differences += 1
        print("round \(result.round): DIFFERENT")
        result.mutations.forEach { print("  mutation: \($0)") }
        print("  \(difference)")
        for fragment in fragments where !fragment.agrees { print("  \(fragment.name): \(fragment.identical) of \(fragment.total) identical") }
      case .rejected(let problems):
        rejected += 1
        if !result.buildsAgree {
          print("round \(result.round): the Python build refused the data and the Swift rules accepted it")
          result.mutations.forEach { print("  mutation: \($0)") }
          problems.prefix(3).forEach { print("    Python: \($0)") }
        }
      case .crashed, .noPage, .swiftFailed:
        broken += 1
        print("round \(result.round): \(result.verdict)")
        result.mutations.forEach { print("  mutation: \($0)") }
      }

      if case .identical = result.verdict, !result.buildsAgree {
        print("round \(result.round): the Swift rules refused data the Python build accepted")
        result.mutations.forEach { print("  mutation: \($0)") }
      }

      disagreements += result.buildsAgree ? 0 : 1
      for mutation in result.mutations {
        // A data change starts with its file; a content change starts with its kind.
        let words = mutation.split(separator: " ")
        let kind = String(words.first.map { $0.contains("/") ? (words.dropFirst().first ?? $0) : $0 } ?? "")
        var counts = kinds[kind] ?? (0, 0)
        if case .rejected = result.verdict { counts.refused += 1 } else { counts.compared += 1 }
        kinds[kind] = counts
      }
    }

    print("\(rounds) mutated rounds and the repository's own data: \(compared) pages compared, \(differences) different, \(rejected) refused by the Python build, \(broken) broken")
    print("rule verdicts that disagreed: \(disagreements)")
    print("changes by kind, as compared or refused by the Python build:")
    for (kind, counts) in kinds.sorted(by: { $0.key < $1.key }) { print("  \(kind): \(counts.compared) compared, \(counts.refused) refused") }

    if differences > 0 || disagreements > 0 || broken > 0 { throw ExitCode.failure }
  }
}
