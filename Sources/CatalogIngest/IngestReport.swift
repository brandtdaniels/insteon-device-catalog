import CatalogJSON
import CatalogRules
import Foundation

/// What drafting found in a set of observation files.
public struct IngestReport: Equatable, Sendable {
  /// The format name apply requires.
  public static let format = "insteon-catalog-ingest-report/1"

  public let observations: [ObservationDraft]

  public init(observations: [ObservationDraft]) {
    self.observations = observations
  }

  /// The most urgent outcome among the observations: rejected, then drafted, then needs-human.
  public var outcome: DraftOutcome {
    let outcomes = Set(observations.map(\.outcome))

    return [DraftOutcome.rejected, .drafted, .needsHuman].first(where: outcomes.contains) ?? .noChange
  }

  /// Whether any observation leaves a decision to a maintainer.
  public var hasDisagreements: Bool {
    observations.contains { !$0.disagreements.isEmpty }
  }

  /// The report as the machine-readable list apply reads.
  public var json: JSONValue {
    .object([
      JSONMember(key: "format", value: .string(Self.format)),
      JSONMember(key: "lane", value: .string("observation")),
      JSONMember(key: "outcome", value: .string(outcome.rawValue)),
      JSONMember(key: "observations", value: .array(observations.map(\.json)))
    ])
  }

  /// The report file's text: the list, with two-space indent, characters as written and one final newline.
  public var text: String {
    ((try? JSONWriter.write(json)) ?? "") + "\n"
  }

  /// The report as text for the maintainer. The contributor's note appears here and in no other output.
  ///
  /// - Parameter notes: Each observation's note, in order; `nil` where a file has none or was rejected.
  public func markdown(notes: [String?]) -> String {
    var lines = ["# Observation report", "", "Outcome: \(outcome.rawValue)", ""]

    for (item, note) in zip(observations, notes) {
      lines += ["## \(item.label): \(item.outcome.rawValue)", ""]

      if let matched = item.matched {
        lines += ["Matched \(matched.model) by category \(matched.category) and subcategory \(matched.subcategory).", ""]
      }

      let sections: [(String, [String])] = [
        ("Errors", item.errors),
        ("Proposed changes", item.changes.map { "\($0.file): \($0.target), \($0.field.rawValue): \($0.effect)" }),
        ("Already recorded", item.unchanged.map { "\($0.target): \($0.reason)" }),
        ("Needs a maintainer decision", item.disagreements.map { "\($0.code.rawValue): \($0.detail)" }),
        ("Not used", item.skipped.map { "\($0.check): \($0.reason)" }),
        ("Report only", item.reportOnly.map { "\($0.item): \($0.detail)" }),
        ("Warnings", item.warnings)
      ]

      for (title, entries) in sections where !entries.isEmpty {
        lines += ["\(title):", ""] + entries.map { "- \($0)" } + [""]
      }

      if let note, !note.isEmpty {
        lines += ["Contributor's note (for the maintainer; copied nowhere):", "", "> \(note)", ""]
      }
    }

    return String(trimmingTrailingWhitespace(lines.joined(separator: "\n"))) + "\n"
  }

  private func trimmingTrailingWhitespace(_ text: String) -> Substring {
    var scalars = text.unicodeScalars[...]

    while let last = scalars.last, last.isPythonWhitespace {
      scalars = scalars.dropLast()
    }

    return Substring(scalars)
  }
}

/// What drafting made of a set of files: the report and each file's note.
public struct DraftedFiles: Equatable, Sendable {
  public let report: IngestReport
  /// The contributor's notes, in the order of the files.
  public let notes: [String?]

  /// The report as Markdown for the maintainer.
  public var markdown: String {
    report.markdown(notes: notes)
  }
}

/// Drafts observation files against the catalog.
public enum ReportDrafting {
  /// The report for observation files, and the contributors' notes in the same order.
  ///
  /// The catalog given is not changed; each file sees the marks the files before it drafted.
  public static func draft(_ files: [URL], in catalog: ProfileCatalog) -> DraftedFiles {
    var working = catalog
    let models = Set(catalog.profiles.keys)
    var observations: [ObservationDraft] = []
    var notes: [String?] = []

    for (offset, file) in files.enumerated() {
      let label = ObservationFile.label(position: offset + 1, of: file)
      let errors: [String]

      switch ObservationFile.load(file) {
      case .loaded(let data):
        errors = ObservationCheck.problems(in: data, models: models)

        if errors.isEmpty {
          observations.append(ObservationDrafting.draft(data, in: &working, label: label))
          notes.append(data.text("note"))
          continue
        }
      case .rejected(let reasons):
        errors = reasons
      }

      var rejected = ObservationDraft(label: label)
      rejected.outcome = .rejected
      rejected.errors = errors
      observations.append(rejected)
      notes.append(nil)
    }

    return DraftedFiles(report: IngestReport(observations: observations), notes: notes)
  }
}
