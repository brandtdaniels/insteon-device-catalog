import ArgumentParser

/// The catalog tooling command. Subcommands are added as the tooling moves to Swift.
@main
struct Catalog: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "catalog",
    abstract: "Tooling for the Insteon device catalog.",
    subcommands: [Check.self, VersionCheckCommand.self, RenderPage.self, Build.self, IngestCommand.self]
  )
}
