import CatalogJSON
import Foundation

/// An observation file as the tests build it: a fixture with fields changed.
public struct ObservationBuilder: Sendable {
  public var value: JSONValue

  public init(value: JSONValue) {
    self.value = value
  }

  /// Reads the fixture file.
  public init(fixture: URL) throws {
    value = try JSONParser.parse(Array(try Data(contentsOf: fixture)))
  }

  /// A copy with the value at the path set, added when the path's last key is new, or removed when
  /// `newValue` is `nil`.
  public func put(_ path: JSONPath, _ newValue: JSONValue?) -> ObservationBuilder {
    ObservationBuilder(value: value.putting(path, newValue))
  }

  public func device(_ key: String, _ newValue: String?) -> ObservationBuilder {
    put([.key("device"), .key(key)], newValue.map(JSONValue.string) ?? .null)
  }

  public func note(_ text: String) -> ObservationBuilder {
    put([.key("note")], .string(text))
  }

  public func detail(_ index: Int, _ text: String) -> ObservationBuilder {
    put([.key("checks"), .index(index), .key("detail")], .string(text))
  }

  public func outcome(_ index: Int, _ text: String) -> ObservationBuilder {
    put([.key("checks"), .index(index), .key("outcome")], .string(text))
  }

  public func productKey(_ text: String?) -> ObservationBuilder {
    put([.key("productKey")], text.map(JSONValue.string))
  }

  public func checks(_ named: [(String, String)]) -> ObservationBuilder {
    put(
      [.key("checks")],
      .array(named.map { name, outcome in
        .object([
          JSONMember(key: "name", value: .string(name)),
          JSONMember(key: "outcome", value: .string(outcome)),
          JSONMember(key: "detail", value: .string("x"))
        ])
      })
    )
  }

  /// The file's bytes as the writer lays the document out.
  public var bytes: [UInt8] {
    Array(((try? JSONWriter.write(value)) ?? "").utf8)
  }
}

extension JSONValue {
  /// A copy with the value at the path replaced, added at the end of an object when the last key is
  /// new, or removed when `newValue` is `nil`. A path that leaves the document changes nothing.
  func putting(_ path: JSONPath, _ newValue: JSONValue?) -> JSONValue {
    guard let step = path.first else { return newValue ?? self }
    let rest = Array(path.dropFirst())

    switch (self, step) {
    case (.object(var members), .key(let key)):
      if let position = members.firstIndex(where: { $0.key == key }) {
        if rest.isEmpty {
          if let newValue { members[position].value = newValue } else { members.remove(at: position) }
        } else {
          members[position].value = members[position].value.putting(rest, newValue)
        }
      } else if rest.isEmpty, let newValue {
        members.append(JSONMember(key: key, value: newValue))
      }
      return .object(members)
    case (.array(var elements), .index(let index)) where elements.indices.contains(index):
      if rest.isEmpty {
        if let newValue { elements[index] = newValue } else { elements.remove(at: index) }
      } else {
        elements[index] = elements[index].putting(rest, newValue)
      }
      return .array(elements)
    case (.array(var elements), .index(let index)) where index == elements.count && rest.isEmpty:
      if let newValue { elements.append(newValue) }
      return .array(elements)
    default:
      return self
    }
  }
}

extension JSONValue {
  /// The member of an object with this name.
  subscript(key: String) -> JSONValue? {
    guard case .object(let members) = self else { return nil }
    return members.first { $0.key == key }?.value
  }

  var elements: [JSONValue] {
    guard case .array(let elements) = self else { return [] }
    return elements
  }

  var string: String? {
    guard case .string(let text) = self else { return nil }
    return text
  }
}
