import CatalogRules

/// A kind of private data a text can look like.
public enum PrivateShape: Equatable, Sendable, CustomStringConvertible {
  case address
  case mac
  case ip
  case url
  case email
  case path
  case serial

  /// What a rejection calls the shape, such as "an Insteon address".
  public var description: String {
    switch self {
    case .address: "an Insteon address"
    case .mac: "a MAC address"
    case .ip: "an IP address"
    case .url: "a URL or host name"
    case .email: "an email address"
    case .path: "a file path"
    case .serial: "a serial number"
    }
  }
}

/// Finds what looks like an address, a host, an account or a path in free text, and says which kind
/// and never shows it.
public enum PrivacyScan {
  private static let before = #"(?<![0-9A-Za-z])"#
  private static let after = #"(?![0-9A-Za-z])"#

  private static let dottedAddress = Pattern(before + #"[0-9A-Fa-f]{2}\.[0-9A-Fa-f]{2}\.[0-9A-Fa-f]{2}"# + after)
  /// Six hexadecimal digits with a digit among them, or all upper case: an address, not a word such as "decade".
  private static let bareAddress = Pattern(before + #"(?=[0-9A-Fa-f]*[0-9])[0-9A-Fa-f]{6}"# + after)
  private static let bareUpperAddress = Pattern(before + #"[0-9A-F]{6}"# + after)
  private static let macAddress = Pattern(before + #"[0-9A-Fa-f]{2}([:\-])(?:[0-9A-Fa-f]{2}\1){4}[0-9A-Fa-f]{2}"# + after)
  private static let ipv4Address = Pattern(#"(?<![0-9.])(?:\d{1,3}\.){3}\d{1,3}(?![0-9])"#)
  private static let ipv6Address = Pattern(
    #"(?<![0-9A-Za-z:])(?:(?:[0-9A-Fa-f]{1,4}:){3,7}[0-9A-Fa-f]{1,4}|(?=[0-9A-Fa-f:]*::)[0-9A-Fa-f:]{3,39})(?![0-9A-Za-z:])"#
  )
  private static let urlOrHost = Pattern(
    #"(?i)(?:[a-z][a-z0-9+.\-]*://|\bwww\.|\b[a-z0-9\-]+(?:\.[a-z0-9\-]+)*\.(?:com|net|org|io|local|lan|home|edu|gov|us|uk|dev|app)\b)"#
  )
  private static let emailAddress = Pattern(#"[\w.+\-]+@[\w\-]+(?:\.[\w\-]+)+"#)
  private static let filePath = Pattern(#"(?i)(?:^|[\#(pythonWhitespaceClass)"'(=])(?:/[\w.\-]+/|~/|[a-z]:\\|\\\\)"#)
  private static let serialNumber = Pattern(before + #"(?!0x)(?=[A-Za-z0-9]*\d)[A-Za-z0-9]{8,}"# + after)

  /// The kinds of private data the text looks like, in a fixed order, each once.
  ///
  /// - Parameters:
  ///   - models: Model numbers that may appear in the text and are not addresses.
  ///   - serial: Whether to look for a serial number too.
  public static func shapes(in text: String, models: Set<String> = [], serial: Bool = false) -> [PrivateShape] {
    var shapes: [PrivateShape] = []
    let bare = bareAddress.allMatches(in: text) + bareUpperAddress.allMatches(in: text)

    if dottedAddress.firstMatch(in: text) != nil || bare.contains(where: { !models.contains($0) }) {
      shapes.append(.address)
    }

    let mac = macAddress.firstMatch(in: text) != nil

    if mac {
      shapes.append(.mac)
    }

    if ipv4Address.firstMatch(in: text) != nil || (!mac && ipv6Address.firstMatch(in: text) != nil) {
      shapes.append(.ip)
    }

    if urlOrHost.firstMatch(in: text) != nil {
      shapes.append(.url)
    }

    if emailAddress.firstMatch(in: text) != nil {
      shapes.append(.email)
    }

    if filePath.firstMatch(in: text) != nil {
      shapes.append(.path)
    }

    if serial, serialNumber.firstMatch(in: text) != nil {
      shapes.append(.serial)
    }

    return shapes
  }
}
