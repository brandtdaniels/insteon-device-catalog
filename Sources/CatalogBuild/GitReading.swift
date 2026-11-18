import Foundation

/// A git command that failed or couldn't start.
public struct GitError: Error, Equatable, Sendable {
  /// The arguments that were given to `git`.
  public let arguments: [String]

  public init(arguments: [String]) {
    self.arguments = arguments
  }
}

/// What the version rule reads from a repository's history.
public protocol GitReading: Sendable {
  /// The text of a file as it is at a revision, or `nil` when git can't show it.
  func contents(of path: String, at revision: String) -> String?

  /// The paths that differ between two revisions, relative to the repository root.
  func changedPaths(from base: String, to head: String) throws(GitError) -> [String]
}

/// A repository read by running the `git` command.
public struct ProcessGit: GitReading {
  /// The working directory of the repository.
  public let root: URL

  public init(root: URL) {
    self.root = root
  }

  public func contents(of path: String, at revision: String) -> String? {
    guard let output = try? run(["show", "\(revision):\(path)"]) else { return nil }
    return String(decoding: output, as: UTF8.self)
  }

  public func changedPaths(from base: String, to head: String) throws(GitError) -> [String] {
    let output = try run(["diff", "--name-only", "--no-renames", "-z", base, head])
    return String(decoding: output, as: UTF8.self).split(separator: "\0").map(String.init)
  }

  private func run(_ arguments: [String]) throws(GitError) -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "-C", root.path] + arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      throw GitError(arguments: arguments)
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw GitError(arguments: arguments) }
    return data
  }
}
