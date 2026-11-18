import CatalogBuild
import Foundation

/// What checking the catalog found.
public struct CatalogCheckResult: Equatable, Sendable {
  public let passed: Bool
  /// What the check printed, one problem to a line, or empty when it passed.
  public let output: String

  public init(passed: Bool, output: String) {
    self.passed = passed
    self.output = output
  }
}

/// Checks a catalog after apply has changed it.
public protocol CatalogChecking: Sendable {
  /// Checks the catalog in `root`.
  func check(root: URL) -> CatalogCheckResult
}

/// Checks the profiles and command sets against their schemas and the rules beyond them, as
/// `catalog check` does.
public struct RepositoryChecker: CatalogChecking {
  public init() {}

  public func check(root: URL) -> CatalogCheckResult {
    do {
      let problems = try RepositoryRoot(url: root).problems()

      return CatalogCheckResult(passed: problems.isEmpty, output: problems.joined(separator: "\n"))
    } catch {
      return CatalogCheckResult(passed: false, output: "\(error)")
    }
  }
}

/// What apply reads of a git working tree.
public protocol WorkingTreeReading: Sendable {
  /// The lines of `git status --porcelain` for the repository in `root`, one for each changed or untracked path.
  func statusLines(in root: URL) throws -> [String]
}

/// A working tree read by running the `git` command.
public struct ProcessWorkingTree: WorkingTreeReading {
  public init() {}

  /// `git` could not run or reported an error.
  public struct Failure: Error, Equatable {}

  public func statusLines(in root: URL) throws -> [String] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "-C", root.path, "status", "--porcelain"]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
    } catch {
      throw Failure()
    }

    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else { throw Failure() }

    return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init)
  }
}
