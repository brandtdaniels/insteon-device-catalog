/// The landing page's template: text with `$name` placeholders, filled the way Python's
/// `string.Template.substitute` fills them.
public struct Template: Sendable {
  private enum Piece: Sendable {
    case text(String)
    case placeholder(String)
  }

  private let pieces: [Piece]
  private let failure: SiteError?

  /// A template from its text. A `$` that starts no placeholder is reported when the template is
  /// filled.
  public init(_ text: String) {
    var pieces: [Piece] = []
    var literal = ""
    var failure: SiteError?
    let scalars = Array(text.unicodeScalars)
    var index = 0

    func isStart(_ scalar: Unicode.Scalar) -> Bool {
      scalar == "_" || ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
    }

    func isPart(_ scalar: Unicode.Scalar) -> Bool {
      isStart(scalar) || ("0"..."9").contains(scalar)
    }

    func identifier(from start: Int) -> (String, Int)? {
      guard start < scalars.count, isStart(scalars[start]) else { return nil }
      var end = start
      while end < scalars.count, isPart(scalars[end]) { end += 1 }
      return (String(String.UnicodeScalarView(scalars[start..<end])), end)
    }

    while index < scalars.count {
      let scalar = scalars[index]

      guard scalar == "$" else {
        literal.unicodeScalars.append(scalar)
        index += 1
        continue
      }

      let next = index + 1

      if next < scalars.count, scalars[next] == "$" {
        literal += "$"
        index = next + 1
      } else if let (name, end) = identifier(from: next) {
        pieces.append(.text(literal))
        literal = ""
        pieces.append(.placeholder(name))
        index = end
      } else if next < scalars.count, scalars[next] == "{", let (name, end) = identifier(from: next + 1), end < scalars.count, scalars[end] == "}" {
        pieces.append(.text(literal))
        literal = ""
        pieces.append(.placeholder(name))
        index = end + 1
      } else {
        failure = failure ?? .invalidPlaceholder
        index = next
      }
    }

    pieces.append(.text(literal))
    self.pieces = pieces
    self.failure = failure
  }

  /// The placeholder names, each once, in the order they first appear.
  public var placeholders: [String] {
    var seen: [String] = []
    for case .placeholder(let name) in pieces where !seen.contains(name) { seen.append(name) }
    return seen
  }

  /// The text with each placeholder replaced by its value. A value is not scanned again.
  public func substitute(_ values: [String: String]) throws(SiteError) -> String {
    if let failure { throw failure }
    var result = ""

    for piece in pieces {
      switch piece {
      case .text(let text):
        result += text
      case .placeholder(let name):
        guard let value = values[name] else { throw .unknownPlaceholder(name) }
        result += value
      }
    }

    return result
  }
}
