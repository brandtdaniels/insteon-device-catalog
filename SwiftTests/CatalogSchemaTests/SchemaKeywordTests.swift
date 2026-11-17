import CatalogJSON
import CatalogSchema
import Testing

/// One schema, one instance and the errors the validator reports, as (path, keyword, message).
struct SchemaCase: Sendable, CustomTestStringConvertible {
  var name: String
  var schema: String
  var instance: String
  var errors: [ExpectedError] = []

  var testDescription: String { name }
}

struct ExpectedError: Equatable, Sendable {
  var path: String
  var keyword: String
  var message: String?

  init(_ path: String, _ keyword: String, _ message: String? = nil) {
    self.path = path
    self.keyword = keyword
    self.message = message
  }
}

/// Each validating keyword with instances that pass and instances that fail, and the path form of
/// every error.
struct SchemaKeywordTests {
  static let cases: [SchemaCase] = [
    // type
    SchemaCase(name: "type string accepts a string", schema: #"{"type": "string"}"#, instance: #""a""#),
    SchemaCase(name: "type string rejects a number", schema: #"{"type": "string"}"#, instance: "1",
               errors: [ExpectedError("$", "type", "1 is not of type 'string'")]),
    SchemaCase(name: "type integer accepts a whole double", schema: #"{"type": "integer"}"#, instance: "2.0"),
    SchemaCase(name: "type integer rejects a fraction", schema: #"{"type": "integer"}"#, instance: "2.5",
               errors: [ExpectedError("$", "type")]),
    SchemaCase(name: "type number accepts an integer", schema: #"{"type": "number"}"#, instance: "2"),
    SchemaCase(name: "type number rejects a boolean", schema: #"{"type": "number"}"#, instance: "true",
               errors: [ExpectedError("$", "type")]),
    SchemaCase(name: "type integer rejects a boolean", schema: #"{"type": "integer"}"#, instance: "false",
               errors: [ExpectedError("$", "type")]),
    SchemaCase(name: "type boolean accepts a boolean", schema: #"{"type": "boolean"}"#, instance: "false"),
    SchemaCase(name: "type object rejects an array", schema: #"{"type": "object"}"#, instance: "[]",
               errors: [ExpectedError("$", "type")]),
    SchemaCase(name: "type array rejects an object", schema: #"{"type": "array"}"#, instance: "{}",
               errors: [ExpectedError("$", "type")]),
    SchemaCase(name: "a type list accepts null", schema: #"{"type": ["string", "null"]}"#, instance: "null"),
    SchemaCase(name: "a type list accepts a string", schema: #"{"type": ["string", "null"]}"#, instance: #""x""#),
    SchemaCase(name: "a type list rejects a number", schema: #"{"type": ["string", "null"]}"#, instance: "3",
               errors: [ExpectedError("$", "type", "3 is not of type 'string', 'null'")]),

    // enum
    SchemaCase(name: "enum accepts a member", schema: #"{"enum": ["a", "b"]}"#, instance: #""b""#),
    SchemaCase(name: "enum rejects a stranger", schema: #"{"enum": ["a", "b"]}"#, instance: #""c""#,
               errors: [ExpectedError("$", "enum", "'c' is not one of ['a', 'b']")]),
    SchemaCase(name: "enum treats 1 and 1.0 as equal", schema: #"{"enum": [1]}"#, instance: "1.0"),
    SchemaCase(name: "enum does not equate true and 1", schema: #"{"enum": [1]}"#, instance: "true",
               errors: [ExpectedError("$", "enum")]),

    // const
    SchemaCase(name: "const accepts its value", schema: #"{"const": {"a": 1, "b": 2}}"#, instance: #"{"b": 2, "a": 1}"#),
    SchemaCase(name: "const rejects another value", schema: #"{"const": "x"}"#, instance: #""y""#,
               errors: [ExpectedError("$", "const", "'x' was expected")]),

    // required
    SchemaCase(name: "required accepts present members", schema: #"{"required": ["a"]}"#, instance: #"{"a": null}"#),
    SchemaCase(name: "required names a missing member", schema: #"{"required": ["a", "b"]}"#, instance: #"{"a": 1}"#,
               errors: [ExpectedError("$", "required", "'b' is a required property")]),
    SchemaCase(name: "required ignores a non-object", schema: #"{"required": ["a"]}"#, instance: "[]"),

    // properties
    SchemaCase(name: "properties checks a member", schema: #"{"properties": {"a": {"type": "string"}}}"#, instance: #"{"a": 1}"#,
               errors: [ExpectedError("$.a", "type")]),
    SchemaCase(name: "properties allows an absent member", schema: #"{"properties": {"a": {"type": "string"}}}"#, instance: "{}"),
    SchemaCase(name: "properties reaches nested members",
               schema: #"{"properties": {"a": {"properties": {"b": {"type": "string"}}}}}"#, instance: #"{"a": {"b": 1}}"#,
               errors: [ExpectedError("$.a.b", "type")]),
    SchemaCase(name: "a key that is not an identifier takes brackets",
               schema: #"{"properties": {"a-b": {"type": "string"}}}"#, instance: #"{"a-b": 1}"#,
               errors: [ExpectedError("$['a-b']", "type")]),

    // additionalProperties
    SchemaCase(name: "additionalProperties false accepts the listed members",
               schema: #"{"properties": {"a": {}}, "additionalProperties": false}"#, instance: #"{"a": 1}"#),
    SchemaCase(name: "additionalProperties false names the stranger",
               schema: #"{"properties": {"a": {}}, "additionalProperties": false}"#, instance: #"{"a": 1, "z": 2}"#,
               errors: [ExpectedError("$", "additionalProperties", "Additional properties are not allowed ('z' was unexpected)")]),
    SchemaCase(name: "additionalProperties false names every stranger",
               schema: #"{"additionalProperties": false}"#, instance: #"{"y": 1, "z": 2}"#,
               errors: [ExpectedError("$", "additionalProperties", "Additional properties are not allowed ('y', 'z' were unexpected)")]),
    SchemaCase(name: "additionalProperties true accepts anything",
               schema: #"{"additionalProperties": true}"#, instance: #"{"z": 2}"#),

    // items
    SchemaCase(name: "items accepts matching elements", schema: #"{"items": {"type": "integer"}}"#, instance: "[1, 2]"),
    SchemaCase(name: "items names the element", schema: #"{"items": {"type": "integer"}}"#, instance: #"[1, "x", 3, "y"]"#,
               errors: [ExpectedError("$[1]", "type"), ExpectedError("$[3]", "type")]),
    SchemaCase(name: "items ignores a non-array", schema: #"{"items": {"type": "integer"}}"#, instance: #""x""#),

    // minItems, maxItems
    SchemaCase(name: "minItems accepts enough", schema: #"{"minItems": 2}"#, instance: "[1, 2]"),
    SchemaCase(name: "minItems rejects too few", schema: #"{"minItems": 2}"#, instance: "[1]",
               errors: [ExpectedError("$", "minItems", "[1] is too short")]),
    SchemaCase(name: "maxItems accepts few enough", schema: #"{"maxItems": 1}"#, instance: "[1]"),
    SchemaCase(name: "maxItems rejects too many", schema: #"{"maxItems": 1}"#, instance: "[1, 2]",
               errors: [ExpectedError("$", "maxItems", "[1, 2] is too long")]),

    // uniqueItems
    SchemaCase(name: "uniqueItems accepts distinct elements", schema: #"{"uniqueItems": true}"#, instance: #"[1, "1", true]"#),
    SchemaCase(name: "uniqueItems rejects a repeat", schema: #"{"uniqueItems": true}"#, instance: "[1, 2, 1]",
               errors: [ExpectedError("$", "uniqueItems", "[1, 2, 1] has non-unique elements")]),
    SchemaCase(name: "uniqueItems treats 1 and 1.0 as one value", schema: #"{"uniqueItems": true}"#, instance: "[1, 1.0]",
               errors: [ExpectedError("$", "uniqueItems")]),
    SchemaCase(name: "uniqueItems ignores member order", schema: #"{"uniqueItems": true}"#, instance: #"[{"a": 1, "b": 2}, {"b": 2, "a": 1}]"#,
               errors: [ExpectedError("$", "uniqueItems")]),
    SchemaCase(name: "uniqueItems false allows a repeat", schema: #"{"uniqueItems": false}"#, instance: "[1, 1]"),

    // minimum, maximum, exclusiveMinimum
    SchemaCase(name: "minimum accepts the bound", schema: #"{"minimum": 0}"#, instance: "0"),
    SchemaCase(name: "minimum rejects below", schema: #"{"minimum": 0}"#, instance: "-1",
               errors: [ExpectedError("$", "minimum", "-1 is less than the minimum of 0")]),
    SchemaCase(name: "maximum accepts the bound", schema: #"{"maximum": 255}"#, instance: "255"),
    SchemaCase(name: "maximum rejects above", schema: #"{"maximum": 255}"#, instance: "256",
               errors: [ExpectedError("$", "maximum", "256 is greater than the maximum of 255")]),
    SchemaCase(name: "exclusiveMinimum rejects the bound", schema: #"{"exclusiveMinimum": 0}"#, instance: "0",
               errors: [ExpectedError("$", "exclusiveMinimum", "0 is less than or equal to the minimum of 0")]),
    SchemaCase(name: "exclusiveMinimum accepts above", schema: #"{"exclusiveMinimum": 0}"#, instance: "0.5"),
    SchemaCase(name: "minimum ignores a string", schema: #"{"minimum": 0}"#, instance: #""x""#),

    // minLength, maxLength
    SchemaCase(name: "minLength rejects an empty string", schema: #"{"minLength": 1}"#, instance: #""""#,
               errors: [ExpectedError("$", "minLength", "'' is too short")]),
    SchemaCase(name: "minLength accepts one character", schema: #"{"minLength": 1}"#, instance: #""a""#),
    SchemaCase(name: "maxLength counts code points", schema: #"{"maxLength": 1}"#, instance: #""😀""#),
    SchemaCase(name: "maxLength rejects a longer string", schema: #"{"maxLength": 1}"#, instance: #""ab""#,
               errors: [ExpectedError("$", "maxLength", "'ab' is too long")]),

    // minProperties, maxProperties
    SchemaCase(name: "minProperties rejects an empty object", schema: #"{"minProperties": 1}"#, instance: "{}",
               errors: [ExpectedError("$", "minProperties", "{} does not have enough properties")]),
    SchemaCase(name: "minProperties accepts one member", schema: #"{"minProperties": 1}"#, instance: #"{"a": 1}"#),
    SchemaCase(name: "maxProperties rejects too many", schema: #"{"maxProperties": 1}"#, instance: #"{"a": 1, "b": 2}"#,
               errors: [ExpectedError("$", "maxProperties", "{'a': 1, 'b': 2} has too many properties")]),

    // pattern
    SchemaCase(name: "pattern accepts a match", schema: #"{"pattern": "^[a-z][A-Za-z0-9]*$"}"#, instance: #""fooBar2""#),
    SchemaCase(name: "pattern rejects a mismatch", schema: #"{"pattern": "^[a-z][A-Za-z0-9]*$"}"#, instance: #""Foo""#,
               errors: [ExpectedError("$", "pattern", "'Foo' does not match '^[a-z][A-Za-z0-9]*$'")]),
    SchemaCase(name: "pattern is not anchored unless it says so", schema: #"{"pattern": "b"}"#, instance: #""abc""#),
    SchemaCase(name: "pattern end anchor does not accept a trailing newline", schema: #"{"pattern": "^[a-z]+$"}"#, instance: #""abc\n""#,
               errors: [ExpectedError("$", "pattern")]),
    SchemaCase(name: "pattern escaped dollar matches a dollar sign", schema: #"{"pattern": "^a\\$$"}"#, instance: #""a$""#),
    SchemaCase(name: "pattern dollar inside a class is a dollar sign", schema: #"{"pattern": "^[$]$"}"#, instance: #""$""#),
    SchemaCase(name: "pattern alternation with groups", schema: #"{"pattern": "^(0x[0-9A-F]{6}|none)$"}"#, instance: #""none""#),
    SchemaCase(name: "pattern alternation rejects a partial match", schema: #"{"pattern": "^(0x[0-9A-F]{6}|none)$"}"#, instance: #""0x1234""#,
               errors: [ExpectedError("$", "pattern")]),
    SchemaCase(name: "pattern ignores a number", schema: #"{"pattern": "^a$"}"#, instance: "1"),

    // oneOf
    SchemaCase(name: "oneOf accepts exactly one match",
               schema: #"{"oneOf": [{"type": "string"}, {"type": "integer"}]}"#, instance: "1"),
    SchemaCase(name: "oneOf rejects no match",
               schema: #"{"oneOf": [{"type": "string"}, {"type": "integer"}]}"#, instance: "true",
               errors: [ExpectedError("$", "oneOf", "true is not valid under any of the given schemas")]),
    SchemaCase(name: "oneOf rejects two matches",
               schema: #"{"oneOf": [{"type": "number"}, {"type": "integer"}]}"#, instance: "1",
               errors: [ExpectedError("$", "oneOf", "1 is valid under each of the 2 given schemas")]),
    SchemaCase(name: "oneOf reports the branch its const names",
               schema: #"""
               {"oneOf": [
                 {"properties": {"kind": {"const": "a"}, "x": {"type": "string"}}, "required": ["kind"]},
                 {"properties": {"kind": {"const": "b"}, "y": {"type": "string"}}, "required": ["kind"]}
               ]}
               """#,
               instance: #"{"kind": "b", "y": 1}"#,
               errors: [ExpectedError("$.y", "type")]),
    SchemaCase(name: "oneOf with no named branch reports the choice",
               schema: #"""
               {"oneOf": [
                 {"properties": {"kind": {"const": "a"}}, "required": ["kind"]},
                 {"properties": {"kind": {"const": "b"}}, "required": ["kind"]}
               ]}
               """#,
               instance: #"{"kind": "c"}"#,
               errors: [ExpectedError("$", "oneOf")]),

    // not
    SchemaCase(name: "not accepts what its schema rejects", schema: #"{"not": {"required": ["a", "b"]}}"#, instance: #"{"a": 1}"#),
    SchemaCase(name: "not rejects what its schema accepts", schema: #"{"not": {"required": ["a", "b"]}}"#, instance: #"{"a": 1, "b": 2}"#,
               errors: [ExpectedError("$", "not", "{'a': 1, 'b': 2} should not be valid under {'required': ['a', 'b']}")]),

    // $ref and $defs
    SchemaCase(name: "$ref follows a local definition",
               schema: ##"{"$defs": {"id": {"type": "string"}}, "properties": {"a": {"$ref": "#/$defs/id"}}}"##, instance: #"{"a": 1}"#,
               errors: [ExpectedError("$.a", "type")]),
    SchemaCase(name: "$ref follows a chain of definitions",
               schema: ##"{"$defs": {"a": {"$ref": "#/$defs/b"}, "b": {"type": "string"}}, "$ref": "#/$defs/a"}"##, instance: "1",
               errors: [ExpectedError("$", "type")]),
    SchemaCase(name: "$ref beside other keywords checks both",
               schema: ##"{"$defs": {"s": {"type": "string"}}, "$ref": "#/$defs/s", "minLength": 3}"##, instance: #""ab""#,
               errors: [ExpectedError("$", "minLength")]),
    SchemaCase(name: "$ref inside items names the element",
               schema: ##"{"$defs": {"s": {"type": "string"}}, "items": {"$ref": "#/$defs/s"}}"##, instance: #"["a", 2]"#,
               errors: [ExpectedError("$[1]", "type")]),
    SchemaCase(name: "$ref to a recursive definition walks the instance",
               schema: #"""
               {"$defs": {"node": {"properties": {"next": {"$ref": "#/$defs/node"}, "n": {"type": "integer"}}}}, "$ref": "#/$defs/node"}
               """#,
               instance: #"{"n": 1, "next": {"n": 2, "next": {"n": "x"}}}"#,
               errors: [ExpectedError("$.next.next.n", "type")]),

    // annotations never fail an instance
    SchemaCase(name: "annotations are ignored",
               schema: #"{"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "x", "title": "t", "description": "d", "default": 1}"#,
               instance: "[]"),

    // several errors at once come out in schema order
    SchemaCase(name: "errors come in the order the schema names the keywords",
               schema: #"{"required": ["a"], "properties": {"b": {"type": "string"}}, "additionalProperties": false}"#, instance: #"{"b": 1, "c": 2}"#,
               errors: [ExpectedError("$", "required"), ExpectedError("$.b", "type"), ExpectedError("$", "additionalProperties")])
  ]

  @Test(arguments: cases)
  func reportsTheErrorsAtTheirPaths(_ item: SchemaCase) throws {
    let validator = try SchemaValidator(schema: JSONParser.parse(item.schema))
    let found = validator.errors(in: try JSONParser.parse(item.instance))

    #expect(found.map { ExpectedError($0.path, $0.keyword) } == item.errors.map { ExpectedError($0.path, $0.keyword) })
    for (error, expected) in zip(found, item.errors) {
      if let message = expected.message {
        #expect(error.message == message)
      }
    }
    #expect(validator.isValid(try JSONParser.parse(item.instance)) == item.errors.isEmpty)
  }
}
