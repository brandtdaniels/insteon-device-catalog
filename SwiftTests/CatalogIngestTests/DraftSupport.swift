import CatalogIngest
import CatalogJSON

/// A profile with only what drafting reads.
func profile(_ model: String, identities: String, engines: String? = nil) -> JSONValue {
  var members = [
    JSONMember(key: "model", value: .string(model)),
    JSONMember(key: "name", value: .string("Invented \(model)")),
    JSONMember(key: "identities", value: json(identities))
  ]

  if let engines { members.append(JSONMember(key: "engines", value: json(engines))) }

  return .object(members)
}

func observed(_ firmware: [String], note: String = "Seen on a device running firmware 0x00: invented.") -> String {
  #"{"status": "observed", "note": "\#(note)", "firmware": [\#(firmware.map { "\"\($0)\"" }.joined(separator: ", "))]}"#
}

/// Profiles in the states the four bench files meet: already observed, partly observed and unmarked.
func benchCatalog() -> ProfileCatalog {
  ProfileCatalog(profiles: [
    "2457D2": profile(
      "2457D2",
      identities: """
        [{"category": "0x01", "subcategory": "0x0E", "productKey": "0x00004B",
          "productKeyVerification": {"status": "inferred", "note": "Read from a shared identity."},
          "verification": \(observed(["0x3B"]))}]
        """,
      engines: """
        [{"engine": "i2cs", "category": "0x01", "subcategory": "0x0E", "firmware": {"only": ["0x41"]}},
         {"engine": "i2", "category": "0x01", "subcategory": "0x0E", "firmware": {"only": ["0x3B"]}, "verification": \(observed(["0x3B"]))}]
        """
    ),
    "2450": profile(
      "2450",
      identities: #"[{"category": "0x07", "subcategory": "0x00", "productKey": "0x00001A", "verification": \#(observed(["0x41"]))}]"#,
      engines: #"[{"engine": "i2cs", "category": "0x07", "subcategory": "0x00", "firmware": {"only": ["0x40", "0x41"]}}]"#
    ),
    "2635-222": profile(
      "2635-222",
      identities: #"[{"category": "0x02", "subcategory": "0x37"}]"#,
      engines: #"[{"engine": "i2cs", "category": "0x02", "subcategory": "0x37"}]"#
    )
  ])
}

/// The invented example observation with the device's fields replaced, as the tests draft it.
func observation(_ device: [String: JSONValue] = [:]) -> JSONValue {
  var data = Fixtures.bench("example-invented-product.json")

  for (key, value) in device { data = data.setting(["device", key], to: value) }

  return data
    .setting("checks", to: json("""
      [{"name": "Get Insteon Engine Version", "outcome": "answered", "detail": "x"},
       {"name": "ID Request", "outcome": "answered", "detail": "x"},
       {"name": "Product Data Request", "outcome": "answered", "detail": "x"}]
      """))
    .setting("productKey", to: .string("0x00001A"))
    .setting("operatingFlags", to: nil)
}

/// A catalog with one invented product at 0x7E/0x7F, whose identity and engine entries the test chooses.
func inventedCatalog(identity: String = #"{"category": "0x7E", "subcategory": "0x7F", "productKey": "0x00001A"}"#, engines: String? = nil) -> ProfileCatalog {
  ProfileCatalog(profiles: [
    "9999": profile(
      "9999",
      identities: "[\(identity)]",
      engines: engines ?? #"[{"engine": "i2cs", "category": "0x7E", "subcategory": "0x7F"}]"#
    )
  ])
}

func draft(_ data: JSONValue, _ catalog: ProfileCatalog) -> ObservationDraft {
  var working = catalog

  return ObservationDrafting.draft(data, in: &working)
}

func codes(_ result: ObservationDraft) -> [String] {
  result.disagreements.map(\.code.rawValue)
}

func changed(_ result: ObservationDraft) -> [String] {
  result.changes.map { "\($0.entry.rawValue) \($0.field.rawValue) \($0.effect)" }
}

func change(_ result: ObservationDraft, entry: String, field: String = "verification") -> ProposedChange? {
  result.changes.first { $0.entry.rawValue == entry && $0.field.rawValue == field }
}
