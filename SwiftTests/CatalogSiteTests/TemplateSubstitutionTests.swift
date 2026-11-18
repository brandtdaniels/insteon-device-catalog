import Foundation
import Testing

@testable import CatalogSite

/// The substituter follows Python's `string.Template.substitute`.
struct TemplateSubstitutionTests {
  @Test func replacesEachNamedPlaceholder() throws {
    let text = try Template("Version $catalog_version of $count.").substitute(["catalog_version": "0.10.3", "count": "151"])

    #expect(text == "Version 0.10.3 of 151.")
  }

  @Test func takesTheLongestIdentifier() throws {
    #expect(try Template("$version/catalog.json v$version/x").substitute(["version": "0"]) == "0/catalog.json v0/x")
    #expect(try Template("$a_b2.c").substitute(["a_b2": "X"]) == "X.c")
  }

  @Test func aDoubleDollarIsOneDollar() throws {
    #expect(try Template("cost $$5 and $$$x").substitute(["x": "y"]) == "cost $5 and $y")
  }

  @Test func bracesEndTheIdentifierEarly() throws {
    #expect(try Template("${name}text").substitute(["name": "A"]) == "Atext")
  }

  @Test func anUnknownNameIsAnError() {
    #expect(throws: SiteError.unknownPlaceholder("missing")) { try Template("$missing").substitute([:]) }
  }

  @Test(arguments: ["$", "$ x", "a $", "$1", "${", "${}", "${a b}", "$-"])
  func aDollarThatStartsNothingIsAnError(text: String) {
    #expect(throws: SiteError.invalidPlaceholder) { try Template(text).substitute(["a": "A"]) }
  }

  @Test func leavesEverythingElseAlone() throws {
    #expect(try Template("<a>\n  {b} %s \\n").substitute([:]) == "<a>\n  {b} %s \\n")
  }

  @Test func aSubstitutedValueIsNotScannedAgain() throws {
    #expect(try Template("$a").substitute(["a": "$b", "b": "X"]) == "$b")
  }

  @Test func theRepositoryTemplateNamesTheElevenPlaceholdersTheBuildFills() throws {
    let template = try Template(String(contentsOf: CatalogRepository.url.appendingPathComponent("templates/index.html"), encoding: .utf8))

    #expect(template.placeholders == [
      "catalog_version", "version", "coverage", "capabilities", "category_options", "capability_options", "engine_options",
      "verification_options", "count", "sections", "how"
    ])
  }
}
