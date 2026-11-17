/// Why a document is not strict JSON, and where.
public struct JSONParseError: Error, Equatable, Sendable, CustomStringConvertible {
  /// What is wrong, without the position.
  public let message: String
  /// The line of the problem, counting from 1.
  public let line: Int
  /// The column of the problem in characters, counting from 1.
  public let column: Int

  public init(message: String, line: Int, column: Int) {
    self.message = message
    self.line = line
    self.column = column
  }

  public var description: String {
    "line \(line), column \(column): \(message)"
  }
}
