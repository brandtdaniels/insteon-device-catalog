import ArgumentParser
import CatalogIngest
import Foundation

/// Turns what a device did into a reviewed draft of the catalog's verification marks.
///
/// Nothing here merges anything: a maintainer reads the draft and runs `apply`, then reviews the diff.
struct IngestCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "ingest",
    abstract: "Turn what a device did into a reviewed draft of the catalog's verification marks.",
    discussion: """
      FILE is what `insteon observe` writes. Nothing here merges anything: a maintainer reads the draft \
      and runs apply, then reviews the diff.
      """,
    subcommands: [IngestCheck.self, IngestDraft.self, IngestApply.self]
  )
}

private func finish(_ result: IngestResult) throws {
  FileHandle.standardOutput.write(Data(result.output.utf8))

  if result.status != 0 {
    throw ExitCode(result.status)
  }
}

struct IngestCheck: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "check",
    abstract: "Say whether observation files are valid and free of addresses, hosts and paths.",
    discussion: """
      Validates each file against the observation format and scans every text in it for an Insteon, IP \
      or MAC address, a URL or host name, an email address and a file path. A rejection names the field \
      and the kind of data, never the data.
      """
  )

  @Argument(help: "An observation written by `insteon observe`.")
  var files: [String]

  @Option(name: .long, help: "The repository whose profiles name the models a product name may hold.")
  var root: String = "."

  func validate() throws {
    guard !files.isEmpty else { throw ValidationError("Provide at least one FILE.") }
  }

  func run() throws {
    try finish(IngestTool(root: URL(fileURLWithPath: root, isDirectory: true)).check(files.map { URL(fileURLWithPath: $0) }))
  }
}

struct IngestDraft: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "draft",
    abstract: "Match observations to profiles and write a report of what they would change.",
    discussion: """
      Checks each file, matches it to a profile by category, subcategory and firmware, and writes a \
      report: the verification marks it would add, what the catalog already records, and every \
      disagreement (engine, key, firmware or device) for a maintainer to decide. It writes only \
      verification marks, never a value, and changes no catalog file. A check the device did not answer \
      is never used. The contributor's note is shown in the Markdown and copied nowhere. Exit status: 0 \
      nothing needs a person, 1 a file was rejected, 2 something is left for a maintainer.
      """
  )

  @Argument(help: "An observation written by `insteon observe`.")
  var files: [String]

  @Option(name: .long, help: "Write the machine-readable report here, for apply.")
  var report: String?

  @Option(name: .long, help: "Write the report as Markdown here; without --report or --md it is printed.")
  var md: String?

  @Option(name: .long, help: "The repository whose profiles are drafted against.")
  var root: String = "."

  func validate() throws {
    guard !files.isEmpty else { throw ValidationError("Provide at least one FILE.") }
  }

  func run() throws {
    let tool = IngestTool(root: URL(fileURLWithPath: root, isDirectory: true))

    try finish(tool.draft(files.map { URL(fileURLWithPath: $0) }, report: report.map { URL(fileURLWithPath: $0) }, markdown: md.map { URL(fileURLWithPath: $0) }))
  }
}

struct IngestApply: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "apply",
    abstract: "Write a reviewed draft into the profile files and check the catalog.",
    discussion: """
      Applies the changes in a report written by draft, after a maintainer has read it. It sets only \
      verification marks, from the report's own wording, and refuses a working tree with other changes, \
      a report whose entries do not match the catalog, and any change that is not an observed mark. It \
      then checks the catalog as `catalog check` does, and puts the files back if that fails. Review \
      the diff and commit it yourself.
      """
  )

  @Argument(help: "The file draft wrote with --report.")
  var report: String

  @Option(name: .long, help: "The repository whose profiles are changed.")
  var root: String = "."

  func run() throws {
    try finish(IngestTool(root: URL(fileURLWithPath: root, isDirectory: true)).apply(report: URL(fileURLWithPath: report)))
  }
}
