import CatalogJSON
import CatalogRules
import Testing

/// The rules a profile has beyond its schema. The Python build has no test for these; the sweep
/// compares them with it.
struct ProfileRulesTests {
  @Test func aFileNameThatIsNotTheModelIsReported() throws {
    let profile = try Fixtures.profile("2441ZTH")

    #expect(ProfileRules.problems(in: profile, fileStem: "other") == ["the file name must be the model, '2441ZTH'"])
    #expect(ProfileRules.problems(in: profile, fileStem: "2441ZTH") == [])
  }

  @Test func aCapabilityKindUsedTwiceIsReported() throws {
    let profile = try Fixtures.profile("2441ZTH")
    let first = try #require(profile["capabilities"]?.elements.first)
    let doubled = try profile.appending(to: ["capabilities"], "[\(JSONWriter.write(first, style: .init(indent: 0)))]")

    #expect(ProfileRules.problems(in: doubled, fileStem: "2441ZTH") == ["a capability kind appears more than once"])
  }

  @Test func aCommandSetEntryForAnIdentityTheProductDoesNotReportIsReported() throws {
    let profile = try Fixtures.profile("2441ZTH").setting(["commandSets", .index(0), "category"], "\"0x99\"")

    #expect(ProfileRules.problems(in: profile, fileStem: "2441ZTH") == [
      "the command set entry for 0x99/0x0A names an identity the product doesn't report"
    ])
  }

  @Test func twoCommandSetEntriesThatCoverTheSameFirmwareUnderOneIdentityAreReported() throws {
    let profile = try Fixtures.profile("2441ZTH").setting(["commandSets", .index(1), "subcategory"], "\"0x0A\"")

    #expect(ProfileRules.problems(in: profile, fileStem: "2441ZTH") == [
      "two command set entries cover the same firmware under 0x05/0x0A"
    ])
  }

  @Test func entriesWithDifferentFirmwareUnderOneIdentityDoNotOverlap() throws {
    let profile = try Fixtures.profile("2441ZTH")
      .setting(["commandSets", .index(0), "firmware"], #"{"only": ["0x01", "0x02"]}"#)
      .setting(["commandSets", .index(1), "subcategory"], "\"0x0A\"")
      .setting(["commandSets", .index(1), "firmware"], #"{"except": ["0x01", "0x02"]}"#)

    #expect(ProfileRules.problems(in: profile, fileStem: "2441ZTH") == [])
  }

  @Test func aModemsRecordDataThatNamesAByteTwiceOrGivesBothAValueAndAnIdentityIsReported() throws {
    let steps: [Step] = ["capabilities", .index(try modemCapabilityIndex()), "linkData", "controller"]
    let profile = try Fixtures.profile("2245")
    let doubled = try profile.setting(steps + [.index(1), "byte"], "1")
    let both = try profile.setting(steps + [.index(0), "identity"], "\"cmd1\"")
    guard case .string(let name)? = profile.value(at: steps + [.index(0), "name"]) else {
      Issue.record("the first controller entry has no name")
      return
    }

    #expect(ProfileRules.problems(in: doubled, fileStem: "2245") == ["the modem's controller record data names a byte twice"])
    #expect(ProfileRules.problems(in: both, fileStem: "2245") == [
      "the modem's controller record data \(name) needs a value or an identity, not both"
    ])
  }

  private func modemCapabilityIndex() throws -> Int {
    let profile = try Fixtures.profile("2245")
    return try #require(profile["capabilities"]?.elements.firstIndex { $0["linkData"] != nil })
  }

  @Test func twoProfilesThatClaimOneIdentityForOverlappingFirmwareAreReported() throws {
    let first = try Fixtures.profile("2441ZTH")
    let second = try first.setting(["model"], "\"9999\"")

    #expect(ProfileRules.overlappingIdentities([first, second]) == [
      "9999 and 2441ZTH both claim 0x05/0x0A for overlapping firmware",
      "9999 and 2441ZTH both claim 0x05/0x07 for overlapping firmware",
      "9999 and 2441ZTH both claim 0x05/0x11 for overlapping firmware",
      "9999 and 2441ZTH both claim 0x05/0x12 for overlapping firmware"
    ])
  }

  @Test func identitiesWithDisjointFirmwareDoNotOverlap() throws {
    let first = try Fixtures.profile("2441ZTH").setting(["identities", .index(0), "firmware"], #"{"from": "0x00", "through": "0x10"}"#)
    let second = try Fixtures.profile("2441ZTH")
      .setting(["model"], "\"9999\"")
      .setting(["identities", .index(0), "firmware"], #"{"from": "0x11", "through": "0xFF"}"#)

    #expect(ProfileRules.overlappingIdentities([first, second]).filter { $0.contains("0x05/0x0A") } == [])
  }

  @Test func aCommandSetTheProfileNamesButTheCatalogLacksIsReportedWithTheFileName() throws {
    let profile = try Fixtures.profile("2441ZTH").setting(["commandSets", .index(0), "commandSet"], "\"nope\"")
    let tempLinc = try Fixtures.commandSet("tempLinc")

    #expect(ProfileRules.commandSetProblems(for: profile, commandSets: ["tempLinc": tempLinc]) == [
      "2441ZTH.json: it names the command set 'nope', which doesn't exist"
    ])
  }

  @Test func aGroupTypeTheCommandSetLacksIsReportedForEachCommandSetTheProfileUses() throws {
    let profile = try Fixtures.profile("2441ZTH").setting(["groups", .index(0), "type"], "\"nope\"")

    #expect(ProfileRules.commandSetProblems(for: profile, commandSets: ["tempLinc": try Fixtures.commandSet("tempLinc")]) == [
      "2441ZTH.json: group 0x01 names the group type 'nope', which tempLinc doesn't have"
    ])
  }

  @Test func aGroupWhoseRoleIsNotTheProfilesIsReported() throws {
    let profile = try Fixtures.profile("2441ZTH").setting(["role"], "\"responder\"")
    let problems = ProfileRules.commandSetProblems(for: profile, commandSets: ["tempLinc": try Fixtures.commandSet("tempLinc")])

    #expect(problems.count == 5)
    #expect(problems.first == "2441ZTH.json: group 0x01 is a controller, but the profile is only a responder")
  }

  @Test func aGroupThatDependsOnAFlagTheCommandSetLacksIsReported() throws {
    let profile = try Fixtures.profile("2441ZTH").setting(["groups", .index(0), "activeWhen"], #"{"flag": "missingFlag"}"#)

    #expect(ProfileRules.commandSetProblems(for: profile, commandSets: ["tempLinc": try Fixtures.commandSet("tempLinc")]) == [
      "2441ZTH.json: group 0x01 depends on 'missingFlag', which tempLinc has no flag for"
    ])
  }
}

extension JSONValue {
  func value(at steps: [Step]) -> JSONValue? {
    var current: JSONValue? = self
    for step in steps {
      switch step {
      case .key(let key): current = current?[key]
      case .index(let index): current = current.flatMap { $0.elements.indices.contains(index) ? $0.elements[index] : nil }
      case .named(let name): current = current?.elements.first { $0["name"] == .string(name) }
      }
    }
    return current
  }
}
