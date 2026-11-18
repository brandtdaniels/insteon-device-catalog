import Foundation

/// A throwaway git repository in a temporary directory, with a fixed identity and no access to
/// the user's git configuration or the network.
final class TemporaryRepository {
  let url: URL

  init() throws {
    url = FileManager.default.temporaryDirectory.appendingPathComponent("catalog-git-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try git("init", "--quiet")
  }

  deinit {
    try? FileManager.default.removeItem(at: url)
  }

  /// Writes a file, creating its directories.
  func write(_ path: String, _ text: String) throws {
    let file = url.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: file)
  }

  func remove(_ path: String) throws {
    try FileManager.default.removeItem(at: url.appendingPathComponent(path))
  }

  func move(_ from: String, to: String) throws {
    let destination = url.appendingPathComponent(to)
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: url.appendingPathComponent(from), to: destination)
  }

  /// Stages everything and commits it, returning the new commit's hash.
  @discardableResult
  func commit(_ message: String) throws -> String {
    try git("add", "--all")
    try git("commit", "--quiet", "--allow-empty", "--message", message)
    return try git("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  @discardableResult
  func git(_ arguments: String...) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "-c", "commit.gpgsign=false", "-C", url.path] + arguments
    var environment = ProcessInfo.processInfo.environment
    for (key, value) in [
      "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
      "GIT_AUTHOR_NAME": "Catalog Test", "GIT_AUTHOR_EMAIL": "catalog-test@example.invalid",
      "GIT_COMMITTER_NAME": "Catalog Test", "GIT_COMMITTER_EMAIL": "catalog-test@example.invalid"
    ] {
      environment[key] = value
    }
    process.environment = environment
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw GitFailure(arguments: arguments) }
    return String(decoding: data, as: UTF8.self)
  }

  struct GitFailure: Error { let arguments: [String] }
}
