import CatalogBuild
import CatalogJSON
import CatalogRules
import CatalogSchema
import Foundation
import Testing

/// One step down a JSON document: an object member, an array element by position, or the
/// element of an array whose `name` is given.
enum Step: ExpressibleByStringLiteral {
  case key(String)
  case index(Int)
  case named(String)

  init(stringLiteral value: String) {
    self = .key(value)
  }
}

extension JSONValue {
  /// A copy with the value at `steps` replaced, or removed when `replacement` is `nil`. An object
  /// member that isn't there is added at the end.
  func changing(_ steps: [Step], to replacement: JSONValue?) -> JSONValue {
    guard let step = steps.first else { return replacement ?? self }
    let rest = Array(steps.dropFirst())

    switch (self, step) {
    case (.object(var members), .key(let key)):
      if let position = members.firstIndex(where: { $0.key == key }) {
        if rest.isEmpty, replacement == nil {
          members.remove(at: position)
        } else {
          members[position].value = members[position].value.changing(rest, to: replacement)
        }
      } else if rest.isEmpty, let replacement {
        members.append(JSONMember(key: key, value: replacement))
      }
      return .object(members)
    case (.array(var elements), .index(let index)):
      elements[index] = elements[index].changing(rest, to: replacement)
      return .array(elements)
    case (.array(var elements), .named(let name)):
      guard let index = elements.firstIndex(where: { $0.member("name") == .string(name) }) else { return self }
      elements[index] = elements[index].changing(rest, to: replacement)
      return .array(elements)
    default:
      return self
    }
  }

  /// A copy with the value at `steps` replaced by the JSON text.
  func setting(_ steps: [Step], _ json: String) throws -> JSONValue {
    changing(steps, to: try JSONParser.parse(json))
  }

  /// A copy with the value at `steps` removed.
  func removing(_ steps: [Step]) -> JSONValue {
    changing(steps, to: nil)
  }

  /// A copy with the JSON objects in `json`, a list, added to the end of the array at `key`.
  func appending(_ json: String, to key: String) throws -> JSONValue {
    let additions = try JSONParser.parse(json)
    let existing = member(key) ?? .array([])
    guard case .array(let elements) = existing, case .array(let new) = additions else { return self }
    return changing([.key(key)], to: .array(elements + new))
  }

  func member(_ key: String) -> JSONValue? {
    guard case .object(let members) = self else { return nil }
    return members.first { $0.key == key }?.value
  }

  /// A copy with `key` of the flag, standard or extended command called `name` set to the JSON text.
  func settingCommand(_ name: String, _ key: String, _ json: String) throws -> JSONValue {
    try setting(commandSteps(name) + [.key(key)], json)
  }

  /// A copy without `key` of the flag, standard or extended command called `name`.
  func removingFromCommand(_ name: String, _ key: String) -> JSONValue {
    removing(commandSteps(name) + [.key(key)])
  }

  /// The flag, standard or extended command called `name`.
  func command(_ name: String) -> JSONValue? {
    let steps = commandSteps(name)
    guard steps.count == 2, case .key(let key) = steps[0] else { return nil }
    return member(key)?.elements.first { $0.member("name") == .string(name) }
  }

  /// The steps to the flag, standard or extended command called `name`.
  func commandSteps(_ name: String) -> [Step] {
    for key in ["flagCommands", "standardCommands", "extendedCommands"] {
      if case .array(let elements)? = member(key), elements.contains(where: { $0.member("name") == .string(name) }) {
        return [.key(key), .named(name)]
      }
    }
    return []
  }
}

/// The catalog's own data, to change in a test.
enum Fixtures {
  static let root = RepositoryRoot(url: CatalogRepository.url)

  static func commandSet(_ id: String) throws -> JSONValue {
    try #require(try root.commandSetFiles().first { $0.stem == id }).value
  }

  static func profile(_ model: String) throws -> JSONValue {
    try #require(try root.deviceFiles().first { $0.stem == model }).value
  }

  /// The messages of the rules for a command set. The command set must pass its schema, as the
  /// build only runs the rules on a command set that does.
  static func problems(_ commandSet: JSONValue) throws -> [String] {
    let validator = try SchemaValidator(schema: root.schema(.commandSet))
    #expect(validator.errors(in: commandSet) == [])
    return CommandSetRules.problems(in: commandSet)
  }

  /// An invented command set with serial commands.
  static func serialCommandSet() throws -> JSONValue {
    try JSONParser.parse(#"""
    {"id": "invented", "name": "Invented", "description": "An invented modem.", "sources": ["An invented guide"],
     "serialCommands": [
       {"name": "readInfo", "description": "Asks for the identity.", "effect": "readOnly", "idempotent": true, "number": "0x60",
        "reply": [{"name": "identity", "description": "The identity.", "bytes": [1, 2, 3]}]},
       {"name": "startThing", "description": "Starts a thing.", "effect": "link", "idempotent": false, "number": "0x64",
        "fixed": [{"position": 1, "value": "0x01"}], "parameters": [{"name": "group", "description": "The group.", "byte": 2}]},
       {"name": "deleteThing", "description": "Deletes a thing.", "effect": "destructive", "idempotent": true, "number": "0x64",
        "fixed": [{"position": 1, "value": "0xFF"}], "parameters": [{"name": "group", "description": "The group.", "byte": 2}]}
     ]}
    """#)
  }
}

/// The repository this test target belongs to.
enum CatalogRepository {
  static let url = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

extension JSONValue {
  subscript(key: String) -> JSONValue? {
    member(key)
  }

  /// A copy with the JSON list added to the end of the array at `steps`.
  func appending(to steps: [Step], _ json: String) throws -> JSONValue {
    guard case .array(let new) = try JSONParser.parse(json) else { return self }
    var target: JSONValue = self
    for step in steps {
      switch (target, step) {
      case (.object, .key(let key)): target = target.member(key) ?? .null
      case (.array(let elements), .named(let name)): target = elements.first { $0.member("name") == .string(name) } ?? .null
      default: break
      }
    }
    return changing(steps, to: .array(target.elements + new))
  }

  var elements: [JSONValue] {
    guard case .array(let elements) = self else { return [] }
    return elements
  }
}
