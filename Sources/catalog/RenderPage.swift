import ArgumentParser
import CatalogBuild
import CatalogSite
import Foundation

/// Writes the landing page.
struct RenderPage: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "render-page",
    abstract: "Check the catalog, then write the landing page for its data."
  )

  @Option(name: .long, help: "The repository to render.")
  var root: String = "."

  @Option(name: .long, help: "The file to write the page to.")
  var output: String

  @Option(name: .long, help: "The version's PATCH number.")
  var patch: Int = 0

  func run() throws {
    let repository = RepositoryRoot(url: URL(fileURLWithPath: root, isDirectory: true))
    let problems = try repository.problems()

    for problem in problems {
      FileHandle.standardError.write(Data((problem + "\n").utf8))
    }

    guard problems.isEmpty else { throw ExitCode.failure }

    let page = try repository.indexPage(patch: patch)
    let file = URL(fileURLWithPath: output)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(page.utf8).write(to: file)
    print("wrote \(output), \(page.utf8.count) bytes")
  }
}
