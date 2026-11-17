import CatalogJSON

/// The schema keywords the validator knows.
public enum SchemaKeywords {
  /// Keywords that decide whether a document is valid.
  public static let validating: Set<String> = [
    "type", "enum", "const", "required", "properties", "additionalProperties", "items", "minItems", "maxItems",
    "uniqueItems", "minimum", "maximum", "exclusiveMinimum", "minLength", "maxLength", "minProperties",
    "maxProperties", "pattern", "oneOf", "not", "$ref"
  ]

  /// Keywords that describe or name a schema and never reject a document.
  public static let annotations: Set<String> = ["$schema", "$id", "$defs", "title", "description", "default"]

  /// Every keyword a schema uses, without the names of its properties or definitions and without
  /// the data inside `const`, `enum` and `default`.
  public static func used(in schema: JSONValue) -> Set<String> {
    var found: Set<String> = []
    collect(schema, into: &found)
    return found
  }

  private static func collect(_ schema: JSONValue, into found: inout Set<String>) {
    guard case .object(let members) = schema else { return }
    for member in members {
      found.insert(member.key)
      for subschema in SubschemaWalk.children(of: member) {
        collect(subschema, into: &found)
      }
    }
  }
}

/// Where a schema keeps schemas inside itself.
enum SubschemaWalk {
  /// A subschema and the pointer segments from its parent to it.
  struct Child {
    var segments: [String]
    var schema: JSONValue
  }

  /// The schemas held by one member of a schema object, with the segments leading to each.
  static func located(in member: JSONMember) -> [Child] {
    switch (member.key, member.value) {
    case ("properties", .object(let members)), ("$defs", .object(let members)):
      return members.map { Child(segments: [member.key, $0.key], schema: $0.value) }
    case ("items", .object), ("not", .object), ("additionalProperties", .object):
      return [Child(segments: [member.key], schema: member.value)]
    case ("oneOf", .array(let elements)):
      return elements.enumerated().map { Child(segments: [member.key, String($0.offset)], schema: $0.element) }
    default:
      return []
    }
  }

  static func children(of member: JSONMember) -> [JSONValue] {
    located(in: member).map(\.schema)
  }
}
