import CatalogSweep
import Foundation
import Testing

/// How two site directories are compared: file names first, then bytes.
struct SiteComparisonTests {
  /// Two directories holding the given files, removed when the test ends.
  struct Pair {
    let swift: URL
    let python: URL

    init(swift: [String: String], python: [String: String]) throws {
      let base = FileManager.default.temporaryDirectory.appendingPathComponent("catalog-site-comparison-" + UUID().uuidString)
      self.swift = base.appendingPathComponent("swift")
      self.python = base.appendingPathComponent("python")
      try Self.write(swift, to: self.swift)
      try Self.write(python, to: self.python)
    }

    func remove() {
      try? FileManager.default.removeItem(at: swift.deletingLastPathComponent())
    }

    private static func write(_ files: [String: String], to directory: URL) throws {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

      for (path, text) in files {
        let file = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
      }
    }
  }

  static func difference(swift: [String: String], python: [String: String]) throws -> SiteDifference? {
    let pair = try Pair(swift: swift, python: python)
    defer { pair.remove() }
    return try SiteComparison.firstDifference(swift: pair.swift, python: pair.python)
  }

  @Test func sameFilesWithTheSameBytesDoNotDiffer() throws {
    let files = ["index.html": "<p>a</p>", "v0/catalog.json": "{}\n"]

    #expect(try Self.difference(swift: files, python: files) == nil)
  }

  @Test func twoEmptyDirectoriesDoNotDiffer() throws {
    #expect(try Self.difference(swift: [:], python: [:]) == nil)
  }

  @Test func aFileOnlyOnTheSwiftSideIsNamed() throws {
    let difference = try Self.difference(swift: ["a": "1", "v0/b": "2"], python: ["a": "1"])

    #expect(difference == .onlyInSwift("v0/b"))
  }

  @Test func aFileOnlyOnThePythonSideIsNamed() throws {
    let difference = try Self.difference(swift: ["a": "1"], python: ["a": "1", "z": "2"])

    #expect(difference == .onlyInPython("z"))
  }

  @Test func aFileWithDifferentBytesNamesTheFileAndTheOffsetOfTheFirstDifferingByte() throws {
    let difference = try Self.difference(swift: ["v0/catalog.json": "abcdef"], python: ["v0/catalog.json": "abcXef"])

    guard case .bytes(let file, let bytes)? = difference else {
      Issue.record("expected a byte difference, got \(String(describing: difference))")
      return
    }

    #expect(file == "v0/catalog.json")
    #expect(bytes.offset == 3)
  }

  @Test func aFileThatIsAPrefixOfTheOtherDiffersAtTheShorterLength() throws {
    let difference = try Self.difference(swift: ["a": "abc"], python: ["a": "abcd"])

    guard case .bytes(_, let bytes)? = difference else {
      Issue.record("expected a byte difference, got \(String(describing: difference))")
      return
    }

    #expect(bytes.offset == 3)
  }

  @Test func theFirstDifferenceIsTheFirstFileInPathOrder() throws {
    let difference = try Self.difference(
      swift: ["b": "1", "a": "1", "c": "1"], python: ["b": "2", "a": "2", "c": "2"]
    )

    guard case .bytes(let file, _)? = difference else {
      Issue.record("expected a byte difference, got \(String(describing: difference))")
      return
    }

    #expect(file == "a")
  }

  @Test func aMissingFileComesBeforeAByteDifferenceInALaterFile() throws {
    let difference = try Self.difference(swift: ["a": "1", "z": "1"], python: ["a": "1", "b": "1", "z": "2"])

    #expect(difference == .onlyInPython("b"))
  }

  @Test func aDifferenceDescribesTheFileTheOffsetAndBothSides() throws {
    let difference = try #require(try Self.difference(swift: ["f": "abcdef"], python: ["f": "abcXef"]))

    #expect(difference.description.contains("f: first difference at byte 3"))
    #expect(difference.description.contains("Swift:"))
    #expect(difference.description.contains("Python:"))
    #expect(try #require(try Self.difference(swift: ["f": "1"], python: [:])).description == "f is only in the Swift site")
    #expect(try #require(try Self.difference(swift: [:], python: ["f": "1"])).description == "f is only in the Python site")
  }
}
