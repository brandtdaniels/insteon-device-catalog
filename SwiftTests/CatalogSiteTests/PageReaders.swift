import Foundation

/// Reads the page's coverage numbers, links, sources, landmarks and headings, independently of the
/// code that wrote them.
final class PageReader: @unchecked Sendable {
  private(set) var metrics: [String: String] = [:]
  private(set) var sources: [String] = []
  private(set) var hrefs: [String] = []
  private(set) var headings: [(tag: String, text: String)] = []
  private(set) var landmarks: Set<String> = []
  private var metric: String?
  private var heading = false

  init(_ page: String) {
    for event in HTMLScanner.events(in: page) {
      switch event {
      case .start(let tag, let list):
        let attributes = Dictionary(list, uniquingKeysWith: { _, last in last })
        sources += ["src", "srcset"].compactMap { attributes[$0] }

        if tag == "link", let href = attributes["href"] { sources.append(href) }
        if tag == "a" { hrefs.append(attributes["href"] ?? "") }
        if ["header", "main", "footer", "nav"].contains(tag) { landmarks.insert(tag) }
        if let name = attributes["data-metric"] { metric = name }
        if ["h1", "h2", "h3"].contains(tag) {
          heading = true
          headings.append((tag, ""))
        }
      case .end:
        metric = nil
        heading = false
      case .text(let data):
        if let metric { metrics[metric, default: ""] += data }
        if heading { headings[headings.count - 1].text += data }
      }
    }
  }

  var headingTexts: [String] { headings.map(\.text) }
}

/// One fact of a card: a labeled row, a figure or a line, with the command set it belongs to.
final class FactRecord: @unchecked Sendable {
  let commandSet: String?
  let name: String
  var text = ""
  let tag: String
  var depth = 0

  init(commandSet: String?, name: String, tag: String) {
    self.commandSet = commandSet
    self.name = name
    self.tag = tag
  }
}

final class ParagraphRecord: @unchecked Sendable {
  let cls: String
  let inside: Bool
  var text = ""

  init(cls: String, inside: Bool) {
    self.cls = cls
    self.inside = inside
  }
}

final class TermRecord: @unchecked Sendable {
  let tag: String
  var text = ""

  init(tag: String) {
    self.tag = tag
  }
}

struct ListKey: Hashable {
  let commandSet: String?
  let name: String
}

/// What a card holds: its filter attributes, paragraphs, labeled rows and the structure of its
/// detail section.
final class CardRecord: @unchecked Sendable {
  var attributes: [String: String] = [:]
  var facts: [FactRecord] = []
  var lists: [ListKey: [String]] = [:]
  var details = false
  var summary = ""
  var outside = ""
  var inside = ""
  var paragraphs: [ParagraphRecord] = []
  var terms: [TermRecord] = []
  var nested = 0
  var htmlClasses: [(tag: String, cls: String)] = []
}

/// Reads each card of a page: its model, filter attributes, paragraphs, labeled rows and the
/// structure of its detail section.
final class CardReader {
  private(set) var cards: [String: CardRecord] = [:]
  private var card: CardRecord?
  private var commandSet: String?
  private var fact: FactRecord?
  private var list: ListKey?
  private var item: String?
  private var paragraph: ParagraphRecord?
  private var term: TermRecord?
  private var detailsDepth = 0
  private var inSummary = false

  init(_ page: String) {
    for event in HTMLScanner.events(in: page) {
      switch event {
      case .start(let tag, let list): start(tag, Dictionary(list, uniquingKeysWith: { _, last in last }))
      case .end(let tag): end(tag)
      case .text(let data): text(data)
      }
    }
  }

  private func start(_ tag: String, _ attributes: [String: String]) {
    if tag == "article" {
      let record = CardRecord()
      record.attributes = attributes
      card = record
      cards[attributes["data-model"] ?? ""] = record
      return
    }

    guard let card else { return }

    card.htmlClasses.append((tag, attributes["class"] ?? ""))
    if detailsDepth > 0 { card.inside += " " } else { card.outside += " " }

    if tag == "details" {
      detailsDepth += 1
      card.details = true
      card.nested += detailsDepth > 1 ? 1 : 0
    }
    if tag == "summary" { inSummary = true }
    if tag == "p" {
      let record = ParagraphRecord(cls: attributes["class"] ?? "", inside: detailsDepth > 0)
      paragraph = record
      card.paragraphs.append(record)
    }
    if ["dt", "th", "h4"].contains(tag) {
      let record = TermRecord(tag: tag)
      term = record
      card.terms.append(record)
    }
    if let name = attributes["data-command-set"] { commandSet = name }
    if let name = attributes["data-list"] {
      list = ListKey(commandSet: commandSet, name: name)
      card.lists[list!] = []
    }
    if tag == "li", list != nil { item = "" }
    if let name = attributes["data-fact"] {
      let record = FactRecord(commandSet: commandSet, name: name, tag: tag)
      fact = record
      card.facts.append(record)
    } else if let fact, tag == fact.tag {
      fact.depth += 1
    }
  }

  private func end(_ tag: String) {
    if tag == "article" {
      card = nil
      commandSet = nil
      detailsDepth = 0
      return
    }

    guard let card else { return }

    if tag == "details" {
      if list != nil, detailsDepth > 1 { list = nil }
      detailsDepth -= 1
    } else if tag == "summary" {
      inSummary = false
    } else if tag == "p" {
      paragraph = nil
    } else if ["dt", "th", "h4"].contains(tag) {
      term = nil
    } else if tag == "li", let finished = item, let list {
      card.lists[list, default: []].append(finished.trimmingCharacters(in: .whitespacesAndNewlines))
      item = nil
    }

    if let current = fact, tag == current.tag {
      if current.depth == 0 { fact = nil } else { current.depth -= 1 }
    }
  }

  private func text(_ data: String) {
    guard let card else { return }

    fact?.text += data
    if item != nil { item! += data }
    paragraph?.text += data
    if inSummary { card.summary += data }
    term?.text += data

    if detailsDepth > 0 { card.inside += data } else { card.outside += data }
  }
}

extension CardRecord {
  /// The text of every fact called `name`, with white space collapsed, optionally of one command set.
  func facts(_ name: String, commandSet: String? = nil) -> [String] {
    facts.filter { $0.name == name && (commandSet == nil || $0.commandSet == commandSet) }.map { $0.text.collapsingWhitespace }
  }
}

extension String {
  /// Runs of white space made into one space, and the ends trimmed.
  var collapsingWhitespace: String {
    split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  /// The text of a page with its scripts, styles and tags removed and white space collapsed.
  var pageText: String {
    var text = removing(#"<(script|style)\b.*?</\1>"#, options: [.dotMatchesLineSeparators])
    text = text.replacingMatches(of: #"<[^>]+>"#, with: " ")
    return text.replacingMatches(of: #"\s+"#, with: " ")
  }

  func removing(_ pattern: String, options: NSRegularExpression.Options = []) -> String {
    replacingMatches(of: pattern, with: "", options: options)
  }

  func replacingMatches(of pattern: String, with template: String, options: NSRegularExpression.Options = []) -> String {
    let expression = try! NSRegularExpression(pattern: pattern, options: options)
    return expression.stringByReplacingMatches(in: self, range: NSRange(startIndex..., in: self), withTemplate: template)
  }

  /// Whether the pattern matches anywhere, as Python's `re.search` finds it.
  func matches(_ pattern: String, options: NSRegularExpression.Options = []) -> Bool {
    let expression = try! NSRegularExpression(pattern: pattern, options: options)
    return expression.firstMatch(in: self, range: NSRange(startIndex..., in: self)) != nil
  }

  /// The text of the first group of every match, or the whole match when the pattern has none.
  func captures(_ pattern: String, options: NSRegularExpression.Options = []) -> [[String]] {
    let expression = try! NSRegularExpression(pattern: pattern, options: options)
    return expression.matches(in: self, range: NSRange(startIndex..., in: self)).map { match in
      (1..<max(match.numberOfRanges, 2)).map { group in
        Range(match.range(at: min(group, match.numberOfRanges - 1)), in: self).map { String(self[$0]) } ?? ""
      }
    }
  }

  /// How many times `fragment` occurs, without overlap.
  func occurrences(of fragment: String) -> Int {
    guard !fragment.isEmpty else { return 0 }
    return components(separatedBy: fragment).count - 1
  }
}
