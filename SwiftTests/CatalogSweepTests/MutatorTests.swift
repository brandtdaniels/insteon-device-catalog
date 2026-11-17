import CatalogJSON
import CatalogSweep
import Testing

/// The mutations the sweep makes are chosen by a seed and change one thing.
struct MutatorTests {
  static let sample: JSONValue = {
    do {
      return try JSONParser.parse(#"""
      {"id": "one", "name": "alpha", "flag": true, "count": 3, "byte": "0x2E",
       "list": [{"name": "a", "effect": "readOnly"}, {"name": "b", "effect": "actuation"}],
       "note": "prose"}
      """#)
    } catch {
      fatalError("\(error)")
    }
  }()

  static let mutator = Mutator(pool: ValuePool(files: [sample]))

  @Test func theSameSeedMakesTheSameMutations() {
    func run(seed: UInt64) -> [String] {
      var random = SplitMix64(seed: seed)
      return (0..<20).compactMap { _ in Self.mutator.mutate(Self.sample, name: "x.json", using: &random)?.applied.description }
    }

    #expect(run(seed: 7) == run(seed: 7))
    #expect(run(seed: 7) != run(seed: 8))
  }

  @Test func theGeneratorHasKnownOutputs() {
    var random = SplitMix64(seed: 1)

    #expect(random.next() == 0x910A_2DEC_8902_5CC1)
    #expect(random.next() == 0xBEEB_8DA1_658E_EC67)
  }

  @Test func everyMutationChangesTheFile() {
    var random = SplitMix64(seed: 3)

    for _ in 0..<200 {
      guard let (changed, _) = Self.mutator.mutate(Self.sample, name: "x.json", using: &random) else { continue }
      #expect(changed != Self.sample)
    }
  }

  @Test func everyKindOfMutationIsMadeSomewhere() {
    var random = SplitMix64(seed: 5)
    var seen = Set<MutationKind>()

    for _ in 0..<2000 {
      if let (_, applied) = Self.mutator.mutate(Self.sample, name: "x.json", using: &random) {
        seen.insert(applied.kind)
      }
    }

    #expect(seen == Set(MutationKind.allCases))
  }

  @Test func proseIsNeverChanged() {
    var random = SplitMix64(seed: 9)

    for _ in 0..<500 {
      guard let (changed, applied) = Self.mutator.mutate(Self.sample, name: "x.json", using: &random),
            applied.kind == .crossValue || applied.kind == .renameName
      else { continue }
      #expect(changed["note"] == Self.sample["note"])
    }
  }
}

extension JSONValue {
  fileprivate subscript(key: String) -> JSONValue? {
    guard case .object(let members) = self else { return nil }
    return members.first { $0.key == key }?.value
  }
}
