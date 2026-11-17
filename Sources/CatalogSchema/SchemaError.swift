/// One way a document breaks its schema: where, which keyword, and what is wrong.
public struct SchemaError: Equatable, Sendable, CustomStringConvertible {
  /// The location in the document, such as `$.capabilities[2].kind`. The root is `$`, a member
  /// whose name is not an identifier is written `['name']`, and an array element `[index]`.
  public let path: String
  /// The schema keyword that failed, such as `required` or `enum`.
  public let keyword: String
  /// What is wrong, in plain words.
  public let message: String

  public init(path: String, keyword: String, message: String) {
    self.path = path
    self.keyword = keyword
    self.message = message
  }

  /// The path and the message, as `$.a.b: message`.
  public var description: String {
    "\(path): \(message)"
  }

  /// The line a build prints for this error in the named file, as `file.json: $.a.b: message`.
  public func report(file: String) -> String {
    "\(file): \(self)"
  }
}

/// Why a schema can't be used to validate documents.
public enum SchemaLoadError: Error, Equatable, Sendable, CustomStringConvertible {
  /// The schema uses a keyword the validator does not implement. Validating with it would skip a
  /// rule the schema states.
  case unsupportedKeyword(String, at: String)
  /// A keyword has a value of the wrong kind, such as a `required` that is not a list of names.
  case malformedKeyword(String, at: String)
  /// A `$ref` names something that is not inside the schema.
  case unresolvedReference(String, at: String)

  public var description: String {
    switch self {
    case .unsupportedKeyword(let keyword, let location):
      "\(location): the keyword '\(keyword)' is not implemented"
    case .malformedKeyword(let keyword, let location):
      "\(location): the value of '\(keyword)' is not one the validator accepts"
    case .unresolvedReference(let reference, let location):
      "\(location): the reference '\(reference)' does not name a part of the schema"
    }
  }
}
