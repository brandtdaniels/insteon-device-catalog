import CatalogJSON
import Foundation

/// A throwaway folder that holds a case's files, removed when it goes away.
public final class IngestWorkspace: Sendable {
  /// What the Python tool reads besides the catalog.
  public static let pythonReads = ["scripts", "schema", "commandSets", "documents", "templates", "VERSION"]

  public let url: URL

  public init() throws {
    url = FileManager.default.temporaryDirectory.appendingPathComponent("ingest-case-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  deinit {
    try? FileManager.default.removeItem(at: url)
  }
}

/// An ingestion case laid out on disk: the root the tool reads, the files it is given and where its
/// report goes.
public struct PreparedIngestCase: Sendable {
  public let workspace: IngestWorkspace
  /// The root: `devices/` with the case's catalog, and `scripts/` when the Python tool runs.
  public let root: URL
  /// The input paths in order; a missing input's path names no file.
  public let inputs: [URL]
  public let report: URL?
  public let markdown: URL?
  public let action: IngestAction

  /// The command line the tool takes, after its name.
  public var arguments: [String] {
    switch action {
    case .check:
      return ["check"] + inputs.map(\.path)
    case .draft:
      return ["draft"] + inputs.map(\.path) + (report.map { ["--report", $0.path] } ?? []) + (markdown.map { ["--md", $0.path] } ?? [])
    }
  }

  /// What the run left: its status and output, and the report and Markdown it wrote.
  public func golden(after run: IngestRun) -> IngestGolden {
    var golden = IngestGolden()
    golden.add("status", String(run.status))
    golden.add("stdout", run.standardOutput)

    for (name, url) in [("report.json", report), ("report.md", markdown)] {
      if let url, let data = try? Data(contentsOf: url) { golden.parts.append(.init(name: name, bytes: Array(data))) }
    }

    return golden
  }
}

extension IngestCase {
  /// Writes the case's files under a new folder.
  ///
  /// - Parameters:
  ///   - catalog: The folder that holds `catalogs/real` and `catalogs/invented`.
  ///   - repository: What the Python tool reads besides the catalog: its scripts, schemas, command sets, documents and
  ///     VERSION, copied from here. `nil` for the catalog alone.
  public func prepare(catalogs: URL, repository: URL? = nil) throws -> PreparedIngestCase {
    let workspace = try IngestWorkspace()
    let root = workspace.url.appendingPathComponent("root")
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    try fileManager.copyItem(at: catalogs.appendingPathComponent("\(catalog.rawValue)/devices"), to: root.appendingPathComponent("devices"))

    if let repository {
      for name in IngestWorkspace.pythonReads {
        try fileManager.copyItem(at: repository.appendingPathComponent(name), to: root.appendingPathComponent(name))
      }
    }

    let folder = workspace.url.appendingPathComponent("input")
    let out = workspace.url.appendingPathComponent("out")
    try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: out, withIntermediateDirectories: true)
    var paths: [URL] = []

    for (position, input) in inputs.enumerated() {
      let path = folder.appendingPathComponent("input-\(position + 1).json")
      paths.append(path)

      if case .bytes(let bytes) = input {
        try Data(bytes).write(to: path)
      }
    }

    var report: URL?
    var markdown: URL?

    if case .draft(let wantsReport, let wantsMarkdown) = action {
      report = wantsReport ? out.appendingPathComponent("report.json") : nil
      markdown = wantsMarkdown ? out.appendingPathComponent("report.md") : nil
    }

    return PreparedIngestCase(workspace: workspace, root: root, inputs: paths, report: report, markdown: markdown, action: action)
  }
}

// MARK: apply

/// One change to a JSON document: set a value, add one or remove one.
public struct IngestEdit: Equatable, Sendable {
  public let path: JSONPath
  public let value: JSONValue?

  public init(_ path: JSONPath, _ value: JSONValue?) {
    self.path = path
    self.value = value
  }
}

/// Where an apply case gets the report it hands to `apply`.
public enum ApplyReportSource: Equatable, Sendable {
  /// The report a draft case wrote, by the draft case's name.
  case drafted(String)
  case text(String)
  case missing
}

/// One run of `apply` on a copy of the three real profiles in a git repository.
public struct ApplyCase: Sendable {
  public let name: String
  public let report: ApplyReportSource
  public let reportEdits: [IngestEdit]
  /// Edits to a profile before the repository's first commit, by path such as `devices/2450.json`.
  public let catalogEdits: [(file: String, edit: IngestEdit)]
  /// Files left untracked before `apply` runs.
  public let untracked: [String]
  public let reportInsideRoot: Bool
  /// Whether the case applies, commits and applies again; its result is the second run's.
  public let appliesTwice: Bool
  /// Whether the build fails after the files are written; the case's change breaks a rule.
  public let buildFails: Bool

  public init(
    name: String, report: ApplyReportSource = .drafted("draft-bench-four"), reportEdits: [IngestEdit] = [],
    catalogEdits: [(file: String, edit: IngestEdit)] = [], untracked: [String] = [], reportInsideRoot: Bool = false,
    appliesTwice: Bool = false, buildFails: Bool = false
  ) {
    self.name = name
    self.report = report
    self.reportEdits = reportEdits
    self.catalogEdits = catalogEdits
    self.untracked = untracked
    self.reportInsideRoot = reportInsideRoot
    self.appliesTwice = appliesTwice
    self.buildFails = buildFails
  }

  /// The report text the case hands to `apply`, or `nil` when it hands none.
  func reportBytes(drafted: (String) throws -> [UInt8]) throws -> [UInt8]? {
    switch report {
    case .missing:
      return nil
    case .text(let text):
      return Array(text.utf8)
    case .drafted(let name):
      var value = try JSONParser.parse(try drafted(name))
      for edit in reportEdits { value = value.putting(edit.path, edit.value) }

      return Array((try JSONWriter.write(value) + "\n").utf8)
    }
  }
}

/// An apply case laid out on disk in a git repository.
public struct PreparedApplyCase: Sendable {
  public let workspace: IngestWorkspace
  public let root: URL
  public let report: URL
  /// Writes the case's second state: commits what the first run changed.
  public let appliesTwice: Bool

  /// What `apply` left: its status and output, the tree's state and every changed file.
  public func golden(after run: IngestRun) throws -> IngestGolden {
    var golden = IngestGolden()
    golden.add("status", String(run.status))
    golden.add("stdout", run.standardOutput)
    golden.add("tree", try IngestGit.run(["status", "--porcelain"], in: root))

    for name in try IngestGit.run(["diff", "--name-only"], in: root).split(separator: "\n").map(String.init).sorted() {
      golden.parts.append(.init(name: "file \(name)", bytes: Array(try Data(contentsOf: root.appendingPathComponent(name)))))
    }

    return golden
  }

  /// Commits the working tree, so a second `apply` meets a catalog that holds the changes.
  public func commitChanges() throws {
    try IngestGit.commitAll("applied", in: root)
  }
}

extension ApplyCase {
  /// Writes the case's repository and report.
  ///
  /// - Parameters:
  ///   - catalogs: The folder that holds `catalogs/real`.
  ///   - repository: What the Python build reads from a full copy of the repository, or `nil` for the
  ///     profiles alone.
  ///   - drafted: The report a draft case wrote, by the case's name.
  public func prepare(catalogs: URL, repository: URL?, drafted: (String) throws -> [UInt8]) throws -> PreparedApplyCase? {
    let workspace = try IngestWorkspace()
    let root = workspace.url.appendingPathComponent("root")
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    try fileManager.copyItem(at: catalogs.appendingPathComponent("real/devices"), to: root.appendingPathComponent("devices"))

    if let repository {
      for name in IngestWorkspace.pythonReads + [".gitignore"] {
        try fileManager.copyItem(at: repository.appendingPathComponent(name), to: root.appendingPathComponent(name))
      }
    }

    for (file, edit) in catalogEdits {
      let url = root.appendingPathComponent(file)
      guard let data = try? Data(contentsOf: url) else { continue }
      let value = try JSONParser.parse(Array(data)).putting(edit.path, edit.value)
      try Data((try JSONWriter.write(value) + "\n").utf8).write(to: url)
    }

    try IngestGit.initialize(root)

    for path in untracked {
      try Data("x".utf8).write(to: root.appendingPathComponent(path))
    }

    let reportURL = reportInsideRoot ? root.appendingPathComponent("report.json") : workspace.url.appendingPathComponent("report.json")

    if let bytes = try reportBytes(drafted: drafted) {
      try Data(bytes).write(to: reportURL)
    }

    return PreparedApplyCase(workspace: workspace, root: root, report: reportURL, appliesTwice: appliesTwice)
  }
}

/// The apply cases the goldens and the comparisons share.
public enum ApplyCaseBook {
  static let change: JSONPath = [.key("observations"), .index(1), .key("changes"), .index(0)]

  static func tamper(_ name: String, _ path: JSONPath, _ value: JSONValue?) -> ApplyCase {
    ApplyCase(name: "apply-a-tampered-report-\(name)", reportEdits: [IngestEdit(change + path, value)])
  }

  static let observedEngine = JSONValue.object([
    JSONMember(key: "status", value: .string("observed")),
    JSONMember(key: "note", value: .string("Seen on a device running firmware 0x10: invented.")),
    JSONMember(key: "firmware", value: .array([.string("0x10")]))
  ])

  public static var cases: [ApplyCase] {
    [
      ApplyCase(name: "apply-the-bench-report"),
      ApplyCase(name: "apply-the-bench-report-twice", appliesTwice: true),
      ApplyCase(name: "apply-with-an-untracked-file", untracked: ["notes.txt"]),
      ApplyCase(name: "apply-with-the-report-in-the-tree", reportInsideRoot: true),
      ApplyCase(name: "apply-with-the-report-in-the-tree-and-another-file", untracked: ["notes.txt"], reportInsideRoot: true),
      ApplyCase(name: "apply-to-a-catalog-that-moved", catalogEdits: [("devices/2450.json", IngestEdit([.key("engines"), .index(0), .key("verification")], observedEngine))]),
      ApplyCase(name: "apply-to-a-catalog-where-only-one-file-moved", catalogEdits: [("devices/2635-222.json", IngestEdit([.key("engines"), .index(0), .key("verification")], observedEngine))]),
      ApplyCase(name: "apply-to-a-catalog-without-the-entry", catalogEdits: [("devices/2450.json", IngestEdit([.key("engines"), .index(0), .key("subcategory")], .string("0x7F")))]),
      ApplyCase(name: "apply-to-a-catalog-where-the-mark-is-there", catalogEdits: [("devices/2450.json", IngestEdit([.key("engines"), .index(0), .key("verification")], .object([
        JSONMember(key: "status", value: .string("observed")),
        JSONMember(key: "note", value: .string("Seen on a device running firmware 0x41: Get Insteon Engine Version answered with i2CS.")),
        JSONMember(key: "firmware", value: .array([.string("0x41")]))
      ])))]),
      ApplyCase(name: "apply-nothing-drafted", report: .drafted("draft-silent-sensor")),
      ApplyCase(name: "apply-a-report-with-a-rejected-observation", reportEdits: [IngestEdit([.key("observations"), .index(4)], .object([
        JSONMember(key: "input", value: .string("observation 5 (00000000)")),
        JSONMember(key: "outcome", value: .string("rejected")),
        JSONMember(key: "errors", value: .array([.string("x")])),
        JSONMember(key: "changes", value: .array([]))
      ]))]),
      ApplyCase(name: "apply-a-report-of-another-format", reportEdits: [IngestEdit([.key("format")], .string("other"))]),
      ApplyCase(name: "apply-a-report-of-another-lane", reportEdits: [IngestEdit([.key("lane")], .string("other"))]),
      ApplyCase(name: "apply-a-report-without-observations", reportEdits: [IngestEdit([.key("observations")], .string("none"))]),
      ApplyCase(name: "apply-a-report-that-is-a-list", report: .text("[]")),
      ApplyCase(name: "apply-a-report-that-is-not-json", report: .text("not json")),
      ApplyCase(name: "apply-an-empty-report", report: .text("")),
      ApplyCase(name: "apply-a-report-that-is-not-utf-8", report: .text("\u{FFFD}")),
      ApplyCase(name: "apply-a-missing-report", report: .missing),
      ApplyCase(name: "apply-a-report-whose-observations-are-not-objects", reportEdits: [IngestEdit([.key("observations")], .array([.int(1), .string("x")]))]),
      ApplyCase(name: "apply-a-report-whose-changes-are-not-a-list", reportEdits: [IngestEdit([.key("observations"), .index(1), .key("changes")], .string("x"))]),
      ApplyCase(name: "apply-a-change-that-is-not-an-object", reportEdits: [IngestEdit(change, .int(5))]),
      tamper("status", [.key("after"), .key("status")], .string("documented")),
      tamper("extra-field", [.key("after"), .key("value")], .string("0x01")),
      tamper("free-note", [.key("after"), .key("note")], .string("Anything at all.")),
      tamper("note-with-a-line-break", [.key("after"), .key("note")], .string("Seen on a device running firmware 0x41: one\ntwo")),
      tamper("note-of-another-firmware-shape", [.key("after"), .key("note")], .string("Seen on a device running firmware 0x4: x")),
      tamper("no-firmware", [.key("after"), .key("firmware")], .array([])),
      tamper("firmware-not-a-byte", [.key("after"), .key("firmware")], .array([.string("0x4")])),
      tamper("firmware-a-number", [.key("after"), .key("firmware")], .array([.int(65)])),
      tamper("after-is-null", [.key("after")], .null),
      tamper("other-field", [.key("field")], .string("productKey")),
      tamper("key-verification-of-an-engine", [.key("field")], .string("productKeyVerification")),
      tamper("other-file", [.key("file")], .string("devices/../README.md")),
      tamper("other-model", [.key("file")], .string("devices/2635-222.json")),
      tamper("other-entry", [.key("entry")], .string("commandSet")),
      tamper("selector-with-another-key", [.key("selector")], .object([
        JSONMember(key: "category", value: .string("0x07")), JSONMember(key: "subcategory", value: .string("0x00")), JSONMember(key: "name", value: .string("x"))
      ])),
      tamper("selector-without-a-subcategory", [.key("selector"), .key("subcategory")], nil),
      tamper("selector-that-is-a-list", [.key("selector")], .array([])),
      tamper("an-identity-selector-with-an-engine", [.key("entry")], .string("identity")),
      ApplyCase(
        name: "apply-a-change-the-build-refuses",
        reportEdits: [IngestEdit(change + [.key("after"), .key("note")], .string("Seen on a device running firmware 0x41: invented \u{2014} dash."))],
        buildFails: true
      )
    ]
  }
}
