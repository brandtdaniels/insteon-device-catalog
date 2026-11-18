import CatalogJSON

/// How far an observation gets: nothing to write, marks drafted, a decision left for a maintainer, or
/// the file refused.
public enum DraftOutcome: String, Equatable, Sendable {
  case noChange = "no-change"
  case drafted
  case needsHuman = "needs-human"
  case rejected
}

/// What an observation contradicts or can't decide.
public enum DisagreementCode: String, Equatable, Sendable {
  case firmwareNotCovered = "firmware-not-covered"
  case unknownDevice = "unknown-device"
  case ambiguous
  case engineDiffers = "engine-differs"
  case keyNotInCatalog = "key-not-in-catalog"
  case keyNotReported = "key-not-reported"
  case keyDiffers = "key-differs"
  case conflictingNotOverwritten = "conflicting-not-overwritten"
}

/// The kind of profile entry a change marks.
public enum EntryKind: String, Equatable, Sendable {
  case identity
  case engine
}

/// The field of an entry a change sets.
public enum VerificationField: String, Equatable, Sendable {
  case verification
  case productKeyVerification
}

/// A verification mark drafting proposes for one entry of one profile.
public struct ProposedChange: Equatable, Sendable {
  /// The profile file, such as `devices/2450.json`.
  public let file: String
  public let model: String
  public let entry: EntryKind
  /// The entry's `engine`, `category`, `subcategory` and `firmware`, as far as it has them.
  public let selector: JSONValue
  public let field: VerificationField
  /// What the field holds, or `nil` when it holds nothing.
  public let before: JSONValue?
  public let after: JSONValue
  public let effect: String
  public let target: String

  var json: JSONValue {
    .object([
      JSONMember(key: "file", value: .string(file)),
      JSONMember(key: "model", value: .string(model)),
      JSONMember(key: "entry", value: .string(entry.rawValue)),
      JSONMember(key: "selector", value: selector),
      JSONMember(key: "field", value: .string(field.rawValue)),
      JSONMember(key: "before", value: before ?? .null),
      JSONMember(key: "after", value: after),
      JSONMember(key: "effect", value: .string(effect)),
      JSONMember(key: "target", value: .string(target))
    ])
  }
}

/// The profile and identity an observation matched.
public struct ProfileMatch: Equatable, Sendable {
  public let model: String
  public let category: String
  public let subcategory: String

  public init(model: String, category: String, subcategory: String) {
    self.model = model
    self.category = category
    self.subcategory = subcategory
  }
}

/// Something the catalog records that an observation agrees with already.
public struct UnchangedTarget: Equatable, Sendable {
  public let target: String
  public let reason: String
}

/// A disagreement and what it asks of a maintainer.
public struct Disagreement: Equatable, Sendable {
  public let code: DisagreementCode
  public let detail: String
  public let needs: String
}

/// A check the draft did not use, and why.
public struct SkippedCheck: Equatable, Sendable {
  public let check: String
  public let reason: String

  public init(check: String, reason: String) {
    self.check = check
    self.reason = reason
  }
}

/// A value shown to the maintainer that is compared with nothing.
public struct ReportOnlyItem: Equatable, Sendable {
  public let item: String
  public let detail: String
}

/// What one observation file would change in the catalog, and what it contradicts.
public struct ObservationDraft: Equatable, Sendable {
  /// How the report names the file: `observation N (fingerprint)`.
  public let label: String
  public internal(set) var outcome: DraftOutcome = .noChange
  public internal(set) var matched: ProfileMatch?
  public internal(set) var changes: [ProposedChange] = []
  public internal(set) var unchanged: [UnchangedTarget] = []
  public internal(set) var disagreements: [Disagreement] = []
  public internal(set) var skipped: [SkippedCheck] = []
  public internal(set) var reportOnly: [ReportOnlyItem] = []
  public internal(set) var warnings: [String] = []
  public internal(set) var errors: [String] = []

  init(label: String) {
    self.label = label
  }

  /// The report's entry for the file, with its members in the order the report lists them.
  public var json: JSONValue {
    let matchValue: JSONValue = matched.map {
      .object([
        JSONMember(key: "model", value: .string($0.model)),
        JSONMember(key: "identity", value: .object([
          JSONMember(key: "category", value: .string($0.category)),
          JSONMember(key: "subcategory", value: .string($0.subcategory))
        ]))
      ])
    } ?? .null

    func pairs(_ first: String, _ second: String, _ rows: [(String, String)]) -> JSONValue {
      .array(rows.map { .object([JSONMember(key: first, value: .string($0.0)), JSONMember(key: second, value: .string($0.1))]) })
    }

    return .object([
      JSONMember(key: "input", value: .string(label)),
      JSONMember(key: "outcome", value: .string(outcome.rawValue)),
      JSONMember(key: "matched", value: matchValue),
      JSONMember(key: "changes", value: .array(changes.map(\.json))),
      JSONMember(key: "unchanged", value: pairs("target", "reason", unchanged.map { ($0.target, $0.reason) })),
      JSONMember(key: "disagreements", value: .array(disagreements.map {
        .object([
          JSONMember(key: "code", value: .string($0.code.rawValue)),
          JSONMember(key: "detail", value: .string($0.detail)),
          JSONMember(key: "needs", value: .string($0.needs))
        ])
      })),
      JSONMember(key: "skipped", value: pairs("check", "reason", skipped.map { ($0.check, $0.reason) })),
      JSONMember(key: "reportOnly", value: pairs("item", "detail", reportOnly.map { ($0.item, $0.detail) })),
      JSONMember(key: "warnings", value: .array(warnings.map(JSONValue.string))),
      JSONMember(key: "errors", value: .array(errors.map(JSONValue.string)))
    ])
  }
}
