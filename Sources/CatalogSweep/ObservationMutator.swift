import CatalogIngest
import CatalogJSON
import Foundation

/// Makes observation files from the catalog's own profiles and then breaks them, to compare how two
/// ingestion tools read them.
public struct ObservationMutator: Sendable {
  let catalog: ProfileCatalog
  let example: ObservationBuilder

  public init(catalog: ProfileCatalog, example: ObservationBuilder) {
    self.catalog = catalog
    self.example = example
  }

  /// One generated file and what was done to make it.
  public struct Generated: Sendable {
    public let description: String
    public let input: IngestInput
  }

  static let notes = [
    "Fresh battery, device on the bench.", "Seen on a device running firmware 0x34, key 0x00001A.", "Tested at 12:30 with a decade of use.",
    "I/O Module 2450 (I/O Linc)", "It reported 2A 00.", "On the bench next to 2F.9A.C1 here.", "Next to 2F9AC1.", "Label reads SN12345678 on the back.",
    "At 192.168.7.20 and fe80::1:2:3:4.", "Hub at hub.example.com, mail someone@example.test.", "Saved in /Users/someone/notes.txt",
    "Line one.\nLine two.  ", "Caf\u{00E9} \u{1F600} bench.", "a4:5e:60:11:22:33", "Version 1.2.3 of the app.", "key 0x00001A or 001122", ""
  ]
  static let checkNames = ["Get Insteon Engine Version", "ID Request", "Product Data Request", "Status Request", "Get Operating Flags"]
  static let outcomes = ["answered", "answered", "answered", "silent", "refused"]

  /// Generates `count` files from the seeded random source.
  public func generate(_ count: Int, using random: inout SplitMix64) -> [Generated] {
    (0..<count).map { _ in one(using: &random) }
  }

  private func one(using random: inout SplitMix64) -> Generated {
    let models = catalog.profiles.keys.sorted()
    let model = models.randomElement(using: &random) ?? ""
    let profile = catalog.profiles[model] ?? .null
    let identities = profile["identities"]?.elements ?? []
    let identity = identities.randomElement(using: &random) ?? .null
    var builder = example
    var steps = ["from \(model)"]

    let category = identity["category"]?.string ?? "0x00", subcategory = identity["subcategory"]?.string ?? "0x00"
    builder = builder.device("category", category).device("subcategory", subcategory)

    let range = firmwareRange(identity)
    let firmware = [range.0, range.1, max(range.0 - 1, 0), min(range.1 + 1, 255), Int.random(in: 0...255, using: &random)].randomElement(using: &random) ?? 0
    builder = builder.device("firmware", Self.byte(firmware))
    steps.append("firmware \(Self.byte(firmware))")

    let engineEntry = (profile["engines"]?.elements ?? []).randomElement(using: &random)
    let engine = Bool.random(using: &random) ? (Self.label(engineEntry?["engine"]?.string) ?? "i2CS") : ["i1", "i2", "i2CS"].randomElement(using: &random) ?? "i2"
    builder = builder.device("engine", Bool.random(using: &random) || engineEntry == nil ? engine : nil)

    let names = [profile["name"]?.string ?? "", model, "Some Other Product 1234", "Item \(model) here"]
    builder = builder.device("model", Bool.random(using: &random) ? names.randomElement(using: &random) : nil)

    let recorded = identity["productKey"]?.string
    let keys: [String?] = [recorded, recorded, "none", nil, "0x000050", "0x00001A"]
    builder = builder.productKey(keys.randomElement(using: &random) ?? nil)

    builder = builder.checks(Self.checkNames.map { ($0, Self.outcomes.randomElement(using: &random) ?? "answered") })
    builder = builder.note(Self.notes.randomElement(using: &random) ?? "")
    if Bool.random(using: &random) { builder = builder.put([.key("note")], nil) }
    if Bool.random(using: &random) { builder = builder.put([.key("operatingFlags")], nil) }

    for _ in 0..<Int.random(in: 0...2, using: &random) {
      let (changed, step) = damage(builder, using: &random)
      builder = changed
      steps.append(step)
    }

    if Int.random(in: 0..<12, using: &random) == 0 {
      let (input, step) = bytesDamage(builder.bytes, using: &random)
      return Generated(description: (steps + [step]).joined(separator: ", "), input: input)
    }

    return Generated(description: steps.joined(separator: ", "), input: .bytes(builder.bytes))
  }

  private func damage(_ builder: ObservationBuilder, using random: inout SplitMix64) -> (ObservationBuilder, String) {
    let leak = Self.notes.randomElement(using: &random) ?? ""
    let position = Int.random(in: 0..<5, using: &random)

    switch Int.random(in: 0..<14, using: &random) {
    case 0: return (builder.put([.key("note")], .string(leak)), "note \(Self.shown(leak))")
    case 1: return (builder.detail(position % 2, leak), "detail \(Self.shown(leak))")
    case 2: return (builder.put([.key("tool"), .key("version")], .string(leak)), "tool version \(Self.shown(leak))")
    case 3: return (builder.device("model", leak), "model \(Self.shown(leak))")
    case 4: return (builder.put([.key("hubAddress")], .string(leak)), "extra field \(Self.shown(leak))")
    case 5: return (builder.put([.key("format")], .string(["insteon-observation/2", "other", "insteon-observation/"].randomElement(using: &random) ?? "")), "format changed")
    case 6: return (builder.put([.key(["observedOn", "tool", "catalog", "device", "checks", "format"].randomElement(using: &random) ?? "tool")], nil), "field removed")
    case 7: return (builder.put([.key("observedOn")], .string(["2026-13-45", "2026-02-30", "x", "2024-02-29"].randomElement(using: &random) ?? "")), "date changed")
    case 8: return (builder.put([.key("note")], .string(String(repeating: "a", count: [279, 280, 281].randomElement(using: &random) ?? 0))), "note length")
    case 9: return (builder.put([.key("checks")], .array(Array(repeating: builder.valueAt("checks", 0), count: [15, 16, 17].randomElement(using: &random) ?? 1))), "check count")
    case 10: return (builder.device(["category", "subcategory", "firmware"].randomElement(using: &random) ?? "category", ["7", "0x7", "0x3b", "0x07", "0xZZ"].randomElement(using: &random)), "identity byte changed")
    case 11: return (builder.device("engine", ["i4", "I2", "i2cs", "i1"].randomElement(using: &random)), "engine changed")
    case 12: return (builder.put([.key("checks"), .index(position % 3), .key("name")], .string(["Ping", "ID Request", "Status Request"].randomElement(using: &random) ?? "")), "check renamed")
    default: return (builder.put([.key("productKey")], .string(["0xZZZZZZ", "0x00001A", "none", "0x000050"].randomElement(using: &random) ?? "")), "key changed")
    }
  }

  private func bytesDamage(_ bytes: [UInt8], using random: inout SplitMix64) -> (IngestInput, String) {
    switch Int.random(in: 0..<5, using: &random) {
    case 0: return (.bytes([]), "file emptied")
    case 1: return (.bytes(Array(bytes.prefix(Int.random(in: 0..<max(bytes.count, 1), using: &random)))), "file cut short")
    case 2: return (.bytes(bytes + [0xFF]), "invalid UTF-8 added")
    case 3: return (.bytes(Array(bytes.dropLast(2)) + [0x2C, 0x7D]), "trailing comma")
    default: return (.missing, "file missing")
    }
  }

  private func firmwareRange(_ identity: JSONValue) -> (Int, Int) {
    guard let firmware = identity["firmware"], let low = firmware["from"]?.string, let high = firmware["through"]?.string else { return (0, 255) }

    return (Int(low.dropFirst(2), radix: 16) ?? 0, Int(high.dropFirst(2), radix: 16) ?? 255)
  }

  static func byte(_ value: Int) -> String {
    "0x" + String(format: "%02X", value)
  }

  private static func label(_ engine: String?) -> String? {
    engine.map { ["i2cs": "i2CS"][$0] ?? $0 }
  }

  /// A leak shortened for a description, which is never printed with the leaked text of a real file.
  private static func shown(_ text: String) -> String {
    text.count > 24 ? String(text.prefix(24)) + "..." : text
  }
}
