import ArgumentParser
import CatalogBuild
import Foundation

/// Fails when a change to the schemas doesn't raise `VERSION`.
struct VersionCheckCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "version-check",
    abstract: "Fail when a schema change doesn't raise VERSION.",
    discussion: """
      While the catalog is below 1.0, any schema change raises MINOR. From 1.0, an additive change \
      raises MINOR and a breaking one MAJOR. Run in a pull request, with the base branch's commit \
      as the argument.
      """
  )

  @Argument(help: "The base branch's commit.")
  var base: String

  @Option(name: .long, help: "The repository to check.")
  var root: String = "."

  func run() throws {
    let url = URL(fileURLWithPath: root, isDirectory: true)
    do {
      try VersionCheck(git: ProcessGit(root: url)).verify(base: base, root: url)
    } catch {
      FileHandle.standardError.write(Data((error.description + "\n").utf8))
      throw ExitCode.failure
    }
  }
}
