import Foundation

/// A golden file could not be read.
public struct GoldenError: Error, CustomStringConvertible {
  public let description: String
}

public enum GoldenReports {
  /// Reads the report the golden of a draft case holds, by the case's name.
  public static func reader(_ golden: URL) -> (String) throws -> [UInt8] {
    { name in
      let bytes = Array(try Data(contentsOf: golden.appendingPathComponent("cases/\(name).golden")))
      guard let report = IngestGolden.parse(bytes)?.parts.first(where: { $0.name == "report.json" }) else {
        throw GoldenError(description: "\(name): the golden holds no report")
      }

      return report.bytes
    }
  }
}
