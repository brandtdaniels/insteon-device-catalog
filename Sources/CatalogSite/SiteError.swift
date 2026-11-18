/// Why the page can't be rendered from its inputs.
public enum SiteError: Error, Equatable, Sendable, CustomStringConvertible {
  /// The template names a placeholder that no value was given for.
  case unknownPlaceholder(String)
  /// The template holds a `$` that starts no placeholder.
  case invalidPlaceholder
  /// A profile names a command set that is not among the command sets.
  case missingCommandSet(String)
  /// The template can't be read.
  case unreadableTemplate(String)

  public var description: String {
    switch self {
    case .unknownPlaceholder(let name): "the template names the placeholder \(name), which has no value"
    case .invalidPlaceholder: "the template has a $ that starts no placeholder"
    case .missingCommandSet(let id): "a profile names the command set \(id), which doesn't exist"
    case .unreadableTemplate(let reason): "the template can't be read: \(reason)"
    }
  }
}
