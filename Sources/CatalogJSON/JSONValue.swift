/// A JSON document whose objects keep the order of their members.
public enum JSONValue: Equatable, Sendable {
  case null
  case bool(Bool)
  case int(Int)
  case double(Double)
  case string(String)
  case array([JSONValue])
  case object([JSONMember])
}

/// One key and value of a JSON object.
public struct JSONMember: Equatable, Sendable {
  public var key: String
  public var value: JSONValue

  public init(key: String, value: JSONValue) {
    self.key = key
    self.value = value
  }
}
