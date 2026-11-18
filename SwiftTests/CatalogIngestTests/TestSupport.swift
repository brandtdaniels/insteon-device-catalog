import CatalogJSON
import Foundation

/// Where the tests find the frozen files and the repository they sit in.
enum Fixtures {
  static let golden = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Golden")
  static let observations = golden.appendingPathComponent("observations")
  static let catalogs = golden.appendingPathComponent("catalogs")
  static let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

  static func bench(_ name: String) -> JSONValue {
    (try? JSONParser.parse(Array(Data(contentsOf: observations.appendingPathComponent(name))))) ?? .null
  }
}

/// A JSON document written as text.
func json(_ text: String) -> JSONValue {
  do {
    return try JSONParser.parse(text)
  } catch {
    preconditionFailure("not JSON: \(text)")
  }
}

extension JSONValue {
  subscript(key: String) -> JSONValue? {
    guard case .object(let members) = self else { return nil }
    return members.first { $0.key == key }?.value
  }

  subscript(position: Int) -> JSONValue? {
    guard case .array(let elements) = self, elements.indices.contains(position) else { return nil }
    return elements[position]
  }

  var string: String? {
    guard case .string(let text) = self else { return nil }
    return text
  }

  var elements: [JSONValue] {
    guard case .array(let elements) = self else { return [] }
    return elements
  }

  var keys: [String] {
    guard case .object(let members) = self else { return [] }
    return members.map(\.key)
  }

  /// A copy with the value at the path set, added when an object lacks the last key, or removed when
  /// `value` is `nil`. A path step that is a number indexes an array.
  func setting(_ path: [String], to value: JSONValue?) -> JSONValue {
    guard let step = path.first else { return value ?? self }
    let rest = Array(path.dropFirst())

    switch self {
    case .object(var members):
      if let position = members.firstIndex(where: { $0.key == step }) {
        if rest.isEmpty, value == nil {
          members.remove(at: position)
        } else {
          members[position].value = members[position].value.setting(rest, to: value)
        }
      } else if rest.isEmpty, let value {
        members.append(JSONMember(key: step, value: value))
      }
      return .object(members)
    case .array(var elements):
      guard let position = Int(step) else { return self }
      if position == elements.count, rest.isEmpty, let value {
        elements.append(value)
      } else if !elements.indices.contains(position) {
        return self
      } else if rest.isEmpty, value == nil {
        elements.remove(at: position)
      } else {
        elements[position] = elements[position].setting(rest, to: value)
      }
      return .array(elements)
    default:
      return self
    }
  }

  func setting(_ key: String, to value: JSONValue?) -> JSONValue {
    setting([key], to: value)
  }

  /// The document as the writer lays it out.
  var text: String {
    (try? JSONWriter.write(self)) ?? ""
  }
}

/// A scratch folder that is removed when the test ends.
final class Scratch {
  let url: URL

  init() throws {
    url = FileManager.default.temporaryDirectory.appendingPathComponent("catalog-ingest-test-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  deinit {
    try? FileManager.default.removeItem(at: url)
  }

  @discardableResult
  func write(_ name: String, _ text: String) throws -> URL {
    let file = url.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: file)

    return file
  }

  @discardableResult
  func write(_ name: String, json value: JSONValue) throws -> URL {
    try write(name, value.text)
  }

  func read(_ name: String) throws -> String {
    String(decoding: try Data(contentsOf: url.appendingPathComponent(name)), as: UTF8.self)
  }
}

/// Runs git in a folder with a fixed identity and no access to the user's configuration.
enum Git {
  @discardableResult
  static func run(_ directory: URL, _ arguments: String...) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "-c", "commit.gpgsign=false", "-C", directory.path] + arguments
    var environment = ProcessInfo.processInfo.environment
    for (key, value) in [
      "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
      "GIT_AUTHOR_NAME": "Catalog Test", "GIT_AUTHOR_EMAIL": "catalog-test@example.invalid",
      "GIT_COMMITTER_NAME": "Catalog Test", "GIT_COMMITTER_EMAIL": "catalog-test@example.invalid"
    ] {
      environment[key] = value
    }
    process.environment = environment
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    return String(decoding: data, as: UTF8.self)
  }

  static func commitAll(_ directory: URL, _ message: String = "start") throws {
    try run(directory, "add", "--all")
    try run(directory, "commit", "--quiet", "--allow-empty", "--message", message)
  }
}
