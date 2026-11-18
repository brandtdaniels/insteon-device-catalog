import CatalogJSON
import CatalogRules
import Foundation

/// What loading the document registry found.
public struct DocumentRegistryLoad: Sendable {
  /// The registered titles, or `nil` when the registry or the reviewed pairs have a problem.
  public let titles: RegisteredTitles?
  /// What is wrong with the registry file, the reviewed pairs file, and the titles between them.
  public let problems: [String]
}

extension RepositoryRoot {
  /// The registered titles, and what is wrong with the registry. A file that can't be read or
  /// parsed is the only problem reported. Otherwise the registry's own problems come first; the
  /// reviewed pairs file is read only when the registry has none, and the near-duplicate titles are
  /// checked only when neither has any.
  public func documentRegistry() -> DocumentRegistryLoad {
    let registry: JSONValue

    switch document(RegistryRules.registryFile) {
    case .failure(let reason): return DocumentRegistryLoad(titles: nil, problems: [reason.line])
    case .success(let value): registry = value
    }

    var problems = RegistryRules.problems(in: registry)
    var reviewed: [JSONValue] = []

    if problems.isEmpty {
      switch document(RegistryRules.reviewedFile) {
      case .failure(let reason):
        problems = [reason.line]
      case .success(let value):
        switch RegistryRules.reviewedPairs(in: value) {
        case .failure(let error): problems = ["\(RegistryRules.reviewedFile): \(error)"]
        case .success(let pairs): reviewed = pairs
        }
      }
    }

    if problems.isEmpty {
      problems = RegistryRules.nearDuplicateProblems(in: registry, reviewed: reviewed)
    }

    guard problems.isEmpty else { return DocumentRegistryLoad(titles: nil, problems: problems) }

    return DocumentRegistryLoad(titles: RegisteredTitles(titles(in: registry)), problems: [])
  }

  /// The titles of the registry's entries.
  private func titles(in registry: JSONValue) -> [String] {
    guard case .object(let members) = registry, case .array(let entries)? = members.first?.value else { return [] }

    return entries.compactMap { entry in
      guard case .object(let fields) = entry, case .string(let title)? = fields.first(where: { $0.key == "title" })?.value else { return nil }

      return title
    }
  }

  /// One line for each file under `devices`, `commandSets` and `documents`, in that order and by
  /// file name, that holds an em dash or an en dash.
  public func dashProblems() throws(RepositoryError) -> [String] {
    var problems: [String] = []

    for directory in ["devices", "commandSets", "documents"] {
      for name in jsonFileNames(in: directory) {
        let path = "\(directory)/\(name)"

        guard let text = try? String(contentsOf: url.appendingPathComponent(path), encoding: .utf8) else {
          throw .unreadable(file: path, reason: "the file can't be read")
        }

        problems += DashRules.problems(file: path, text: text)
      }
    }

    return problems
  }

  /// A file of `documents` parsed, or the line that says why it can't be: its name, then that the
  /// file can't be read, or where it stops being JSON.
  private func document(_ name: String) -> Result<JSONValue, DocumentFileFailure> {
    do {
      return .success(try read("documents/\(name)"))
    } catch .unparseable(_, let error) {
      return .failure(DocumentFileFailure(line: "\(name): \(error)"))
    } catch {
      return .failure(DocumentFileFailure(line: "\(name): the file can't be read"))
    }
  }
}

private struct DocumentFileFailure: Error, CustomStringConvertible {
  let line: String

  var description: String { line }
}
