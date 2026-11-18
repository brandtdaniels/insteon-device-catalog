import CatalogJSON
import Foundation

/// What applying a report did: the exit status and the lines to print.
public struct ApplyOutcome: Equatable, Sendable {
  public let status: Int32
  public let messages: [String]

  public init(status: Int32, messages: [String]) {
    self.status = status
    self.messages = messages
  }
}

/// Applies a reviewed draft to the profile files, then proves the catalog still checks.
///
/// This is a maintainer's action. It refuses a working tree that holds other work, a report it did
/// not expect to read, and a catalog that has moved since the report was drafted; and it puts every
/// file back when the check fails.
public enum ReportApplication {
  /// Applies every drafted change in the report.
  ///
  /// - Parameters:
  ///   - root: The repository whose `devices/` the changes name.
  ///   - allowed: Paths relative to `root` that may be untracked or modified, such as the report itself.
  public static func apply(
    _ report: JSONValue, in root: URL, checker: any CatalogChecking, tree: any WorkingTreeReading, allowed: Set<String>
  ) -> ApplyOutcome {
    guard report["format"] == .string(IngestReport.format), report["lane"] == .string("observation") else {
      return refused("not an observation report this tool wrote")
    }

    guard case .array(let observations)? = report["observations"] else { return refused("the report has no observations") }

    if observations.contains(where: { $0["outcome"] == .string("rejected") }) {
      return refused("the report holds a rejected observation; fix it and draft again")
    }

    if let problem = treeProblem(in: root, tree: tree, allowed: allowed) { return refused(problem) }

    let changes = observations.filter { $0["outcome"] == .string("drafted") }.flatMap(changesOf)

    guard !changes.isEmpty else { return ApplyOutcome(status: 0, messages: ["nothing to apply: the report drafts no changes"]) }

    for change in changes {
      let problems = ProfilePatching.problems(in: change)

      if !problems.isEmpty { return ApplyOutcome(status: 1, messages: problems) }
    }

    var originals: [String: String] = [:]
    var profiles: [String: JSONValue] = [:]
    var names: [String] = []
    var outcomes: [ProfilePatching.Result] = []

    for change in changes {
      let file = change["file"]?.string ?? ""

      if profiles[file] == nil {
        guard let text = try? String(contentsOf: root.appendingPathComponent(file), encoding: .utf8), let profile = try? JSONParser.parse(text) else {
          return refused("cannot read \(file)")
        }

        originals[file] = text
        profiles[file] = profile
        names.append(file)
      }

      let outcome = ProfilePatching.apply(
        kind: EntryKind(rawValue: change["entry"]?.string ?? "") ?? .identity, selector: change["selector"] ?? .null,
        field: VerificationField(rawValue: change["field"]?.string ?? "") ?? .verification, before: change["before"],
        after: change["after"] ?? .null, to: &profiles[file, default: .null]
      )

      if case .refused(let reason) = outcome { return refused("\(file): \(reason)") }

      outcomes.append(outcome)
    }

    guard outcomes.contains(.applied) else {
      return ApplyOutcome(status: 0, messages: ["already applied: the catalog holds every change in the report"])
    }

    let written = names.filter { name in
      !ProfileFile.text(of: profiles[name] ?? .null).utf8.elementsEqual((originals[name] ?? "").utf8)
    }

    for (position, name) in written.enumerated() {
      do {
        try Data(ProfileFile.text(of: profiles[name] ?? .null).utf8).write(to: root.appendingPathComponent(name))
      } catch {
        restore(written[...position], originals, in: root)

        return refused("cannot write \(name), so every file was put back")
      }
    }

    let result = checker.check(root: root)

    guard result.passed else {
      restore(written[...], originals, in: root)

      return ApplyOutcome(status: 1, messages: ["the build failed, so every file was put back:", result.output])
    }

    let applied = outcomes.filter { $0 == .applied }.count

    return ApplyOutcome(status: 0, messages: ["applied \(applied) changes to \(written.count) files and the build passed"] + written.map { "  \($0)" })
  }

  private static func refused(_ message: String) -> ApplyOutcome {
    ApplyOutcome(status: 1, messages: [message])
  }

  /// Why the working tree is not clean, ignoring the paths in `allowed`.
  private static func treeProblem(in root: URL, tree: any WorkingTreeReading, allowed: Set<String>) -> String? {
    guard let lines = try? tree.statusLines(in: root) else { return "cannot tell whether the working tree is clean" }

    let others = lines.filter { !allowed.contains(String(String.UnicodeScalarView($0.unicodeScalars.dropFirst(3)))) }

    return others.isEmpty ? nil : "the working tree has changes of its own; commit or stash them first"
  }

  /// The changes of one observation's entry. Text or an object where a list belongs is read as one
  /// change that is not an object, so the report is refused.
  private static func changesOf(_ observation: JSONValue) -> [JSONValue] {
    switch observation["changes"] {
    case .array(let elements)?: elements
    case .string(let text)? where !text.isEmpty: [.null]
    case .object(let members)? where !members.isEmpty: [.null]
    default: []
    }
  }

  private static func restore(_ names: ArraySlice<String>, _ originals: [String: String], in root: URL) {
    for name in names {
      try? Data((originals[name] ?? "").utf8).write(to: root.appendingPathComponent(name))
    }
  }
}
