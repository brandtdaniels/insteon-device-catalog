import ArgumentParser
import CatalogBuild
import Foundation

/// Checks the profiles and command sets against their schemas and the rules beyond them.
struct Check: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Check the profiles and command sets, and print each problem."
  )

  @Option(name: .long, help: "The repository to check.")
  var root: String = "."

  func run() throws {
    let repository = RepositoryRoot(url: URL(fileURLWithPath: root, isDirectory: true))
    let problems = try repository.problems()

    for problem in problems {
      FileHandle.standardError.write(Data((problem + "\n").utf8))
    }

    guard problems.isEmpty else { throw ExitCode.failure }

    let profiles = try repository.deviceFiles().count
    let commandSets = try repository.commandSetFiles().count
    print("\(profiles) profiles and \(commandSets) command sets are valid")
  }
}
