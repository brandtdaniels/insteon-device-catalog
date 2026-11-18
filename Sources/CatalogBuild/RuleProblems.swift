import CatalogJSON
import CatalogRules
import CatalogSchema

extension RepositoryRoot {
  /// Every problem the catalog's profiles and command sets have, one line each, in the order the
  /// checks find them: each profile by file name (its schema errors, or else its own rules), the
  /// identities profiles share, each command set by file name (its schema errors, or else its own
  /// rules), then each profile's use of the command sets.
  ///
  /// A file that fails its schema gets no rule checks. The list is empty when every file passes.
  public func problems() throws -> [String] {
    try problems(deviceSchema: schema(.deviceProfile), commandSetSchema: schema(.commandSet))
  }

  /// The same checks against schemas the caller supplies.
  public func problems(deviceSchema: JSONValue, commandSetSchema: JSONValue) throws -> [String] {
    let deviceValidator = try SchemaValidator(schema: deviceSchema)
    let commandSetValidator = try SchemaValidator(schema: commandSetSchema)
    var problems: [String] = []
    var profiles: [JSONValue] = []
    var commandSets: [JSONValue] = []

    for file in try deviceFiles() {
      let schemaErrors = deviceValidator.errors(in: file.value).map { $0.report(file: file.name) }

      guard schemaErrors.isEmpty else {
        problems += schemaErrors
        continue
      }

      problems += ProfileRules.problems(in: file.value, fileStem: file.stem).map { "\(file.name): \($0)" }
      profiles.append(file.value)
    }

    problems += ProfileRules.overlappingIdentities(profiles)

    for file in try commandSetFiles() {
      let schemaErrors = commandSetValidator.errors(in: file.value).map { $0.report(file: file.name) }

      guard schemaErrors.isEmpty else {
        problems += schemaErrors
        continue
      }

      problems += CommandSetRules.problems(in: file.value, fileStem: file.stem).map { "\(file.name): \($0)" }
      commandSets.append(file.value)
    }

    let commandSetsById = CommandSetRules.byId(commandSets)

    for profile in profiles {
      problems += ProfileRules.commandSetProblems(for: profile, commandSets: commandSetsById)
    }

    return problems
  }
}
