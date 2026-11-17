import CatalogJSON
import Foundation

/// Checks a document against a JSON Schema (Draft 2020-12) that stays inside the keywords of
/// ``SchemaKeywords``.
///
/// A schema that uses any other keyword, holds a keyword value of the wrong kind or refers outside
/// itself is refused when the validator is made, so a schema can never ask for a rule the
/// validator skips. References are local, as `#` or `#/path/to/schema`.
public struct SchemaValidator: Sendable {
  private let root: JSONValue
  private let patterns: [String: SchemaPattern]

  /// Reads the schema and throws ``SchemaLoadError`` when it can't be used.
  public init(schema: JSONValue) throws(SchemaLoadError) {
    var patterns: [String: SchemaPattern] = [:]
    try Self.check(schema, root: schema, at: ["#"], patterns: &patterns)
    self.root = schema
    self.patterns = patterns
  }

  /// Every way the document breaks the schema, in the order the schema names its keywords.
  public func errors(in document: JSONValue) -> [SchemaError] {
    var found: [SchemaError] = []
    validate(document, against: root, at: "$", into: &found)
    return found
  }

  /// Whether the document breaks no rule of the schema.
  public func isValid(_ document: JSONValue) -> Bool {
    errors(in: document).isEmpty
  }

  // MARK: Loading

  private static let typeNames: Set<String> = ["object", "array", "string", "number", "integer", "boolean", "null"]
  private static let sizeKeywords: Set<String> = ["minItems", "maxItems", "minLength", "maxLength", "minProperties", "maxProperties"]
  private static let numberKeywords: Set<String> = ["minimum", "maximum", "exclusiveMinimum"]

  private static func check(
    _ schema: JSONValue, root: JSONValue, at location: [String], patterns: inout [String: SchemaPattern]
  ) throws(SchemaLoadError) {
    guard case .object(let members) = schema else {
      throw .malformedKeyword(location.last ?? "#", at: pointer(location.dropLast()))
    }
    let here = pointer(location)
    for member in members {
      let keyword = member.key
      if !SchemaKeywords.validating.contains(keyword), !SchemaKeywords.annotations.contains(keyword) {
        throw .unsupportedKeyword(keyword, at: here)
      }
      guard isWellFormed(member, root: root, patterns: &patterns) else {
        if keyword == "$ref", case .string(let reference) = member.value {
          throw .unresolvedReference(reference, at: here)
        }
        throw .malformedKeyword(keyword, at: here)
      }
      for child in SubschemaWalk.located(in: member) {
        try check(child.schema, root: root, at: location + child.segments, patterns: &patterns)
      }
    }
  }

  /// Whether the keyword's value is of the kind the keyword takes. Subschemas are checked apart.
  private static func isWellFormed(_ member: JSONMember, root: JSONValue, patterns: inout [String: SchemaPattern]) -> Bool {
    let value = member.value
    switch member.key {
    case "type":
      switch value {
      case .string(let name): return typeNames.contains(name)
      case .array(let names):
        return !names.isEmpty && names.allSatisfy { if case .string(let name) = $0 { typeNames.contains(name) } else { false } }
      default: return false
      }
    case "required":
      guard case .array(let names) = value else { return false }
      return names.allSatisfy { if case .string = $0 { true } else { false } }
    case "enum":
      if case .array = value { return true }
      return false
    case "properties", "$defs":
      if case .object = value { return true }
      return false
    case "items", "not":
      if case .object = value { return true }
      return false
    case "additionalProperties", "uniqueItems":
      if case .bool = value { return true }
      return false
    case "oneOf":
      if case .array(let branches) = value { return !branches.isEmpty }
      return false
    case "pattern":
      guard case .string(let text) = value, let pattern = SchemaPattern(text) else { return false }
      patterns[text] = pattern
      return true
    case "$ref":
      guard case .string(let reference) = value else { return false }
      return resolve(reference, in: root) != nil
    case let keyword where sizeKeywords.contains(keyword):
      if case .int(let size) = value { return size >= 0 }
      return false
    case let keyword where numberKeywords.contains(keyword):
      return value.number != nil
    default:
      return true
    }
  }

  /// The schema a local reference names: `#` for the whole, `#/a/b` for a part.
  private static func resolve(_ reference: String, in root: JSONValue) -> JSONValue? {
    if reference == "#" { return root }
    guard reference.hasPrefix("#/") else { return nil }
    var current = root
    for segment in reference.dropFirst(2).split(separator: "/", omittingEmptySubsequences: false) {
      let name = String(segment).replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
      switch current {
      case .object:
        guard let next = current.member(name) else { return nil }
        current = next
      case .array(let elements):
        guard let index = Int(name), elements.indices.contains(index) else { return nil }
        current = elements[index]
      default:
        return nil
      }
    }
    if case .object = current { return current }
    return nil
  }

  private static func pointer(_ segments: some Sequence<String>) -> String {
    segments.joined(separator: "/")
  }

  // MARK: Validating

  private func validate(_ value: JSONValue, against schema: JSONValue, at path: String, into found: inout [SchemaError]) {
    guard case .object(let rules) = schema else { return }
    for rule in rules {
      apply(rule, among: rules, to: value, at: path, into: &found)
    }
  }

  private func apply(_ rule: JSONMember, among rules: [JSONMember], to value: JSONValue, at path: String, into found: inout [SchemaError]) {
    func fail(_ message: String) {
      found.append(SchemaError(path: path, keyword: rule.key, message: message))
    }
    let argument = rule.value

    switch rule.key {
    case "type":
      let names: [String]
      switch argument {
      case .string(let name): names = [name]
      case .array(let list): names = list.compactMap { if case .string(let name) = $0 { name } else { nil } }
      default: names = []
      }
      if !names.contains(where: { Self.has(type: $0, value) }) {
        fail("\(value.summary) is not of type \(names.map { "'\($0)'" }.joined(separator: ", "))")
      }

    case "enum":
      if case .array(let options) = argument, !options.contains(where: { $0.isSchemaEqual(to: value) }) {
        fail("\(value.summary) is not one of \(argument.summary)")
      }

    case "const":
      if !argument.isSchemaEqual(to: value) {
        fail("\(argument.summary) was expected")
      }

    case "required":
      if case .object(let members) = value, case .array(let names) = argument {
        for case .string(let name) in names where !members.contains(where: { $0.key == name }) {
          fail("'\(name)' is a required property")
        }
      }

    case "properties":
      if case .object(let members) = value, case .object(let declared) = argument {
        for property in declared {
          if let child = members.first(where: { $0.key == property.key }) {
            validate(child.value, against: property.value, at: Self.path(path, member: child.key), into: &found)
          }
        }
      }

    case "additionalProperties":
      if case .bool(false) = argument, case .object(let members) = value {
        let declared: [JSONMember]
        if case .object(let list)? = rules.first(where: { $0.key == "properties" })?.value { declared = list } else { declared = [] }
        let strangers = members.map(\.key).filter { key in !declared.contains { $0.key == key } }
        if !strangers.isEmpty {
          let names = strangers.map { "'\($0)'" }.joined(separator: ", ")
          fail("Additional properties are not allowed (\(names) \(strangers.count == 1 ? "was" : "were") unexpected)")
        }
      }

    case "items":
      if case .array(let elements) = value {
        for (index, element) in elements.enumerated() {
          validate(element, against: argument, at: "\(path)[\(index)]", into: &found)
        }
      }

    case "minItems", "maxItems":
      if case .array(let elements) = value, case .int(let limit) = argument {
        if rule.key == "minItems", elements.count < limit { fail("\(value.summary) is too short") }
        if rule.key == "maxItems", elements.count > limit { fail("\(value.summary) is too long") }
      }

    case "uniqueItems":
      if case .bool(true) = argument, case .array(let elements) = value {
        let repeated = elements.indices.contains { index in
          elements[(index + 1)...].contains { $0.isSchemaEqual(to: elements[index]) }
        }
        if repeated { fail("\(value.summary) has non-unique elements") }
      }

    case "minimum", "maximum", "exclusiveMinimum":
      if let number = value.number, let limit = argument.number {
        switch rule.key {
        case "minimum" where number < limit:
          fail("\(value.summary) is less than the minimum of \(argument.summary)")
        case "maximum" where number > limit:
          fail("\(value.summary) is greater than the maximum of \(argument.summary)")
        case "exclusiveMinimum" where number <= limit:
          fail("\(value.summary) is less than or equal to the minimum of \(argument.summary)")
        default:
          break
        }
      }

    case "minLength", "maxLength":
      if case .string(let text) = value, case .int(let limit) = argument {
        let length = text.unicodeScalars.count
        if rule.key == "minLength", length < limit { fail("\(value.summary) is too short") }
        if rule.key == "maxLength", length > limit { fail("\(value.summary) is too long") }
      }

    case "minProperties", "maxProperties":
      if case .object(let members) = value, case .int(let limit) = argument {
        if rule.key == "minProperties", members.count < limit { fail("\(value.summary) does not have enough properties") }
        if rule.key == "maxProperties", members.count > limit { fail("\(value.summary) has too many properties") }
      }

    case "pattern":
      if case .string(let text) = value, case .string(let source) = argument, let pattern = patterns[source], !pattern.matches(text) {
        fail("\(value.summary) does not match '\(source)'")
      }

    case "oneOf":
      if case .array(let branches) = argument {
        applyOneOf(branches, to: value, at: path, into: &found)
      }

    case "not":
      if isValid(value, against: argument) {
        fail("\(value.summary) should not be valid under \(argument.summary)")
      }

    case "$ref":
      if case .string(let reference) = argument, let target = Self.resolve(reference, in: root) {
        validate(value, against: target, at: path, into: &found)
      }

    default:
      break
    }
  }

  private func applyOneOf(_ branches: [JSONValue], to value: JSONValue, at path: String, into found: inout [SchemaError]) {
    let valid = branches.filter { isValid(value, against: $0) }
    switch valid.count {
    case 1:
      return
    case 0:
      let named = branches.filter { Self.branch($0, isNamedBy: value) }
      if named.count == 1 {
        validate(value, against: named[0], at: path, into: &found)
      } else {
        found.append(SchemaError(path: path, keyword: "oneOf", message: "\(value.summary) is not valid under any of the given schemas"))
      }
    default:
      found.append(SchemaError(path: path, keyword: "oneOf", message: "\(value.summary) is valid under each of the \(valid.count) given schemas"))
    }
  }

  /// Whether a branch pins a property to a constant and the document carries that constant, which
  /// says the document meant this branch.
  private static func branch(_ branch: JSONValue, isNamedBy value: JSONValue) -> Bool {
    guard case .object(let declared)? = branch.member("properties") else { return false }
    let pinned = declared.compactMap { property in property.value.member("const").map { (property.key, $0) } }
    return !pinned.isEmpty && pinned.allSatisfy { key, constant in value.member(key)?.isSchemaEqual(to: constant) ?? false }
  }

  private func isValid(_ value: JSONValue, against schema: JSONValue) -> Bool {
    var found: [SchemaError] = []
    validate(value, against: schema, at: "$", into: &found)
    return found.isEmpty
  }

  private static func has(type name: String, _ value: JSONValue) -> Bool {
    switch (name, value) {
    case ("object", .object), ("array", .array), ("string", .string), ("boolean", .bool), ("null", .null), ("integer", .int), ("number", .int), ("number", .double):
      return true
    case ("integer", .double(let number)):
      return number.rounded() == number
    default:
      return false
    }
  }

  private static func path(_ path: String, member name: String) -> String {
    let isIdentifier = name.first.map { $0 == "_" || ($0.isASCII && $0.isLetter) } ?? false
      && name.allSatisfy { $0 == "_" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }
    return isIdentifier ? "\(path).\(name)" : "\(path)['\(name)']"
  }
}
