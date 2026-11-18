import CatalogIngest
import CatalogJSON
import Foundation
import Testing

struct ObservationLoadTests {
  func load(_ text: String) throws -> ObservationLoad {
    let scratch = try Scratch()

    return ObservationFile.load(try scratch.write("a.json", text))
  }

  @Test func malformedJSONIsRejectedWithoutQuotingTheFile() throws {
    let result = try load(#"{"format": "insteon-observation/1", 2F9AC1"#)

    guard case .rejected(let errors) = result else { Issue.record("loaded"); return }
    #expect(errors.count == 1)
    #expect(errors[0].contains("not valid JSON"))
    #expect(!errors[0].contains("2F9AC1"))
  }

  @Test func aFileThatIsNotAnObjectIsRejected() throws {
    #expect(try load("[1, 2]") == .rejected(["the file must hold one JSON object"]))
  }

  @Test func anObjectIsLoaded() throws {
    #expect(try load(#"{"a": 1}"#) == .loaded(json(#"{"a": 1}"#)))
  }

  @Test func aMissingFileIsReportedNotRaised() {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent("absent-\(UUID().uuidString).json")

    #expect(ObservationFile.load(missing) == .rejected(["cannot read the file"]))
    #expect(ObservationFile.fingerprint(missing) == "unreadable")
  }

  @Test func aFolderIsNotAFile() throws {
    let scratch = try Scratch()

    #expect(ObservationFile.load(scratch.url) == .rejected(["cannot read the file"]))
  }

  @Test func theLimitIsSixtyFourKilobytes() throws {
    let scratch = try Scratch()
    let text = "{}"
    let atLimit = scratch.url.appendingPathComponent("at.json")
    let over = scratch.url.appendingPathComponent("over.json")
    try Data((text + String(repeating: " ", count: 65536 - text.utf8.count)).utf8).write(to: atLimit)
    try Data((text + String(repeating: " ", count: 65537 - text.utf8.count)).utf8).write(to: over)

    #expect(ObservationFile.load(atLimit) == .loaded(json("{}")))
    #expect(ObservationFile.load(over) == .rejected(["the file is larger than 64 KB"]))
  }

  @Test func textThatIsNotUTF8IsRejectedAsSuch() throws {
    let scratch = try Scratch()
    let file = scratch.url.appendingPathComponent("a.json")
    try Data([0x7B, 0x22, 0xFF, 0x22, 0x7D]).write(to: file)

    #expect(ObservationFile.load(file) == .rejected(["the file is not valid JSON: it is not UTF-8 text"]))
  }

  @Test func theErrorNamesTheLineAndColumn() throws {
    #expect(try load("{\n  \"a\": 1,\n  \"b\": ,\n}") == .rejected(["the file is not valid JSON (line 3, column 8)"]))
  }

  @Test func aFileIsNamedByItsContentsAndNotByItsFileName() throws {
    let scratch = try Scratch()
    let first = try scratch.write("2F.9A.C1.json", "{}")
    let second = try scratch.write("other.json", "{}")

    #expect(ObservationFile.fingerprint(first) == ObservationFile.fingerprint(second))
    #expect(ObservationFile.fingerprint(first) == "44136fa3")
    #expect(ObservationFile.label(position: 2, of: first) == "observation 2 (44136fa3)")
  }
}
