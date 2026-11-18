import Foundation

/// Runs the Python ingestion tool on every case and keeps what it did, as the goldens the Swift
/// tool is held to.
///
/// Transitional: `scripts/ingest.py` is the oracle while the Python ingestion exists.
public struct IngestCapture: Sendable {
  public let oracle: IngestOracle
  /// The repository whose `scripts/` and build the Python tool runs.
  public let repository: URL
  /// The folder with `observations/`, `catalogs/`, `cases/` and `apply/`.
  public let golden: URL

  public init(oracle: IngestOracle, repository: URL, golden: URL) {
    self.oracle = oracle
    self.repository = repository
    self.golden = golden
  }

  public var catalogs: URL { golden.appendingPathComponent("catalogs") }
  public var observations: URL { golden.appendingPathComponent("observations") }

  /// What the Python tool does for a case.
  public func python(_ ingestCase: IngestCase) throws -> IngestGolden {
    let prepared = try ingestCase.prepare(catalogs: catalogs, repository: repository)
    let run = try oracle.run(prepared.arguments, in: prepared.root)

    return prepared.golden(after: run)
  }

  /// What the Python tool does for an apply case, on a full copy of the repository so its build runs.
  public func python(_ applyCase: ApplyCase) throws -> IngestGolden {
    guard let prepared = try applyCase.prepare(catalogs: catalogs, repository: repository, drafted: Self.reader(golden)) else {
      return IngestGolden()
    }

    var run = try oracle.run(["apply", prepared.report.path], in: prepared.root)

    if prepared.appliesTwice {
      try prepared.commitChanges()
      run = try oracle.run(["apply", prepared.report.path], in: prepared.root)
    }

    return try prepared.golden(after: run)
  }

  /// Reads the report the golden of a draft case holds.
  public static func reader(_ golden: URL) -> (String) throws -> [UInt8] {
    { name in
      let bytes = Array(try Data(contentsOf: golden.appendingPathComponent("cases/\(name).golden")))
      guard let report = IngestGolden.parse(bytes)?.parts.first(where: { $0.name == "report.json" }) else {
        throw SweepError.copyFailed("\(name): the golden holds no report")
      }

      return report.bytes
    }
  }

  /// Writes the golden of every case; returns how many it wrote.
  public func write(book: IngestCaseBook) throws -> Int {
    var written = 0

    for ingestCase in try book.cases() {
      try write(try python(ingestCase), to: "cases/\(ingestCase.name).golden")
      written += 1
    }

    for ingestCase in try book.knownDifferenceCases() {
      try write(try python(ingestCase), to: "known-differences/\(ingestCase.name).golden")
      written += 1
    }

    for applyCase in ApplyCaseBook.cases {
      try write(try python(applyCase), to: "apply/\(applyCase.name).golden")
      written += 1
    }

    return written
  }

  private func write(_ result: IngestGolden, to path: String) throws {
    let url = golden.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(result.serialized()).write(to: url)
  }
}
