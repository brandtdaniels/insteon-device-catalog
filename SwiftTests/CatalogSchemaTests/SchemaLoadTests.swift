import CatalogJSON
import CatalogSchema
import Testing

/// A schema the validator does not fully implement is refused when it loads, never skipped.
struct SchemaLoadTests {
  @Test(arguments: ["allOf", "anyOf", "if", "then", "else", "format", "patternProperties", "contains", "dependentRequired", "prefixItems",
                    "propertyNames", "multipleOf", "exclusiveMaximum", "unevaluatedProperties", "$dynamicRef", "$anchor", "$vocabulary"])
  func refusesAKeywordItDoesNotImplement(_ keyword: String) throws {
    let schema = try JSONParser.parse(#"{"properties": {"a": {"\#(keyword)": []}}}"#)

    #expect(throws: SchemaLoadError.unsupportedKeyword(keyword, at: "#/properties/a")) {
      try SchemaValidator(schema: schema)
    }
  }

  @Test func refusesAKeywordInsideADefinition() throws {
    let schema = try JSONParser.parse(#"{"$defs": {"d": {"items": {"oneOf": [{"allOf": []}]}}}}"#)

    #expect(throws: SchemaLoadError.unsupportedKeyword("allOf", at: "#/$defs/d/items/oneOf/0")) {
      try SchemaValidator(schema: schema)
    }
  }

  @Test func readsAPropertyNamedLikeAKeywordAsAName() throws {
    let schema = try JSONParser.parse(#"{"properties": {"allOf": {"type": "string"}}, "$defs": {"format": {"type": "string"}}}"#)

    #expect(throws: Never.self) { try SchemaValidator(schema: schema) }
  }

  @Test func doesNotReadInsideValuesThatAreData() throws {
    let schema = try JSONParser.parse(#"{"const": {"allOf": 1}, "enum": [{"format": 1}], "default": {"if": 1}}"#)

    #expect(throws: Never.self) { try SchemaValidator(schema: schema) }
  }

  @Test func refusesAReferenceThatIsNotLocal() throws {
    let schema = try JSONParser.parse(#"{"$ref": "https://example.com/other.json"}"#)

    #expect(throws: SchemaLoadError.unresolvedReference("https://example.com/other.json", at: "#")) {
      try SchemaValidator(schema: schema)
    }
  }

  @Test func refusesAReferenceToNothing() throws {
    let schema = try JSONParser.parse(##"{"properties": {"a": {"$ref": "#/$defs/missing"}}}"##)

    #expect(throws: SchemaLoadError.unresolvedReference("#/$defs/missing", at: "#/properties/a")) {
      try SchemaValidator(schema: schema)
    }
  }

  @Test(arguments: [
    (#"{"type": "text"}"#, "type"),
    (#"{"type": 3}"#, "type"),
    (#"{"required": "a"}"#, "required"),
    (#"{"enum": 1}"#, "enum"),
    (#"{"minItems": "1"}"#, "minItems"),
    (#"{"additionalProperties": {"type": "string"}}"#, "additionalProperties"),
    (#"{"oneOf": {}}"#, "oneOf"),
    (#"{"pattern": "("}"#, "pattern"),
    (#"{"uniqueItems": 1}"#, "uniqueItems")
  ])
  func refusesAKeywordWithTheWrongKindOfValue(_ schemaText: String, _ keyword: String) throws {
    let schema = try JSONParser.parse(schemaText)

    #expect(throws: SchemaLoadError.malformedKeyword(keyword, at: "#")) {
      try SchemaValidator(schema: schema)
    }
  }

  @Test func listsTheKeywordsASchemaUses() throws {
    let schema = try JSONParser.parse(#"{"$schema": "x", "properties": {"type": {"type": "string", "minLength": 1}}, "const": {"allOf": 1}}"#)

    #expect(SchemaKeywords.used(in: schema) == ["$schema", "properties", "type", "minLength", "const"])
  }

  @Test func namesTheKeywordsItImplements() {
    #expect(SchemaKeywords.validating == [
      "type", "enum", "const", "required", "properties", "additionalProperties", "items", "minItems", "maxItems", "uniqueItems",
      "minimum", "maximum", "exclusiveMinimum", "minLength", "maxLength", "minProperties", "maxProperties", "pattern", "oneOf", "not", "$ref"
    ])
    #expect(SchemaKeywords.annotations == ["$schema", "$id", "$defs", "title", "description", "default"])
  }
}
