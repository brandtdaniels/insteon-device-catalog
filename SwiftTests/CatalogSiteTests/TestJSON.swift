import CatalogJSON

/// Reads of JSON documents in tests, independent of the library under test.
extension JSONValue {
  subscript(key: String) -> JSONValue? {
    guard case .object(let members) = self else { return nil }
    return members.first { $0.key == key }?.value
  }

  var members: [JSONMember] {
    guard case .object(let members) = self else { return [] }
    return members
  }

  var elements: [JSONValue] {
    guard case .array(let elements) = self else { return [] }
    return elements
  }

  var string: String? {
    guard case .string(let text) = self else { return nil }
    return text
  }

  var int: Int? {
    guard case .int(let number) = self else { return nil }
    return number
  }

  func has(_ key: String) -> Bool {
    self[key] != nil
  }

  func text(_ key: String) -> String? {
    self[key]?.string
  }

  func list(_ key: String) -> [JSONValue] {
    self[key]?.elements ?? []
  }

  /// Whether the member is the boolean `true`.
  func isTrue(_ key: String) -> Bool {
    self[key] == .bool(true)
  }
}

/// A JSON document written in a test.
func json(_ text: String) -> JSONValue {
  do {
    return try JSONParser.parse(text)
  } catch {
    fatalError("not JSON: \(text)")
  }
}

/// The status of every `verification` in the value, found by reading the JSON independently of
/// the page's own code.
func markedStatuses(in value: JSONValue) -> [String] {
  var found: [String] = []

  func visit(_ node: JSONValue, key: String?) {
    switch node {
    case .object(let members):
      if key == "verification", let status = node["status"]?.string { found.append(status) }
      for member in members { visit(member.value, key: member.key) }
    case .array(let elements):
      for element in elements { visit(element, key: key) }
    default:
      break
    }
  }

  visit(value, key: nil)
  return found
}
