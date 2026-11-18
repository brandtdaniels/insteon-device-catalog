import CatalogJSON

/// Two titles that look like one document.
public struct TitlePair: Equatable, Sendable {
  public let first: String
  public let second: String
}

/// The rules for the document registry and the file of title pairs reviewed as different.
public enum RegistryRules {
  /// The registry file's name, which starts its lines.
  public static let registryFile = "registry.json"
  /// The reviewed pairs file's name, which starts its lines.
  public static let reviewedFile = "reviewed-distinct-titles.json"

  /// What kind of document an entry is.
  static let documentKinds: Set<ExactText> = Set([
    "commandTables", "developerDocumentation", "developerNotes", "developersGuide", "deviceCategories",
    "deviceDefinitions", "ownersManual", "productCatalog", "productGuide", "quickStart", "supportArticle", "other"
  ].map(ExactText.init))

  private static let documentFields: Set<String> = ["title", "kind", "edition", "url"]
  private static let httpsURL = Pattern.whole("https://[^\(pythonWhitespaceClass)/]+(/[^\(pythonWhitespaceClass)]*)?")

  /// What is wrong with the registry: its shape, each entry, and repeated titles.
  public static func problems(in registry: JSONValue) -> [String] {
    guard case .object(let members) = registry, members.map(\.key) == ["documents"], case .array(let entries) = members[0].value else {
      return [#"\#(registryFile): must be an object with only a "documents" list"#]
    }

    var problems: [String] = []
    var seen = Set<ExactText>()

    for (position, entry) in entries.enumerated() {
      problems += documentProblems(position: position, entry: entry)

      guard let title = entry["title"]?.string else { continue }

      if seen.contains(ExactText(title)) {
        problems.append("\(registryFile): title \(pythonRepr(title)) appears more than once")
      }

      seen.insert(ExactText(title))
    }

    return problems
  }

  /// What is wrong with one entry.
  private static func documentProblems(position: Int, entry: JSONValue) -> [String] {
    guard case .object(let members) = entry else {
      return ["\(registryFile): entry \(position) must be an object"]
    }

    var problems: [String] = []
    let title = entry["title"]?.string
    let label = "\(registryFile): entry \(position)" + (title.map { " (\(pythonRepr($0)))" } ?? "")

    for field in members.map(\.key).filter({ !documentFields.contains($0) }).codePointSorted() {
      problems.append("\(label): unknown field \(pythonRepr(field))")
    }

    for field in ["title", "kind"] where entry[field]?.string.map(\.isBlankToPython) ?? true {
      problems.append("\(label): \(field) must be a non-empty string")
    }

    if let kind = entry["kind"]?.string, !documentKinds.contains(ExactText(kind)) {
      let kinds = documentKinds.map { String(decoding: $0.utf8, as: UTF8.self) }.codePointSorted()
      problems.append("\(label): kind \(pythonRepr(kind)) is not one of \(pythonRepr(.array(kinds.map(JSONValue.string))))")
    }

    if let edition = entry["edition"], edition.string.map(\.isBlankToPython) ?? true {
      problems.append("\(label): edition must be a non-empty string")
    }

    if let url = entry["url"], !(url.string.map(httpsURL.matches) ?? false) {
      problems.append("\(label): url must be an https URL")
    }

    for member in members {
      if let text = member.value.string, text.hasEmOrEnDash {
        problems.append("\(label): \(member.key) has a dash; rewrite it with a comma, colon or hyphen")
      }
    }

    if let title {
      problems += TermRules.problems(label: label, in: .string(title), key: "sources")
    }

    return problems
  }

  // MARK: Near-duplicate titles

  /// Words every title of a kind carries, which say nothing about which document it is.
  private static let titleFiller: Set<String> = ["owner", "manual", "quick", "start", "guide", "developer", "notes", "insteon", "the", "and", "with", "for", "of"]
  private static let modelNumber = Pattern.whole(#"\d{4}[a-z0-9]*"#)
  private static let year = Pattern.whole(#"(19|20)\d\d"#)

  /// The words of a title that name its subject: lowercase, without punctuation or filler.
  public static func titleWords(_ title: String) -> Set<String> {
    var lowered = ""

    for scalar in title.unicodeScalars where scalar != "'" {
      lowered += scalar.properties.lowercaseMapping
    }

    var words = Set<String>()
    var current = ""

    for scalar in lowered.unicodeScalars {
      if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) {
        current.unicodeScalars.append(scalar)
      } else if !current.isEmpty {
        words.insert(current)
        current = ""
      }
    }

    if !current.isEmpty { words.insert(current) }

    return words.subtracting(titleFiller).subtracting(["s"])
  }

  /// The words that are model numbers: four digits, then any letters or digits, and not a year. A
  /// regional suffix such as 222 is not one.
  public static func modelNumbers(in words: Set<String>) -> Set<String> {
    words.filter { modelNumber.matches($0) && !year.matches($0) }
  }

  /// The pairs of titles of one kind where one title's words contain the other's, or both name a
  /// model number, in registry order.
  public static func nearDuplicates(in registry: JSONValue) -> [TitlePair] {
    let documents = registry.list("documents").filter { $0["title"]?.string != nil }
    var pairs: [TitlePair] = []

    for (position, first) in documents.enumerated() {
      for second in documents[(position + 1)...] where first["kind"]?.canonical == second["kind"]?.canonical {
        guard let firstTitle = first["title"]?.string, let secondTitle = second["title"]?.string else { continue }
        let one = titleWords(firstTitle), other = titleWords(secondTitle)

        if !one.isEmpty, !other.isEmpty, one.isSubset(of: other) || other.isSubset(of: one) || !modelNumbers(in: one).isDisjoint(with: modelNumbers(in: other)) {
          pairs.append(TitlePair(first: firstTitle, second: secondTitle))
        }
      }
    }

    return pairs
  }

  /// Near-duplicate titles nobody has reviewed, and reviewed pairs that no longer fit the registry.
  ///
  /// `reviewed` lists pairs of titles checked against their documents and found to be different
  /// documents. A pair listed there that isn't a candidate, or names an unregistered title, is stale.
  public static func nearDuplicateProblems(in registry: JSONValue, reviewed: [JSONValue]) -> [String] {
    let registered = Set(registry.list("documents").compactMap { $0["title"]?.string }.map(ExactText.init))
    let candidates = Set(nearDuplicates(in: registry).map(pairKey))
    var problems: [String] = []
    var listed = Set<Set<ExactText>>()

    for pair in reviewed {
      guard case .array(let items) = pair, items.count == 2, let first = items[0].string, let second = items[1].string else {
        problems.append("\(reviewedFile): each entry must be a list of two titles, not \(pythonRepr(pair))")
        continue
      }

      for title in [first, second] where !registered.contains(ExactText(title)) {
        problems.append("\(reviewedFile): \(pythonRepr(title)) is not in \(registryFile)")
      }

      let key = pairKey(TitlePair(first: first, second: second))

      if [first, second].allSatisfy({ registered.contains(ExactText($0)) }), !candidates.contains(key) {
        problems.append("\(reviewedFile): \(pythonRepr(first)) and \(pythonRepr(second)) are not a near-duplicate pair; remove the entry")
      }

      listed.insert(key)
    }

    for pair in nearDuplicates(in: registry) where !listed.contains(pairKey(pair)) {
      problems.append(
        "\(registryFile): \(pythonRepr(pair.first)) and \(pythonRepr(pair.second)) look like one document under two titles; "
          + "keep one, or list the pair in \(reviewedFile) once their documents are checked to differ"
      )
    }

    return problems
  }

  private static func pairKey(_ pair: TitlePair) -> Set<ExactText> {
    [ExactText(pair.first), ExactText(pair.second)]
  }

  // MARK: The reviewed pairs file

  /// The pairs a reviewed pairs file lists under `distinct`, or the Python error text the build
  /// printed for a file that has no such list: `KeyError('distinct')` for an object without it and a
  /// `TypeError` for any other kind of value.
  public static func reviewedPairs(in document: JSONValue) -> Result<[JSONValue], ReviewedFileError> {
    switch document {
    case .object(let members):
      guard let distinct = members.first(where: { $0.key == "distinct" })?.value else {
        return .failure(ReviewedFileError(text: "KeyError('distinct')"))
      }

      switch distinct {
      case .array(let pairs): return .success(pairs)
      case .string(let text): return .success(text.unicodeScalars.map { .string(String($0)) })
      case .object(let members): return .success(members.map { .string($0.key) })
      default: return .failure(ReviewedFileError(text: typeError("'\(typeName(distinct))' object is not iterable")))
      }
    case .array:
      return .failure(ReviewedFileError(text: typeError("list indices must be integers or slices, not str")))
    case .string:
      return .failure(ReviewedFileError(text: typeError("string indices must be integers, not 'str'")))
    default:
      return .failure(ReviewedFileError(text: typeError("'\(typeName(document))' object is not subscriptable")))
    }
  }

  private static func typeError(_ message: String) -> String {
    "TypeError(\(pythonRepr(message)))"
  }

  private static func typeName(_ value: JSONValue) -> String {
    switch value {
    case .null: "NoneType"
    case .bool: "bool"
    case .int: "int"
    case .double: "float"
    case .string: "str"
    case .array: "list"
    case .object: "dict"
    }
  }
}

/// Why a reviewed pairs file has no list of pairs, in the words Python's exception repr gives.
public struct ReviewedFileError: Error, Equatable, Sendable, CustomStringConvertible {
  public let text: String

  public var description: String { text }
}
