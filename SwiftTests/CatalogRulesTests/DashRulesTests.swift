import CatalogRules
import Testing

/// The dash rule. Ports the Python `NoDashTests`; the check over the catalog's own files is in
/// `RegistryProblemsTests`.
struct DashRulesTests {
  // NoDashTests.test_a_dash_in_a_data_file_is_reported_with_its_file
  @Test func aDashInADataFileIsReportedWithItsFile() {
    #expect(DashRules.problems(file: "devices/1234.json", text: #"{"sources": ["A \#u{2014} B"]}"#) == [
      "devices/1234.json: has an em or en dash; use a hyphen, comma or colon"
    ])
  }

  @Test(arguments: ["\u{2013}", "\u{2014}", "a\u{2014}", "\u{2013}\u{2014}"])
  func anEmOrEnDashIsReportedOnceForTheFile(text: String) {
    #expect(DashRules.problems(file: "documents/registry.json", text: text).count == 1)
  }

  @Test(arguments: ["-", "a-b", "\u{2012}", "\u{2015}", "\u{2212}", "\u{FE58}", "\\u2014", "\\u2013", "\u{2010}\u{2011}", ""])
  func otherDashesAndEscapesAreNotReported(text: String) {
    #expect(DashRules.problems(file: "devices/1.json", text: text) == [])
  }
}
