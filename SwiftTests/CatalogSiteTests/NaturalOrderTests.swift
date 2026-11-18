import Testing

@testable import CatalogSite

/// Natural order compares digit runs as numbers and everything else in lower case, as the page's
/// model sort does, and keeps equal keys in their original order.
struct NaturalOrderTests {
  @Test(arguments: [
    (["2413U", "2477D", "2342-2", "2342"], ["2342", "2342-2", "2413U", "2477D"]),
    (["10", "9", "100", "1"], ["1", "9", "10", "100"]),
    (["B2", "a10", "a9", "A1"], ["A1", "a9", "a10", "B2"]),
    (["2842-222", "2842-2", "2842"], ["2842", "2842-2", "2842-222"]),
    (["1A", "1", "1-"], ["1", "1-", "1A"]),
    (["007", "7", "06", "6"], ["06", "6", "007", "7"]),
    (["99999999999999999999999", "100000000000000000000000", "9"], ["9", "99999999999999999999999", "100000000000000000000000"]),
    (["", "A", "0"], ["", "0", "A"])
  ])
  func sortsDigitRunsAsNumbers(models: [String], expected: [String]) {
    #expect(NaturalOrder.sorted(models) { $0 } == expected)
  }

  @Test func equalKeysKeepTheirOriginalOrder() {
    #expect(NaturalOrder.sorted(["B", "a", "A", "b"]) { $0 } == ["a", "A", "B", "b"])
    #expect(NaturalOrder.sorted(["07", "7", "007"]) { $0 } == ["07", "7", "007"])
  }

  @Test func sortsAnyElementByItsKey() {
    #expect(NaturalOrder.sorted([("x", "10"), ("y", "9")]) { $0.1 }.map(\.0) == ["y", "x"])
  }

  @Test func aLetterSortsAfterEveryDigitRunOfTheSamePrefixThatEndsEarlier() {
    // "2442" is [ "", 2442, "" ] and "2442-222" is [ "", 2442, "-", 222, "" ].
    #expect(NaturalOrder.sorted(["2442-222", "2442"]) { $0 } == ["2442", "2442-222"])
  }

  @Test func lowerCasesTheWayPythonDoes() {
    #expect(PythonCase.lowercased("ABC\u{3A3}") == "abc\u{3C2}")
    #expect(PythonCase.lowercased("ABC \u{3A3}") == "abc \u{3C3}")
    #expect(PythonCase.lowercased("\u{3A3}A") == "\u{3C3}a")
    #expect(PythonCase.lowercased("A\u{3A3}B") == "a\u{3C3}b")
    #expect(PythonCase.lowercased("\u{130}") == "i\u{307}")
    #expect(PythonCase.lowercased("Caf\u{C9}") == "caf\u{E9}")
  }
}
