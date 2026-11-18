import Foundation

/// One thing a page holds, in the order it appears.
enum HTMLEvent: Equatable {
  /// A start tag, with its attributes in order. A name with no value reads as an empty value.
  case start(String, [(String, String)])
  case end(String)
  case text(String)

  static func == (left: HTMLEvent, right: HTMLEvent) -> Bool {
    switch (left, right) {
    case (.start(let a, let x), .start(let b, let y)): a == b && x.map { "\($0)=\($1)" } == y.map { "\($0)=\($1)" }
    case (.end(let a), .end(let b)): a == b
    case (.text(let a), .text(let b)): a == b
    default: false
    }
  }
}

/// Reads the page's own markup into events, the way a forgiving HTML parser does for it: tag and
/// attribute names in lower case, character references decoded in text and attribute values, the
/// contents of `script` and `style` kept as raw text, and void elements without an end tag.
enum HTMLScanner {
  static func events(in html: String) -> [HTMLEvent] {
    let characters = Array(html.unicodeScalars)
    var events: [HTMLEvent] = []
    var text = ""
    var index = 0

    func flush() {
      if !text.isEmpty { events.append(.text(decoded(text))) }
      text = ""
    }

    while index < characters.count {
      let character = characters[index]

      guard character == "<", index + 1 < characters.count else {
        text.unicodeScalars.append(character)
        index += 1
        continue
      }

      let next = characters[index + 1]

      if next == "!" {
        flush()
        index = skip(past: ">", from: index, in: characters)
      } else if next == "/" {
        flush()
        var name = ""
        index += 2
        while index < characters.count, characters[index] != ">" {
          name.unicodeScalars.append(characters[index])
          index += 1
        }
        index += 1
        events.append(.end(name.trimmingCharacters(in: .whitespaces).lowercased()))
      } else if next.properties.isAlphabetic {
        flush()
        let (name, attributes, after) = startTag(at: index + 1, in: characters)
        index = after
        events.append(.start(name, attributes))

        if name == "script" || name == "style" {
          var raw = ""
          let closing = Array("</\(name)".unicodeScalars)
          while index < characters.count, !startsWith(closing, at: index, in: characters) {
            raw.unicodeScalars.append(characters[index])
            index += 1
          }
          if !raw.isEmpty { events.append(.text(raw)) }
        }
      } else {
        text.unicodeScalars.append(character)
        index += 1
      }
    }

    flush()
    return events
  }

  private static func startTag(at start: Int, in characters: [Unicode.Scalar]) -> (String, [(String, String)], Int) {
    var index = start
    var name = ""

    while index < characters.count, !isSpace(characters[index]), characters[index] != ">", characters[index] != "/" {
      name.unicodeScalars.append(characters[index])
      index += 1
    }

    var attributes: [(String, String)] = []

    while index < characters.count, characters[index] != ">" {
      if isSpace(characters[index]) || characters[index] == "/" {
        index += 1
        continue
      }

      var key = ""
      while index < characters.count, !isSpace(characters[index]), characters[index] != "=", characters[index] != ">", characters[index] != "/" {
        key.unicodeScalars.append(characters[index])
        index += 1
      }

      var value = ""
      if index < characters.count, characters[index] == "=" {
        index += 1
        if index < characters.count, characters[index] == "\"" || characters[index] == "'" {
          let quote = characters[index]
          index += 1
          while index < characters.count, characters[index] != quote {
            value.unicodeScalars.append(characters[index])
            index += 1
          }
          index += 1
        } else {
          while index < characters.count, !isSpace(characters[index]), characters[index] != ">" {
            value.unicodeScalars.append(characters[index])
            index += 1
          }
        }
      }

      attributes.append((key.lowercased(), decoded(value)))
    }

    return (name.lowercased(), attributes, index + 1)
  }

  private static func isSpace(_ scalar: Unicode.Scalar) -> Bool {
    scalar == " " || scalar == "\n" || scalar == "\t" || scalar == "\r"
  }

  private static func startsWith(_ prefix: [Unicode.Scalar], at index: Int, in characters: [Unicode.Scalar]) -> Bool {
    guard index + prefix.count <= characters.count else { return false }
    return zip(prefix, characters[index...]).allSatisfy { String($0).lowercased() == String($1).lowercased() }
  }

  private static func skip(past terminator: Unicode.Scalar, from index: Int, in characters: [Unicode.Scalar]) -> Int {
    var position = index
    while position < characters.count, characters[position] != terminator { position += 1 }
    return position + 1
  }

  /// The text with `&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;` and numeric references decoded.
  static func decoded(_ text: String) -> String {
    guard text.contains("&") else { return text }
    var result = ""
    var rest = Substring(text)

    while let ampersand = rest.firstIndex(of: "&") {
      result += rest[..<ampersand]
      rest = rest[ampersand...]

      guard let semicolon = rest.firstIndex(of: ";"), rest.distance(from: rest.startIndex, to: semicolon) <= 10 else {
        result += "&"
        rest = rest.dropFirst()
        continue
      }

      let name = String(rest[rest.index(after: rest.startIndex)..<semicolon])
      let replacement: String?

      switch name {
      case "amp": replacement = "&"
      case "lt": replacement = "<"
      case "gt": replacement = ">"
      case "quot": replacement = "\""
      case "apos": replacement = "'"
      default:
        if name.hasPrefix("#x") || name.hasPrefix("#X"), let value = UInt32(name.dropFirst(2), radix: 16), let scalar = Unicode.Scalar(value) {
          replacement = String(Character(scalar))
        } else if name.hasPrefix("#"), let value = UInt32(name.dropFirst()), let scalar = Unicode.Scalar(value) {
          replacement = String(Character(scalar))
        } else {
          replacement = nil
        }
      }

      if let replacement {
        result += replacement
        rest = rest[rest.index(after: semicolon)...]
      } else {
        result += "&"
        rest = rest.dropFirst()
      }
    }

    return result + rest
  }
}
