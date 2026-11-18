import CatalogSite
import Foundation

/// How one kind of fragment of the page compares between the Swift renderer and the Python build.
public struct FragmentResult: Equatable, Sendable {
  public let name: String
  /// How many fragments of this kind the Python page has.
  public let total: Int
  /// How many of them the Swift page has with the same bytes.
  public let identical: Int
  /// The first difference among the others.
  public let firstDifference: PageDifference?

  public var agrees: Bool { identical == total && firstDifference == nil }
}

/// Compares the page one fragment at a time: the coverage summary, the legend, the closing
/// section, the filter options, each category section's opening and then every card.
public enum FragmentComparison {
  public static func compare(swift: PageFragments, pythonPage: String) -> [FragmentResult] {
    var results: [FragmentResult] = []

    func single(_ name: String, swift swiftText: String, python pythonText: String?) {
      let python = pythonText ?? ""
      results.append(FragmentResult(
        name: name, total: 1, identical: sameBytes(swiftText, python) ? 1 : 0,
        firstDifference: PageComparison.firstDifference(swift: swiftText, python: python)
      ))
    }

    single("coverage summary", swift: swift.coverage, python: section("coverage", in: pythonPage))
    single("legend", swift: swift.capabilities, python: section("capabilities", in: pythonPage))
    single("how section", swift: swift.how, python: section("how", in: pythonPage))
    single("category options", swift: swift.categoryOptions, python: options(of: "category", in: pythonPage))
    single("capability options", swift: swift.capabilityOptions, python: options(of: "capability", in: pythonPage))
    single("engine options", swift: swift.engineOptions, python: options(of: "engine", in: pythonPage))
    single("verification options", swift: swift.verificationOptions, python: options(of: "verification", in: pythonPage))

    let pythonSections = slices(of: pythonPage, from: #"<section class="category""#, through: "</section>")
    let swiftSections = swift.categories.map(\.html)
    results.append(compareLists(
      name: "category sections", swift: swiftSections.map(opening), python: pythonSections.map(opening)
    ))

    let pythonCards = slices(of: pythonPage, from: #"<article class="card""#, through: "</article>")
    let swiftCards = swift.categories.flatMap(\.cards).map(\.html)
    results.append(compareCards(swift: swiftCards, python: pythonCards))

    return results
  }

  /// Whether the texts are the same bytes. Swift's own `==` takes canonically equivalent text as equal.
  private static func sameBytes(_ left: String, _ right: String) -> Bool {
    left.utf8.elementsEqual(right.utf8)
  }

  /// A category section up to its grid of cards.
  private static func opening(_ section: String) -> String {
    guard let range = section.range(of: #"<div class="grid">"#) else { return section }
    return String(section[..<range.lowerBound])
  }

  /// The section with the class, from its start tag to its end tag.
  private static func section(_ name: String, in page: String) -> String? {
    slices(of: page, from: #"<section class="\#(name)""#, through: "</section>").first
  }

  /// The options of a filter, after its first "any" option.
  private static func options(of id: String, in page: String) -> String? {
    guard let start = page.range(of: #"<select id="\#(id)""#), let first = page[start.upperBound...].range(of: "</option>"),
          let end = page[first.upperBound...].range(of: "</select>")
    else { return nil }

    return String(page[first.upperBound..<end.lowerBound])
  }

  /// Every piece of the page that starts with `opening` and ends at the next `closing`, in order.
  static func slices(of page: String, from opening: String, through closing: String) -> [String] {
    var found: [String] = []
    var rest = page[...]

    while let start = rest.range(of: opening), let end = rest[start.upperBound...].range(of: closing) {
      found.append(String(rest[start.lowerBound..<end.upperBound]))
      rest = rest[end.upperBound...]
    }

    return found
  }

  /// The value of a card's `data-model`.
  private static func model(of card: String) -> String {
    guard let start = card.range(of: #"data-model=""#), let end = card[start.upperBound...].firstIndex(of: "\"") else { return "" }
    return String(card[start.upperBound..<end])
  }

  /// Cards matched by model, each Python card against the Swift card of the same model.
  private static func compareCards(swift: [String], python: [String]) -> FragmentResult {
    let swiftByModel = Dictionary(swift.map { (model(of: $0), $0) }, uniquingKeysWith: { first, _ in first })
    var identical = 0
    var first: PageDifference?

    for card in python {
      let counterpart = swiftByModel[model(of: card)] ?? ""

      if sameBytes(counterpart, card) {
        identical += 1
      } else if first == nil {
        first = PageComparison.firstDifference(swift: counterpart, python: card)
      }
    }

    if first == nil, swift.count != python.count {
      first = PageComparison.firstDifference(swift: swift.joined(), python: python.joined())
    }

    return FragmentResult(name: "cards", total: python.count, identical: identical, firstDifference: first)
  }

  /// Fragments compared by position.
  private static func compareLists(name: String, swift: [String], python: [String]) -> FragmentResult {
    var identical = 0
    var first: PageDifference?

    for (index, text) in python.enumerated() {
      let counterpart = index < swift.count ? swift[index] : ""

      if sameBytes(counterpart, text) {
        identical += 1
      } else if first == nil {
        first = PageComparison.firstDifference(swift: counterpart, python: text)
      }
    }

    if first == nil, swift.count != python.count {
      first = PageComparison.firstDifference(swift: swift.joined(), python: python.joined())
    }

    return FragmentResult(name: name, total: python.count, identical: identical, firstDifference: first)
  }
}
