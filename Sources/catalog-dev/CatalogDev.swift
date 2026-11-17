import ArgumentParser
import CatalogSweep
import Foundation

/// Developer tooling for the catalog repository. Not part of a release.
@main
struct CatalogDev: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "catalog-dev",
    abstract: "Developer tooling for the Insteon device catalog.",
    subcommands: [SweepCommand.self]
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

  @Option(help: "The Python interpreter that runs scripts/build.py.")
  var python: String = "python3"

  @Option(help: "A file to write the distinct rule messages the sweep compared to, one per line.")
  var messagesFile: String?

  func run() throws {
    let sweep = Sweep(
      repository: URL(fileURLWithPath: root, isDirectory: true), interpreter: python, seed: seed, mutationsPerRound: mutationsPerRound
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
