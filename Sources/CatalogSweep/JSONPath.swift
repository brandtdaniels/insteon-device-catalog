import CatalogJSON

/// One step down a JSON document.
public enum PathStep: Equatable, Sendable, CustomStringConvertible {
  case key(String)
  case index(Int)

  public var description: String {
    switch self {
    case .key(let key): ".\(key)"
    case .index(let index): "[\(index)]"
    }
  }
}

/// A place in a JSON document.
public typealias JSONPath = [PathStep]

extension JSONValue {
  /// The value at the path, or `nil` when the document has nothing there.
  func value(at path: JSONPath) -> JSONValue? {
    guard let step = path.first else { return self }
    let rest = Array(path.dropFirst())

    switch (self, step) {
    case (.object(let members), .key(let key)):
      return members.first { $0.key == key }?.value.value(at: rest)
    case (.array(let elements), .index(let index)) where elements.indices.contains(index):
      return elements[index].value(at: rest)
    default:
      return nil
    }
  }

  /// A copy with the value at the path passed through `change`; `nil` from `change` removes an
  /// object member or an array element.
  func replacing(at path: JSONPath, _ change: (JSONValue) -> JSONValue?) -> JSONValue {
    guard let step = path.first else { return change(self) ?? self }
    let rest = Array(path.dropFirst())

    switch (self, step) {
    case (.object(var members), .key(let key)):
      guard let position = members.firstIndex(where: { $0.key == key }) else { return self }
      if rest.isEmpty {
        if let changed = change(members[position].value) {
          members[position].value = changed
        } else {
          members.remove(at: position)
        }
      } else {
        members[position].value = members[position].value.replacing(at: rest, change)
      }
      return .object(members)
    case (.array(var elements), .index(let index)) where elements.indices.contains(index):
      if rest.isEmpty {
        if let changed = change(elements[index]) {
          elements[index] = changed
        } else {
          elements.remove(at: index)
        }
      } else {
        elements[index] = elements[index].replacing(at: rest, change)
      }
      return .array(elements)
    default:
      return self
    }
  }

  /// Every place in the document with its value, parents before children.
  func locations(under path: JSONPath = []) -> [(path: JSONPath, value: JSONValue)] {
    var found: [(JSONPath, JSONValue)] = [(path, self)]

    switch self {
    case .object(let members):
      for member in members {
        found += member.value.locations(under: path + [.key(member.key)])
      }
    case .array(let elements):
      for (index, element) in elements.enumerated() {
        found += element.locations(under: path + [.index(index)])
      }
    default:
      break
    }

    return found
  }
}
