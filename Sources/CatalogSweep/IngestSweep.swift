import CatalogBuild
import CatalogIngest
import CatalogJSON
import Foundation

/// One round of the ingestion sweep: the files made and where the two tools differ.
public struct IngestRoundResult: Sendable {
  public let round: Int
  /// What was made for each file of the round.
  public let files: [String]
  /// How the two tools differ, as one text each. Empty when they agree.
  public let differences: [String]
  /// Runs whose only difference is the line and column in a JSON error message.
  public let positionOnly: Int
  /// How many runs of the two tools were compared.
  public let compared: Int
}

/// Runs the Python and the Swift ingestion tools on observation files made from the catalog and
/// broken in many ways, and compares their exit status, output and reports.
///
/// Transitional: `scripts/ingest.py` is the oracle while the Python ingestion exists.
public struct IngestSweep: Sendable {
  public let repository: URL
  /// The folder with `observations/` and the frozen catalogs, for the fixtures and the apply cases.
  public let golden: URL
  public let oracle: any IngestRunning
  public let subject: any IngestRunning
  public let seed: UInt64
  public let filesPerRound: Int
  /// Compare `apply` on every Nth round that drafted something; 0 for never.
  public let applyEvery: Int
  /// Whether round 0 also runs every apply case on both tools.
  public let applyCases: Bool

  public init(
    repository: URL, golden: URL, oracle: any IngestRunning, subject: any IngestRunning = SwiftIngestRunner(), seed: UInt64 = 1,
    filesPerRound: Int = 12, applyEvery: Int = 3, applyCases: Bool = true
  ) {
    self.repository = repository
    self.golden = golden
    self.oracle = oracle
    self.subject = subject
    self.seed = seed
    self.filesPerRound = filesPerRound
    self.applyEvery = applyEvery
    self.applyCases = applyCases
  }

  /// Runs round 0, which compares the fixtures and the apply cases, then rounds `1...rounds`.
  public func run(rounds: Int, report: (IngestRoundResult) -> Void) throws {
    let root = try PageSweep.temporaryCopy(of: repository)
    defer { try? FileManager.default.removeItem(at: root) }

    let fixtures = golden.appendingPathComponent("observations")
    let book = IngestCaseBook(fixtures: fixtures)
    let catalog = try ProfileCatalog.load(from: RepositoryRoot(url: root))
    let names = ["dimmer-plug-2457D2", "example-invented-product", "io-module-2450", "on-off-plug-2635-222", "silent-sensor"]
    let raw = try names.map { IngestInput.bytes(Array(try Data(contentsOf: fixtures.appendingPathComponent($0 + ".json")))) }
    let compare = Comparer(root: root, oracle: oracle, subject: subject)

    var first = try compare.runs([("check", raw), ("draft", raw)] + raw.map { ("draft", [$0]) })

    if applyCases {
      first.differences += try applyCaseDifferences(&first.compared)
    }

    report(IngestRoundResult(round: 0, files: names, differences: first.differences, positionOnly: first.positionOnly, compared: first.compared))

    let mutator = ObservationMutator(catalog: catalog, example: try book.fixture("example-invented-product.json"))

    for round in 1...max(rounds, 1) where rounds > 0 {
      var random = SplitMix64(seed: seed &+ UInt64(round) &* 0x1_0000_0001)
      let generated = mutator.generate(filesPerRound, using: &random)
      let inputs = generated.map(\.input)
      var result = try compare.runs([("check", inputs), ("draft", inputs)])

      if applyEvery > 0, round % applyEvery == 0, let reportText = result.pythonReport, result.pythonReport?.contains("\"outcome\": \"drafted\"") == true {
        let edited = tampered(reportText, using: &random)
        result.differences += try applyDifferences(report: edited.text).map { "apply (\(edited.description)): \($0)" }
        result.compared += 1
      }

      report(IngestRoundResult(
        round: round, files: generated.map(\.description), differences: result.differences, positionOnly: result.positionOnly, compared: result.compared
      ))
    }
  }

  // MARK: apply

  private struct Edited {
    let text: String
    let description: String
  }

  /// The report, sometimes changed the way a hand edit or a stale report would change it.
  private func tampered(_ text: String, using random: inout SplitMix64) -> Edited {
    guard Int.random(in: 0..<10, using: &random) < 4, let value = try? JSONParser.parse(text) else { return Edited(text: text, description: "as drafted") }

    let observations = value["observations"]?.elements ?? []
    let drafted = observations.enumerated().filter { !($0.element["changes"]?.elements ?? []).isEmpty }
    guard let (position, observation) = drafted.randomElement(using: &random) else { return Edited(text: text, description: "as drafted") }

    let changeIndex = Int.random(in: 0..<(observation["changes"]?.elements.count ?? 1), using: &random)
    let base: JSONPath = [.key("observations"), .index(position), .key("changes"), .index(changeIndex)]
    let edits: [(String, JSONPath, JSONValue?)] = [
      ("status documented", base + [.key("after"), .key("status")], .string("documented")),
      ("note with a dash", base + [.key("after"), .key("note")], .string("Seen on a device running firmware 0x41: invented \u{2014} dash.")),
      ("free note", base + [.key("after"), .key("note")], .string("Anything at all.")),
      ("no firmware", base + [.key("after"), .key("firmware")], .array([])),
      ("other field", base + [.key("field")], .string("productKey")),
      ("other file", base + [.key("file")], .string("devices/../README.md")),
      ("selector without a subcategory", base + [.key("selector"), .key("subcategory")], nil),
      ("another before", base + [.key("before")], .object([JSONMember(key: "status", value: .string("inferred")), JSONMember(key: "note", value: .string("x"))])),
      ("another firmware byte", base + [.key("after"), .key("firmware")], .array([.string("0x00")])),
      ("rejected observation", [.key("observations"), .index(observations.count)], .object([JSONMember(key: "outcome", value: .string("rejected"))]))
    ]
    let (description, path, replacement) = edits[Int.random(in: 0..<edits.count, using: &random)]
    let changed = value.putting(path, replacement)

    return Edited(text: ((try? JSONWriter.write(changed)) ?? text) + "\n", description: description)
  }

  /// Applies a report to a copy of the repository with each tool and compares what they leave.
  private func applyDifferences(report: String) throws -> [String] {
    var snapshots: [(name: String, golden: IngestGolden)] = []

    for (name, runner) in [("Python", oracle), ("Swift", subject)] as [(String, any IngestRunning)] {
      let root = try PageSweep.temporaryCopy(of: repository)
      defer { try? FileManager.default.removeItem(at: root) }

      try? FileManager.default.copyItem(at: repository.appendingPathComponent(".gitignore"), to: root.appendingPathComponent(".gitignore"))
      try IngestGit.initialize(root)
      let file = root.deletingLastPathComponent().appendingPathComponent("sweep-report-\(UUID().uuidString).json")
      try Data(report.utf8).write(to: file)
      defer { try? FileManager.default.removeItem(at: file) }

      let run = try runner.run(["apply", file.path], in: root)
      snapshots.append((name, try PreparedApplyCase.golden(after: run, in: root)))
    }

    return Self.describe(snapshots[0].golden, snapshots[1].golden)
  }

  /// Runs every apply case on a copy of the repository with each tool, on the frozen catalog.
  private func applyCaseDifferences(_ compared: inout Int) throws -> [String] {
    var differences: [String] = []
    let catalogs = golden.appendingPathComponent("catalogs")
    let drafted = IngestCapture.reader(golden)

    for applyCase in ApplyCaseBook.cases {
      var goldens: [IngestGolden] = []

      for runner in [oracle, subject] {
        guard let prepared = try applyCase.prepare(catalogs: catalogs, repository: repository, drafted: drafted) else { continue }
        var run = try runner.run(["apply", prepared.report.path], in: prepared.root)

        if prepared.appliesTwice {
          try prepared.commitChanges()
          run = try runner.run(["apply", prepared.report.path], in: prepared.root)
        }

        goldens.append(try prepared.golden(after: run))
      }

      compared += 1
      differences += Self.describe(goldens[0], goldens[1]).map { "\(applyCase.name): \($0)" }
    }

    return differences
  }

  /// How two outcomes differ, part by part, where the first is the Python tool's.
  static func describe(_ python: IngestGolden, _ swift: IngestGolden) -> [String] {
    var found: [String] = []

    if python.parts.map(\.name) != swift.parts.map(\.name) {
      found.append("parts differ: Python \(python.parts.map(\.name)), Swift \(swift.parts.map(\.name))")
    }

    for part in python.parts where swift[part.name] != part.text {
      found.append("\(part.name) differs:\n    Python: \(part.text.prefix(600))\n    Swift:  \((swift[part.name] ?? "(none)").prefix(600))")
    }

    return found
  }

  // MARK: comparing one command

  /// Runs commands on both tools in one root and compares them.
  struct Comparer {
    let root: URL
    let oracle: any IngestRunning
    let subject: any IngestRunning

    struct Totals {
      var differences: [String] = []
      var positionOnly = 0
      var compared = 0
      var pythonReport: String?
    }

    func runs(_ commands: [(String, [IngestInput])]) throws -> Totals {
      var totals = Totals()

      for (command, inputs) in commands {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("ingest-sweep-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: work) }
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        var paths: [String] = []
        for (position, input) in inputs.enumerated() {
          let path = work.appendingPathComponent("input-\(position + 1).json")
          paths.append(path.path)
          if case .bytes(let bytes) = input { try Data(bytes).write(to: path) }
        }

        var outcomes: [IngestGolden] = []

        for (name, runner) in [("python", oracle), ("swift", subject)] as [(String, any IngestRunning)] {
          let out = work.appendingPathComponent(name)
          try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
          var arguments = [command] + paths

          if command == "draft" {
            arguments += ["--report", out.appendingPathComponent("report.json").path, "--md", out.appendingPathComponent("report.md").path]
          }

          let run = try runner.run(arguments, in: root)
          var golden = IngestGolden()
          golden.add("status", String(run.status))
          golden.add("stdout", run.standardOutput)

          for file in ["report.json", "report.md"] {
            if let data = try? Data(contentsOf: out.appendingPathComponent(file)) { golden.parts.append(.init(name: file, bytes: Array(data))) }
          }

          outcomes.append(golden)
        }

        totals.compared += 1
        totals.pythonReport = totals.pythonReport ?? outcomes[0]["report.json"]
        let found = IngestSweep.describe(outcomes[0], outcomes[1])

        if found.isEmpty { continue }

        if IngestSweep.normalized(outcomes[0]) == IngestSweep.normalized(outcomes[1]) {
          totals.positionOnly += 1
        } else {
          totals.differences.append("\(command) of \(inputs.count) files: " + found.joined(separator: "\n  "))
        }
      }

      return totals
    }
  }

  /// The parts with the line and column of a JSON error taken out.
  static func normalized(_ golden: IngestGolden) -> [String] {
    golden.parts.map { part in
      part.text.replacingOccurrences(of: #"\(line \d+, column \d+\)"#, with: "(line, column)", options: .regularExpression)
    }
  }
}
