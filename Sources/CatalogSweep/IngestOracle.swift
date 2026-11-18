import Foundation

/// What one run of a tool did: its exit status and what it printed.
public struct IngestRun: Equatable, Sendable {
  public let status: Int32
  public let standardOutput: String

  public init(status: Int32, standardOutput: String) {
    self.status = status
    self.standardOutput = standardOutput
  }
}

/// Runs `scripts/ingest.py` as it is, in a copy of the repository.
///
/// Transitional: `scripts/ingest.py` is the oracle while the Python ingestion exists. Nothing here
/// writes Python.
public struct IngestOracle: Sendable {
  public let interpreter: String

  public init(interpreter: String = "python3") {
    self.interpreter = interpreter
  }

  /// Runs `ingest.py` with the arguments, in `root`, which holds `scripts/` and the catalog it reads.
  public func run(_ arguments: [String], in root: URL) throws -> IngestRun {
    let output = FileManager.default.temporaryDirectory.appendingPathComponent("ingest-oracle-" + UUID().uuidString)
    _ = FileManager.default.createFile(atPath: output.path, contents: nil)
    defer { try? FileManager.default.removeItem(at: output) }

    let handle = try FileHandle(forWritingTo: output)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [interpreter, "-I", "scripts/ingest.py"] + arguments
    process.currentDirectoryURL = root
    process.standardOutput = handle
    process.standardError = handle
    try process.run()
    process.waitUntilExit()
    try handle.close()

    let text = String(decoding: try Data(contentsOf: output), as: UTF8.self)

    return IngestRun(status: process.terminationStatus, standardOutput: text)
  }
}

/// Runs git in a directory with a fixed identity and no access to the user's configuration.
enum IngestGit {
  @discardableResult
  static func run(_ arguments: [String], in directory: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "-c", "commit.gpgsign=false", "-C", directory.path] + arguments
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

    return String(decoding: data, as: UTF8.self)
  }

  /// Starts a repository in the directory and commits everything in it.
  static func initialize(_ directory: URL) throws {
    try run(["init", "--quiet"], in: directory)
    try commitAll("start", in: directory)
  }

  static func commitAll(_ message: String, in directory: URL) throws {
    try run(["add", "--all"], in: directory)
    try run(["commit", "--quiet", "--allow-empty", "--message", message], in: directory)
  }
}
