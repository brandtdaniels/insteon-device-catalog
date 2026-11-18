import CatalogJSON
import Testing

@testable import CatalogSite

/// What the catalog covers, counted from its data.
struct PageCoverageTests {
  @Test func countsProfilesIdentitiesAndIdentityStatuses() throws {
    let profiles = json(#"""
    [{"identities": [{}, {"verification": {"status": "observed", "note": "n"}}], "commandSets": []},
     {"identities": [{"verification": {"status": "conflicting", "note": "n"}}]}]
    """#).elements

    let coverage = try CoverageSummary(profiles: profiles, commandSets: [])

    #expect(coverage.profiles == 2)
    #expect(coverage.identities == 3)
    #expect(coverage.identityStatuses == ["observed": 1, "documented": 1, "inferred": 0, "conflicting": 1])
  }

  @Test func separatesDescribedDeliberatelyEmptyAndUndescribedProfiles() throws {
    let commandSets = json(#"""
    [{"id": "described", "name": "D", "operatingFlags": []},
     {"id": "empty", "name": "E", "description": "Nothing to read.", "sources": ["S"]}]
    """#).elements
    let profiles = json(#"""
    [{"identities": [{}], "commandSets": [{"commandSet": "described"}]},
     {"identities": [{}], "commandSets": [{"commandSet": "empty"}]},
     {"identities": [{}], "commandSets": [{"commandSet": "empty"}, {"commandSet": "described"}]},
     {"identities": [{}]}]
    """#).elements

    let coverage = try CoverageSummary(profiles: profiles, commandSets: commandSets)

    #expect(coverage.described == 2)
    #expect(coverage.deliberatelyEmpty == 1)
    #expect(coverage.undescribed == 1)
  }

  @Test func countsTheStatusOfEveryMarkedCommandSetValue() throws {
    let commandSets = json(#"""
    [{"id": "a", "name": "A", "operatingFlags": [
      {"verification": {"status": "inferred", "note": "n"}},
      {"nested": [{"verification": {"status": "inferred", "note": "n"}}, {"verification": {"status": "observed", "note": "n"}}]}]}]
    """#).elements

    let coverage = try CoverageSummary(profiles: [], commandSets: commandSets)

    #expect(coverage.commandSetStatuses == ["observed": 1, "documented": 0, "inferred": 2, "conflicting": 0])
  }

  @Test func matchesTheCatalogFiles() throws {
    let profiles = CatalogPage.profiles
    let commandSets = CatalogPage.commandSets
    let coverage = try CoverageSummary(profiles: profiles, commandSets: commandSets)
    let expected = commandSets.flatMap { markedStatuses(in: $0) }

    #expect(profiles.count == 151)
    #expect(coverage.commandSetStatuses == Dictionary(uniqueKeysWithValues: PageTables.statuses.map { status in (status, expected.filter { $0 == status }.count) }))
    #expect(coverage.described + coverage.deliberatelyEmpty + coverage.undescribed == profiles.count)
    #expect(coverage.identityStatuses.values.reduce(0, +) == coverage.identities)
  }

  @Test func aProfileThatNamesAMissingCommandSetIsAnError() {
    let profiles = json(#"[{"identities": [{}], "commandSets": [{"commandSet": "gone"}]}]"#).elements

    #expect(throws: SiteError.missingCommandSet("gone")) { try CoverageSummary(profiles: profiles, commandSets: []) }
  }

  @Test func readsAMarkAtAnyDepthAndUnderAnyListOfMarks() {
    let value = json(#"""
    {"verification": {"status": "observed"}, "a": [{"verification": [{"status": "inferred"}, {"status": "conflicting"}]}],
     "b": {"verification": {"note": "no status"}}, "c": {"x": {"verification": {"status": "documented"}}}}
    """#)

    #expect(StatusMarks.statuses(in: value) == ["observed", "inferred", "conflicting", "documented"])
  }

  @Test func aMarkOnTheRootValueItselfIsNotCounted() {
    #expect(StatusMarks.statuses(in: json(#"{"status": "observed"}"#)) == [])
  }
}
