import CatalogJSON
import CatalogSchema

extension RepositoryRoot {
  /// The schema errors of every profile and then every command set, one line each as
  /// `file.json: $.path: message`, in file name order. The list is empty when every file passes.
  public func schemaProblems() throws -> [String] {
    try schemaProblems(deviceSchema: schema(.deviceProfile), commandSetSchema: schema(.commandSet))
  }

  /// The same check against schemas the caller supplies.
  public func schemaProblems(deviceSchema: JSONValue, commandSetSchema: JSONValue) throws -> [String] {
    let devices = try SchemaValidator(schema: deviceSchema)
    let commandSets = try SchemaValidator(schema: commandSetSchema)

    return try deviceFiles().flatMap { file in devices.errors(in: file.value).map { $0.report(file: file.name) } }
      + commandSetFiles().flatMap { file in commandSets.errors(in: file.value).map { $0.report(file: file.name) } }
  }
}
