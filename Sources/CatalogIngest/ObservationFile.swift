import CatalogBuild
import CatalogJSON
import Foundation

/// What reading an observation file found.
public enum ObservationLoad: Equatable, Sendable {
  /// The file holds one JSON object.
  case loaded(JSONValue)
  /// The file can't be drafted from, for these reasons, which never quote the file.
  case rejected([String])
}

/// An observation file on disk.
public enum ObservationFile {
  /// The largest file read, in bytes.
  public static let maximumBytes = 64 * 1024

  /// Reads the file, which must be UTF-8 JSON of at most 64 KB that holds one object.
  public static func load(_ url: URL) -> ObservationLoad {
    guard let data = try? Data(contentsOf: url) else {
      return .rejected(["cannot read the file"])
    }

    guard data.count <= maximumBytes else {
      return .rejected(["the file is larger than \(maximumBytes / 1024) KB"])
    }

    let bytes = [UInt8](data)

    // Invalid UTF-8 is replaced when decoded, so the text re-encodes to different bytes.
    guard Array(String(decoding: bytes, as: UTF8.self).utf8) == bytes else {
      return .rejected(["the file is not valid JSON: it is not UTF-8 text"])
    }

    let value: JSONValue

    do {
      value = try JSONParser.parse(bytes)
    } catch {
      return .rejected(["the file is not valid JSON (line \(error.line), column \(error.column))"])
    }

    guard value.isObject else {
      return .rejected(["the file must hold one JSON object"])
    }

    return .loaded(value)
  }

  /// Eight hexadecimal digits of the file's content, which name it in output instead of its file name:
  /// a file name can be an address. `unreadable` when the file can't be read.
  public static func fingerprint(_ url: URL) -> String {
    guard let data = try? Data(contentsOf: url) else { return "unreadable" }

    return String(Checksum.sha256Hex(of: [UInt8](data)).prefix(8))
  }

  /// How output names the file: its position in the command's list and its fingerprint.
  public static func label(position: Int, of url: URL) -> String {
    "observation \(position) (\(fingerprint(url)))"
  }
}
