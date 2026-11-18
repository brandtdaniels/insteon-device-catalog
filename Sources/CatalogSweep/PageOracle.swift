import Foundation

/// What the Python build did with a copy of the repository.
public enum PageOracleOutcome: Equatable, Sendable {
  /// It wrote the landing page.
  case page(String)
  /// It refused the data and printed these problems.
  case rejected([String])
  /// It stopped with a traceback.
  case crashed
  /// It finished without writing a page.
  case noPage
}

/// Something that builds the landing page of a copy of the repository, to compare with the Swift page.
public protocol PageBuilding: Sendable {
  /// The version's PATCH number the page is built with.
  var patch: Int { get }

  /// Builds the copy's page.
  func build(in directory: URL) throws -> PageOracleOutcome
}

/// Runs the Python build on a copy of the repository and reads the landing page it writes.
///
/// Transitional: `scripts/build.py` is the oracle while the Python build exists. Nothing here
/// writes Python; it runs `scripts/build.py` as it is.
public struct PageOracle: PageBuilding {
  public let interpreter: String
  public let patch: Int

  public init(interpreter: String = "python3", patch: Int = 0) {
    self.interpreter = interpreter
    self.patch = patch
  }

  /// Builds the copy's page with the Python build.
  public func build(in directory: URL) throws -> PageOracleOutcome {
    let output = directory.appendingPathComponent("python-site")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [interpreter, "-I", "scripts/build.py", "--output", output.path, "--patch", String(patch)]
    process.currentDirectoryURL = directory

    let errors = Pipe()
    process.standardError = errors
    process.standardOutput = FileHandle.nullDevice

    try process.run()
    let text = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()

    if text.contains("Traceback (most recent call last)") { return .crashed }

    if process.terminationStatus != 0 {
      return .rejected(text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init))
    }

    guard let data = try? Data(contentsOf: output.appendingPathComponent("index.html")) else { return .noPage }

    return .page(String(decoding: data, as: UTF8.self))
  }
}
