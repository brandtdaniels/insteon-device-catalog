import Testing

@testable import CatalogSite

/// The escaper matches Python's `html.escape(text, quote=True)`.
struct HTMLEscaperTests {
  @Test(arguments: [
    ("", ""),
    ("plain", "plain"),
    ("a & b", "a &amp; b"),
    ("<b>", "&lt;b&gt;"),
    ("say \"hi\"", "say &quot;hi&quot;"),
    ("it's", "it&#x27;s"),
    ("&amp;", "&amp;amp;"),
    ("&lt;&gt;&quot;&#x27;", "&amp;lt;&amp;gt;&amp;quot;&amp;#x27;"),
    ("<a href=\"x\">'&'</a>", "&lt;a href=&quot;x&quot;&gt;&#x27;&amp;&#x27;&lt;/a&gt;"),
    ("caf\u{E9} \u{3C9} \u{2026}", "caf\u{E9} \u{3C9} \u{2026}"),
    ("e\u{301}", "e\u{301}"),
    ("tab\there", "tab\there"),
    ("line\nbreak", "line\nbreak"),
    ("a/b\\c", "a/b\\c")
  ])
  func escapesTheFiveCharactersAndNothingElse(text: String, expected: String) {
    #expect(HTMLEscaper.escape(text) == expected)
  }

  @Test func escapesAmpersandFirstSoNothingIsEscapedTwice() {
    #expect(HTMLEscaper.escape("<&>") == "&lt;&amp;&gt;")
  }
}
