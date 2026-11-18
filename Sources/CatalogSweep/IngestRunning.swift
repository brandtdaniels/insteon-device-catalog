import CatalogIngest
import Foundation

/// Something that runs the ingestion tool's command line in a root.
public protocol IngestRunning: Sendable {
  /// Runs `check FILE...`, `draft FILE... [--report PATH] [--md PATH]` or `apply REPORT` in `root`.
  func run(_ arguments: [String], in root: URL) throws -> IngestRun
}

extension IngestOracle: IngestRunning {}

/// Runs the command line on the Swift tool.
public struct SwiftIngestRunner: IngestRunning {
  public init() {}

  public func run(_ arguments: [String], in root: URL) throws -> IngestRun {
    let tool = IngestTool(root: root)
    var words = arguments[...]
    guard let command = words.popFirst() else { return IngestRun(status: 2, standardOutput: "") }

    var files: [URL] = []
    var report: URL?
    var markdown: URL?

    while let word = words.popFirst() {
      switch word {
      case "--report": report = words.popFirst().map { URL(fileURLWithPath: $0) }
      case "--md": markdown = words.popFirst().map { URL(fileURLWithPath: $0) }
      default: files.append(URL(fileURLWithPath: word))
      }
    }

    let result: IngestResult

    switch command {
    case "check": result = tool.check(files)
    case "draft": result = tool.draft(files, report: report, markdown: markdown)
    case "apply": result = files.first.map { tool.apply(report: $0) } ?? IngestResult(status: 2, output: "")
    default: result = IngestResult(status: 2, output: "")
    }

    return IngestRun(status: result.status, standardOutput: result.output)
  }
}
