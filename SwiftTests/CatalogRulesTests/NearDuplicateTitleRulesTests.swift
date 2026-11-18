import CatalogJSON
import CatalogRules
import Testing

/// The near-duplicate title rule. Ports the Python `NearDuplicateTitleTests`.
struct NearDuplicateTitleRulesTests {
  static let tail = "look like one document under two titles; keep one, or list the pair in reviewed-distinct-titles.json once their documents are checked to differ"

  // NearDuplicateTitleTests.test_two_names_for_one_model_are_reported
  @Test func twoNamesForOneModelAreReported() {
    let registry = Registry.with(
      Registry.document("USB Stick 2448A7 Quick Start Guide", "quickStart"),
      Registry.document("Portable USB Adapter 2448A7 Quick Start Guide", "quickStart")
    )

    #expect(RegistryRules.nearDuplicateProblems(in: registry, reviewed: []) == [
      "registry.json: 'USB Stick 2448A7 Quick Start Guide' and 'Portable USB Adapter 2448A7 Quick Start Guide' \(Self.tail)"
    ])
  }

  // NearDuplicateTitleTests.test_a_title_that_adds_a_word_to_another_is_reported
  @Test func aTitleThatAddsAWordToAnotherIsReported() {
    let registry = Registry.with(
      Registry.document("LED Bulb 2672 Owner's Manual", "ownersManual"),
      Registry.document("LED Bulb A19 2672 Owner's Manual", "ownersManual")
    )

    #expect(RegistryRules.nearDuplicateProblems(in: registry, reviewed: []) == [
      "registry.json: \"LED Bulb 2672 Owner's Manual\" and \"LED Bulb A19 2672 Owner's Manual\" \(Self.tail)"
    ])
  }

  // NearDuplicateTitleTests.test_titles_of_different_kinds_are_not_reported
  @Test func titlesOfDifferentKindsAreNotReported() {
    let registry = Registry.with(
      Registry.document("Leak Sensor 2852 Owner's Manual", "ownersManual"),
      Registry.document("Leak Sensor 2852 Quick Start Guide", "quickStart")
    )

    #expect(RegistryRules.nearDuplicateProblems(in: registry, reviewed: []) == [])
  }

  // NearDuplicateTitleTests.test_unrelated_titles_are_not_reported
  @Test func unrelatedTitlesAreNotReported() {
    let registry = Registry.with(
      Registry.document("Leak Sensor 2852 Owner's Manual", "ownersManual"),
      Registry.document("Motion Sensor 2842 Owner's Manual", "ownersManual")
    )

    #expect(RegistryRules.nearDuplicateProblems(in: registry, reviewed: []) == [])
  }

  // NearDuplicateTitleTests.test_a_reviewed_pair_is_accepted_in_either_order
  @Test func aReviewedPairIsAcceptedInEitherOrder() {
    let registry = Registry.with(
      Registry.document("Access Point 2443 Owner's Manual", "ownersManual"),
      Registry.document("Micro On/Off 2443 Owner's Manual", "ownersManual")
    )
    let pair = Registry.pair("Micro On/Off 2443 Owner's Manual", "Access Point 2443 Owner's Manual")

    #expect(RegistryRules.nearDuplicateProblems(in: registry, reviewed: [pair]) == [])
  }

  // NearDuplicateTitleTests.test_a_reviewed_pair_that_is_no_longer_a_candidate_is_reported
  @Test func aReviewedPairThatIsNoLongerACandidateIsReported() {
    let registry = Registry.with(
      Registry.document("Leak Sensor 2852 Owner's Manual", "ownersManual"),
      Registry.document("Motion Sensor 2842 Owner's Manual", "ownersManual")
    )
    let pair = Registry.pair("Leak Sensor 2852 Owner's Manual", "Motion Sensor 2842 Owner's Manual")

    #expect(RegistryRules.nearDuplicateProblems(in: registry, reviewed: [pair]) == [
      "reviewed-distinct-titles.json: \"Leak Sensor 2852 Owner's Manual\" and \"Motion Sensor 2842 Owner's Manual\" are not a near-duplicate pair; remove the entry"
    ])
  }

  // NearDuplicateTitleTests.test_a_reviewed_pair_naming_an_unregistered_title_is_reported
  @Test func aReviewedPairNamingAnUnregisteredTitleIsReported() {
    let registry = Registry.with(Registry.document("Leak Sensor 2852 Owner's Manual", "ownersManual"))
    let pair = Registry.pair("Leak Sensor 2852 Owner's Manual", "Gone 1234 Owner's Manual")

    #expect(RegistryRules.nearDuplicateProblems(in: registry, reviewed: [pair]) == [
      "reviewed-distinct-titles.json: \"Gone 1234 Owner's Manual\" is not in registry.json"
    ])
  }

  @Test func aReviewedEntryThatIsNotAPairOfTitlesIsReportedAsPythonPrintsIt() throws {
    let registry = Registry.with(Registry.document())
    let entries = try JSONParser.parse(#"["a", ["x"], [1, 2], null, {"a": 1}, 3.5, true, ["p", "q", "r"], ["p", 2]]"#).elements

    #expect(RegistryRules.nearDuplicateProblems(in: registry, reviewed: entries) == [
      "reviewed-distinct-titles.json: each entry must be a list of two titles, not 'a'",
      "reviewed-distinct-titles.json: each entry must be a list of two titles, not ['x']",
      "reviewed-distinct-titles.json: each entry must be a list of two titles, not [1, 2]",
      "reviewed-distinct-titles.json: each entry must be a list of two titles, not None",
      "reviewed-distinct-titles.json: each entry must be a list of two titles, not {'a': 1}",
      "reviewed-distinct-titles.json: each entry must be a list of two titles, not 3.5",
      "reviewed-distinct-titles.json: each entry must be a list of two titles, not True",
      "reviewed-distinct-titles.json: each entry must be a list of two titles, not ['p', 'q', 'r']",
      "reviewed-distinct-titles.json: each entry must be a list of two titles, not ['p', 2]"
    ])
  }

  @Test func eachUnregisteredTitleOfAPairIsReportedAndNoStaleLineFollows() {
    let registry = Registry.with(Registry.document("Leak Sensor 2852 Owner's Manual", "ownersManual"))
    let pair = Registry.pair("Gone 1 Manual", "Gone 2 Manual")

    #expect(RegistryRules.nearDuplicateProblems(in: registry, reviewed: [pair]) == [
      "reviewed-distinct-titles.json: 'Gone 1 Manual' is not in registry.json",
      "reviewed-distinct-titles.json: 'Gone 2 Manual' is not in registry.json"
    ])
  }

  @Test func theUnreviewedPairsComeInRegistryOrder() {
    let registry = Registry.with(
      Registry.document("Alpha 1111 Manual", "ownersManual"),
      Registry.document("Beta 2222 Manual", "ownersManual"),
      Registry.document("Gamma 1111 Manual", "ownersManual"),
      Registry.document("Delta 2222 Manual", "ownersManual")
    )

    #expect(RegistryRules.nearDuplicateProblems(in: registry, reviewed: []) == [
      "registry.json: 'Alpha 1111 Manual' and 'Gamma 1111 Manual' \(Self.tail)",
      "registry.json: 'Beta 2222 Manual' and 'Delta 2222 Manual' \(Self.tail)"
    ])
  }

  // The rule's own pieces, which the Python tests reach only through the registry.

  @Test(arguments: [
    ("Leak Sensor 2852 Owner's Manual", ["leak", "sensor", "2852", "owners"]),
    ("The Hub 2242 Quick Start Guide", ["hub", "2242"]),
    ("Insteon Developer's Guide (2009)", ["developers", "2009"]),
    ("Micro On/Off 2443-222 Owner\u{2019}s Manual", ["micro", "on", "off", "2443", "222"]),
    ("Quick Start Guide - EZIO8SA & PLM Combo", ["ezio8sa", "plm", "combo"]),
    ("\u{212A} 2000", ["k", "2000"]),
    ("", [])
  ])
  func aTitlesWordsAreItsLowercaseRunsWithoutFiller(title: String, words: [String]) {
    #expect(RegistryRules.titleWords(title) == Set(words))
  }

  @Test(arguments: [
    (["2448a7", "usb"], ["2448a7"]),
    (["2443", "222"], ["2443"]),
    (["2009", "2020", "1999", "1900"], []),
    (["2009a", "20x0"], ["2009a"]),
    (["123", "a1234"], []),
    (["12345", "2010"], ["12345"]),
    (["1800", "2100"], ["1800", "2100"])
  ])
  func aModelNumberIsFourDigitsThenLettersOrDigitsAndNotAYear(words: [String], numbers: [String]) {
    #expect(RegistryRules.modelNumbers(in: Set(words)) == Set(numbers))
  }
}
