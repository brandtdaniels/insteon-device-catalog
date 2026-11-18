import Foundation

/// What the Python build did with a copy of the repository.
public enum SiteOracleOutcome: Equatable, Sendable {
  /// It wrote a site into the directory, after printing the summary line.
  case site(directory: URL, summary: String?)
  /// It refused the data and printed these problems.
  case rejected([String])
  /// It stopped with a traceback.
  case crashed
  /// It finished without writing a site.
  case noSite
}

/// Something that builds the site of a copy of the repository, to compare with the Swift site.
public protocol SiteBuilding: Sendable {
  /// The version's PATCH number the site is built with.
  var patch: Int { get }
  /// The build time the manifest names, or `nil` for none.
  var built: String? { get }

  /// Builds the copy's site.
  func build(in directory: URL) throws -> SiteOracleOutcome
}

/// Runs the Python build on a copy of the repository and reads the site it writes.
///
/// Transitional: `scripts/build.py` is the oracle while the Python build exists. Nothing here
/// writes Python; it runs `scripts/build.py` as it is.
public struct PythonSiteOracle: SiteBuilding {
  public let interpreter: String
  public let patch: Int
  public let built: String?

  public init(interpreter: String = "python3", patch: Int = 0, built: String? = nil) {
    self.interpreter = interpreter
    self.patch = patch
    self.built = built
  }

  /// Builds the copy's site with the Python build.
  public func build(in directory: URL) throws -> SiteOracleOutcome {
    let output = directory.appendingPathComponent("python-site")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [interpreter, "-I", "scripts/build.py", "--output", output.path, "--patch", String(patch)]
      + (built.map { ["--built", $0] } ?? [])
    process.currentDirectoryURL = directory

    let errors = Pipe()
    let messages = Pipe()
    process.standardError = errors
    process.standardOutput = messages

    try process.run()
    // Both pipes are read to the end before waiting, so a full pipe never stops the build.
    let errorText = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let messageText = String(decoding: messages.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()

    if errorText.contains("Traceback (most recent call last)") { return .crashed }

    if process.terminationStatus != 0 {
      return .rejected(errorText.split(separator: "\n", omittingEmptySubsequences: true).map(String.init))
    }

    guard FileManager.default.fileExists(atPath: output.appendingPathComponent("index.html").path) else { return .noSite }

    let summary = messageText.split(separator: "\n", omittingEmptySubsequences: true).last.map(String.init)
    return .site(directory: output, summary: summary)
  }
}
