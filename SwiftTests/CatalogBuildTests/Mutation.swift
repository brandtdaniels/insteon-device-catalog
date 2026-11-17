import CatalogJSON

/// One step down a JSON document.
enum Step {
  case key(String)
  case index(Int)
}

extension JSONValue {
  /// The member of an object with this name.
  subscript(key: String) -> JSONValue? {
    guard case .object(let members) = self else { return nil }
    return members.first { $0.key == key }?.value
  }

  /// A copy with the value at `steps` replaced, or removed when `replacement` is `nil`. An object
  /// member that is not there yet is added at the end.
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
    default:
      return self
    }
  }

  /// The steps to the element of the list at `key` whose `name` is `name`.
  func steps(toNamed name: String, in key: String) -> [Step] {
    guard case .array(let elements)? = self[key],
          let index = elements.firstIndex(where: { $0["name"] == .string(name) })
    else { return [] }
    return [.key(key), .index(index)]
  }
}
