import ArgumentParser
import CatalogBuild
import CatalogSite
import Foundation

/// Checks the catalog, then writes the site it publishes.
struct Build: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Check the catalog, then write its site: the catalog, its manifest, the schemas and the landing page.",
    discussion: """
      The site goes in --output: index.html, and v<MAJOR>/ with catalog.json, manifest.json and a \
      copy of each schema. A catalog with problems prints them and writes nothing.
      """
  )

  @Option(name: .long, help: "The repository to build.")
  var root: String = "."

  @Option(name: .long, help: "The directory to write the site to.")
  var output: String

  @Option(name: .long, help: "The version's PATCH number.")
  var patch: Int = 0

  @Option(name: .long, help: "When the catalog was built, as an ISO 8601 date and time.")
  var built: String?

  func run() throws {
    let repository = RepositoryRoot(url: URL(fileURLWithPath: root, isDirectory: true))
    let result: SiteBuildResult

    do {
      result = try repository.buildSite(into: URL(fileURLWithPath: output, isDirectory: true), patch: patch, built: built)
    } catch let problem as VersionProblem {
      FileHandle.standardError.write(Data((problem.description + "\n").utf8))
      throw ExitCode.failure
    }

    switch result {
    case .refused(let problems):
      for problem in problems {
        FileHandle.standardError.write(Data((problem + "\n").utf8))
      }

      throw ExitCode.failure
    case .written(let profiles, let commandSets):
      print("\(profiles) profiles and \(commandSets) command sets are valid")
    }
  }
}
