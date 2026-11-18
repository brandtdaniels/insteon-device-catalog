import CatalogBuild
import Foundation
import Testing

/// Transitional: the Swift rule and `scripts/check_version.py` give the same exit status and
/// message for the same history. The comparison with the script ends when the script is removed.
struct VersionCheckEquivalenceTests {
  /// What a run of the check reports: its exit status and what it wrote to standard error.
  struct Outcome: Equatable, CustomStringConvertible {
    var status: Int32
    var message: String
    var description: String { "status \(status), message \(message.debugDescription)" }
  }

  /// A scripted history. `expected` is what the script reports for it, used in place of the
  /// script when no Python interpreter is installed. `comparesMessage` is false when the script
  /// ends in a traceback whose text isn't part of the contract.
  struct Scenario: Sendable {
    var name: String
    var expected: Outcome
    var comparesMessage = true
    var build: @Sendable (TemporaryRepository) throws -> String
  }

  static let schema = "schema/device-profile.json"

  /// A base commit holding a version and a schema, then `change` applied and committed. Returns the base.
  static func history(
    base version: String?, change: @escaping @Sendable (TemporaryRepository) throws -> Void
  ) -> @Sendable (TemporaryRepository) throws -> String {
    { repository in
      if let version { try repository.write("VERSION", version) }
      try repository.write(schema, "{}\n")
      try repository.write("devices/a.json", "{}\n")
      let base = try repository.commit("base")
      try change(repository)
      try repository.commit("change")
      return base
    }
  }

  static let ok = Outcome(status: 0, message: "")
  static let noBump = Outcome(status: 1, message: "The schemas changed, so VERSION needs a higher MAJOR.MINOR.\n")
  static let wentDown = Outcome(status: 1, message: "VERSION went down.\n")

  static let scenarios: [Scenario] = [
    Scenario(name: "no schema change", expected: ok, build: history(base: "0.10\n") {
      try $0.write("devices/a.json", #"{"a": 1}"#)
    }),
    Scenario(name: "schema change with a MINOR bump", expected: ok, build: history(base: "0.10\n") {
      try $0.write(schema, #"{"a": 1}"#)
      try $0.write("VERSION", "0.11\n")
    }),
    Scenario(name: "schema change with a MAJOR bump", expected: ok, build: history(base: "0.10\n") {
      try $0.write(schema, #"{"a": 1}"#)
      try $0.write("VERSION", "1.0\n")
    }),
    Scenario(name: "schema change without a bump", expected: noBump, build: history(base: "0.10\n") {
      try $0.write(schema, #"{"a": 1}"#)
    }),
    Scenario(name: "added schema file without a bump", expected: noBump, build: history(base: "0.10\n") {
      try $0.write("schema/new.json", "{}\n")
    }),
    Scenario(name: "deleted schema file without a bump", expected: noBump, build: history(base: "0.10\n") {
      try $0.remove(schema)
    }),
    Scenario(name: "schema file renamed out of schema without a bump", expected: noBump, build: history(base: "0.10\n") {
      try $0.move(schema, to: "documents/device-profile.json")
    }),
    Scenario(name: "bump without a schema change", expected: ok, build: history(base: "0.10\n") {
      try $0.write("VERSION", "0.11\n")
    }),
    Scenario(name: "path outside schema", expected: ok, build: history(base: "0.10\n") {
      try $0.write("schemas/other.json", "{}\n")
      try $0.write("schema.json", "{}\n")
    }),
    Scenario(name: "MINOR compared as a number", expected: ok, build: history(base: "0.9\n") {
      try $0.write(schema, #"{"a": 1}"#)
      try $0.write("VERSION", "0.10\n")
    }),
    Scenario(name: "version went down", expected: wentDown, build: history(base: "0.10\n") {
      try $0.write("VERSION", "0.9\n")
    }),
    Scenario(name: "version went down with a schema change", expected: wentDown, build: history(base: "1.0\n") {
      try $0.write(schema, #"{"a": 1}"#)
      try $0.write("VERSION", "0.20\n")
    }),
    Scenario(
      name: "malformed VERSION",
      expected: Outcome(status: 1, message: "VERSION must be MAJOR.MINOR, not '1.2.3'\n"),
      build: history(base: "0.10\n") { try $0.write("VERSION", "1.2.3\n") }),
    Scenario(
      name: "malformed VERSION with a quote",
      expected: Outcome(status: 1, message: "VERSION must be MAJOR.MINOR, not \"it's\"\n"),
      build: history(base: "0.10\n") { try $0.write("VERSION", "it's\n") }),
    Scenario(
      name: "malformed base VERSION",
      expected: Outcome(status: 1, message: "VERSION must be MAJOR.MINOR, not 'latest'\n"),
      build: history(base: "latest\n") { try $0.write("devices/a.json", #"{"a": 1}"#) }),
    Scenario(name: "base without VERSION and a schema change", expected: ok, build: history(base: nil) {
      try $0.write(schema, #"{"a": 1}"#)
      try $0.write("VERSION", "0.1\n")
    }),
    Scenario(
      name: "VERSION missing now", expected: Outcome(status: 1, message: ""), comparesMessage: false,
      build: history(base: "0.10\n") { try $0.remove("VERSION") })
  ]

  /// The script's outcome, or `nil` when there is no Python interpreter to run it.
  static func script(base: String, in repository: TemporaryRepository) throws -> Outcome? {
    guard let script = scriptURL() else { return nil }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", "-I", script.path, base]
    process.currentDirectoryURL = repository.url
    let errors = Pipe()
    process.standardError = errors
    process.standardOutput = FileHandle.nullDevice
    do { try process.run() } catch { return nil }
    let data = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return Outcome(status: process.terminationStatus, message: String(decoding: data, as: UTF8.self))
  }

  /// `scripts/check_version.py`, when it exists and a Python interpreter answers.
  static func scriptURL() -> URL? {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    let script = root.appendingPathComponent("scripts/check_version.py")
    guard FileManager.default.fileExists(atPath: script.path), interpreterAnswers else { return nil }
    return script
  }

  static let interpreterAnswers: Bool = {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", "--version"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return false }
    process.waitUntilExit()
    return process.terminationStatus == 0
  }()

  /// The Swift rule's outcome for the repository, in the script's terms.
  static func swift(base: String, in repository: TemporaryRepository) -> Outcome {
    do {
      try VersionCheck(git: ProcessGit(root: repository.url)).verify(base: base, root: repository.url)
      return ok
    } catch {
      return Outcome(status: 1, message: error.description + "\n")
    }
  }

  @Test(arguments: scenarios.map(\.name))
  func givesTheScriptsAnswer(name: String) throws {
    let scenario = try #require(Self.scenarios.first { $0.name == name })
    let repository = try TemporaryRepository()
    let base = try scenario.build(repository)

    var actual = Self.swift(base: base, in: repository)
    var expected = try Self.script(base: base, in: repository) ?? scenario.expected
    if !scenario.comparesMessage {
      actual.message = ""
      expected.message = ""
    }
    #expect(actual == expected)
    if scenario.comparesMessage { #expect(actual == scenario.expected) }
  }
}
