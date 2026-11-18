import ArgumentParser
import CatalogSweep
import Foundation

/// Builds the site with Swift and with the Python build, on the repository's data and on mutated
/// copies of it, and compares the two directories byte for byte.
///
/// Transitional: `scripts/build.py` is the oracle while the Python build exists.
struct CompareSiteCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "compare-site",
    abstract: "Build the site with Swift and with the Python build, and compare every file byte for byte.",
    discussion: """
      Round 0 is the repository's own data. Each later round changes a copy of the data and builds \
      it with both. A copy is compared only when both builds accept it; when both refuse it, the \
      round agrees. A copy one build refuses and the other accepts is a difference. Plain swift \
      test never runs the Python build; only this command does.
      """
  )

  @Option(help: "The repository to build and mutate.")
  var root: String = "."

  @Option(help: "How many mutated copies to build, after the repository's own data.")
  var rounds: Int = 20

  @Option(help: "The seed of the first round. The same seed makes the same mutations.")
  var seed: UInt64 = 1

  @Option(help: "The version's PATCH number both builds use.")
  var patch: Int = 0

  @Option(help: "The build time both builds put in the manifest.")
  var built: String = "2000-01-01T00:00:00Z"

  @Option(help: "How many changes to what a card shows each round makes.")
  var contentMutationsPerRound: Int = 3

  @Option(help: "How many changes from the data sweep's mutator each round makes as well.")
  var dataMutationsPerRound: Int = 0

  @Option(help: "The Python interpreter that runs scripts/build.py.")
  var python: String = "python3"

  func run() throws {
    let sweep = SiteSweep(
      repository: URL(fileURLWithPath: root, isDirectory: true), interpreter: python, patch: patch, built: built, seed: seed,
      contentMutationsPerRound: contentMutationsPerRound, dataMutationsPerRound: dataMutationsPerRound
    )
    var compared = 0
    var refused = 0
    var differences = 0
    var disagreements = 0
    var broken = 0

    try sweep.run(rounds: rounds) { result in
      func describe(_ title: String) {
        print("round \(result.round): \(title)")
        result.mutations.forEach { print("  mutation: \($0)") }
      }

      switch result.verdict {
      case .identical(let files, let bytes):
        compared += 1
        if result.round == 0 { print("repository data: \(files) files identical, \(bytes) bytes") }
      case .different(let difference):
        compared += 1
        differences += 1
        describe("DIFFERENT")
        print("  \(difference)")
      case .summaryDiffers(let swift, let python):
        compared += 1
        differences += 1
        describe("the printed summary differs")
        print("  Swift:  \(swift)")
        print("  Python: \(python ?? "nothing")")
      case .refusedByBoth:
        refused += 1
      case .swiftRefusedWhatPythonAccepted(let problems):
        disagreements += 1
        describe("the Swift build refused data the Python build accepted")
        problems.prefix(3).forEach { print("    Swift: \($0)") }
      case .swiftAcceptedWhatPythonRefused(let problems):
        disagreements += 1
        describe("the Python build refused data the Swift build accepted")
        problems.prefix(3).forEach { print("    Python: \($0)") }
      case .crashed, .noSite, .swiftFailed:
        broken += 1
        describe("\(result.verdict)")
      }
    }

    print("\(rounds) mutated rounds and the repository's own data: \(compared) compared, \(differences) different, \(refused) refused by both builds")
    print("builds that disagreed on whether to accept the data: \(disagreements); broken rounds: \(broken)")

    if differences > 0 || disagreements > 0 || broken > 0 { throw ExitCode.failure }
  }
}
