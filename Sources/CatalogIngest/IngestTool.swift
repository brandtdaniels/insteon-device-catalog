import CatalogBuild
import CatalogJSON
import Foundation

/// What a command printed and the exit status it ends with.
public struct IngestResult: Equatable, Sendable {
  public let status: Int32
  public let output: String

  public init(status: Int32, output: String) {
    self.status = status
    self.output = output
  }
}

/// The three commands of the observation lane, `check`, `draft` and `apply`, on the catalog in a repository.
///
/// Nothing here reads a network. A command reads the files it is given and the repository's profiles,
/// and writes only the report files and, for `apply`, the profiles a reviewed report names.
public struct IngestTool: Sendable {
  public let root: URL
  private let checker: any CatalogChecking
  private let tree: any WorkingTreeReading

  public init(root: URL, checker: any CatalogChecking = RepositoryChecker(), tree: any WorkingTreeReading = ProcessWorkingTree()) {
    self.root = root
    self.checker = checker
    self.tree = tree
  }

  /// Says whether each file may be drafted from, naming files by their content's fingerprint because a
  /// file name can be an address. Exit status 1 when any file is not valid.
  public func check(_ files: [URL]) -> IngestResult {
    let models = ProfileCatalog.models(in: root)
    var lines: [String] = []
    var status: Int32 = 0

    for (offset, file) in files.enumerated() {
      let label = ObservationFile.label(position: offset + 1, of: file)
      let errors: [String]

      switch ObservationFile.load(file) {
      case .loaded(let data): errors = ObservationCheck.problems(in: data, models: models)
      case .rejected(let reasons): errors = reasons
      }

      if errors.isEmpty {
        lines.append("\(label): valid")
      } else {
        status = 1
        lines.append("\(label): not valid")
        lines += errors.map { "  \($0)" }
      }
    }

    return IngestResult(status: status, output: Self.printed(lines))
  }

  /// Drafts every file, then writes or prints the report.
  ///
  /// Exit status: 0 when nothing needs a person, 1 when a file was rejected, 2 when something is left
  /// for a maintainer.
  public func draft(_ files: [URL], report reportFile: URL?, markdown markdownFile: URL?) -> IngestResult {
    let catalog: ProfileCatalog

    do {
      catalog = try ProfileCatalog.load(from: RepositoryRoot(url: root))
    } catch {
      return IngestResult(status: 1, output: "\(error)\n")
    }

    let drafted = ReportDrafting.draft(files, in: catalog)
    let markdown = drafted.markdown

    do {
      if let reportFile { try Data(drafted.report.text.utf8).write(to: reportFile) }
      if let markdownFile { try Data(markdown.utf8).write(to: markdownFile) }
    } catch {
      return IngestResult(status: 1, output: "cannot write the report\n")
    }

    let output = reportFile != nil || markdownFile != nil
      ? Self.printed(drafted.report.observations.map { "\($0.label): \($0.outcome.rawValue)" })
      : markdown

    if drafted.report.outcome == .rejected { return IngestResult(status: 1, output: output) }

    return IngestResult(status: drafted.report.hasDisagreements ? 2 : 0, output: output)
  }

  /// Applies a reviewed report to the profile files and checks the catalog.
  public func apply(report file: URL) -> IngestResult {
    guard let data = try? Data(contentsOf: file), let report = try? JSONParser.parse([UInt8](data)) else {
      return IngestResult(status: 1, output: "cannot read the report\n")
    }

    let outcome = ReportApplication.apply(report, in: root, checker: checker, tree: tree, allowed: allowedPaths(for: file))

    return IngestResult(status: outcome.status, output: Self.printed(outcome.messages))
  }

  /// The report's path inside the repository, which may stay untracked, or nothing when it lies outside.
  private func allowedPaths(for report: URL) -> Set<String> {
    let base = root.standardizedFileURL.resolvingSymlinksInPath().path
    let path = report.standardizedFileURL.resolvingSymlinksInPath().path

    guard path.hasPrefix(base + "/") else { return [] }

    return [String(path.dropFirst(base.count + 1))]
  }

  private static func printed(_ lines: [String]) -> String {
    lines.map { $0 + "\n" }.joined()
  }
}
