import CatalogIngest
import CatalogJSON
import Testing

struct BenchFileDraftTests {
  @Test func anObservationTheCatalogAlreadyRecordsChangesNothing() {
    let result = draft(Fixtures.bench("dimmer-plug-2457D2.json"), benchCatalog())

    #expect(result.outcome == .noChange)
    #expect(result.changes.isEmpty)
    #expect(result.disagreements.isEmpty)
    #expect(result.unchanged.map(\.target) == ["identity 0x01/0x0E", "engine i2 0x01/0x0E"])
    #expect(result.matched == ProfileMatch(model: "2457D2", category: "0x01", subcategory: "0x0E"))
  }

  @Test func aSilentProductDataRequestIsSkippedAndNeverAClaim() {
    let result = draft(Fixtures.bench("dimmer-plug-2457D2.json"), benchCatalog())

    #expect(result.skipped == [SkippedCheck(check: "Product Data Request", reason: "outcome was silent; says nothing about the device")])
  }

  @Test func operatingFlagBytesAreListedAndComparedWithNothing() {
    let result = draft(Fixtures.bench("dimmer-plug-2457D2.json"), benchCatalog())

    #expect(result.reportOnly.count == 1)
    #expect(result.reportOnly[0].detail.contains("20 03 03"))
  }

  @Test func anEngineTheCatalogHasNotSeenObservedIsMarkedWhenTheIdentityIsAlreadyRecorded() {
    let result = draft(Fixtures.bench("io-module-2450.json"), benchCatalog())

    #expect(result.outcome == .drafted)
    #expect(changed(result) == ["engine verification marked observed on firmware 0x41"])
    #expect(result.changes[0].after == json("""
      {"status": "observed", "note": "Seen on a device running firmware 0x41: Get Insteon Engine Version answered with i2CS.", "firmware": ["0x41"]}
      """))
    #expect(result.changes[0].before == nil)
  }

  @Test func aProductThatReportsNoKeyIsMarkedAndTheNoteSaysSo() {
    let result = draft(Fixtures.bench("on-off-plug-2635-222.json"), benchCatalog())

    #expect(result.outcome == .drafted)
    #expect(changed(result) == ["identity verification marked observed on firmware 0x48", "engine verification marked observed on firmware 0x48"])
    #expect(result.changes[0].after["note"]?.string == """
      Seen on a device running firmware 0x48: ID Request answered with category 0x02, subcategory 0x37 and firmware 0x48. \
      Product Data Request answered and reported no product key.
      """)
    #expect(result.disagreements.isEmpty)
  }

  @Test func aFileWhereNothingAnsweredWritesNothingAndSaysWhy() {
    let result = draft(Fixtures.bench("silent-sensor.json"), benchCatalog())

    #expect(result.outcome == .noChange)
    #expect(result.changes.isEmpty)
    #expect(result.disagreements.isEmpty)
    #expect(result.skipped.map(\.check) == ["Get Insteon Engine Version", "ID Request"])
    #expect(result.warnings == ["No check was answered, so this file says nothing about the device. Run `insteon observe` again with the device awake."])
  }
}

struct IdentityDraftTests {
  @Test func anUnmarkedIdentityIsMarkedWithATemplatedNoteAndTheFirmware() throws {
    let result = draft(observation(), inventedCatalog())
    let identity = try #require(change(result, entry: "identity"))

    #expect(identity.after == json("""
      {"status": "observed", "note": "Seen on a device running firmware 0x41: ID Request answered with category 0x7E, subcategory 0x7F and firmware 0x41.", "firmware": ["0x41"]}
      """))
    #expect(identity.file == "devices/9999.json")
    #expect(identity.selector == json(#"{"category": "0x7E", "subcategory": "0x7F"}"#))
  }

  @Test func anOlderNoteFollowsTheNewSentenceWhenADocumentedValueIsMarked() throws {
    let catalog = inventedCatalog(identity: """
      {"category": "0x7E", "subcategory": "0x7F", "productKey": "0x00001A", "verification": {"status": "inferred", "note": "Read from a similar product."}}
      """)

    let identity = try #require(change(draft(observation(), catalog), entry: "identity"))
    let note = identity.after["note"]?.string ?? ""

    #expect(note.hasSuffix(" Read from a similar product."))
    #expect(note.hasPrefix("Seen on a device running firmware 0x41: "))
    #expect(identity.after["status"] == .string("observed"))
  }

  @Test func anIdentityObservedOnThisFirmwareIsNotMarkedAgain() {
    let catalog = inventedCatalog(identity: #"{"category": "0x7E", "subcategory": "0x7F", "productKey": "0x00001A", "verification": \#(observed(["0x41"]))}"#)
    let result = draft(observation(), catalog)

    #expect(change(result, entry: "identity") == nil)
    #expect(result.unchanged.map(\.target).contains("identity 0x7E/0x7F"))
  }

  @Test func aDifferentFirmwareIsAddedToTheObservedRecordAndTheNoteIsKept() throws {
    let note = "Seen on a device running firmware 0x3B: kept as written."
    let before = observed(["0x3B"], note: note)
    let catalog = inventedCatalog(identity: #"{"category": "0x7E", "subcategory": "0x7F", "productKey": "0x00001A", "verification": \#(before)}"#)

    let identity = try #require(change(draft(observation(), catalog), entry: "identity"))

    #expect(identity.effect == "added firmware 0x41 to the observed record")
    #expect(identity.after == json(#"{"status": "observed", "note": "\#(note)", "firmware": ["0x3B", "0x41"]}"#))
    #expect(identity.before == json(before))
  }

  @Test func theFirmwareListStaysInCodePointOrder() throws {
    let catalog = inventedCatalog(identity: #"{"category": "0x7E", "subcategory": "0x7F", "productKey": "0x00001A", "verification": \#(observed(["0x50", "0x3B"]))}"#)

    let identity = try #require(change(draft(observation(), catalog), entry: "identity"))

    #expect(identity.after["firmware"] == json(#"["0x3B", "0x41", "0x50"]"#))
  }

  @Test func anObservedRecordWithoutAFirmwareListGainsOne() throws {
    let catalog = inventedCatalog(identity: """
      {"category": "0x7E", "subcategory": "0x7F", "productKey": "0x00001A", "verification": {"status": "observed", "note": "Seen."}}
      """)

    let identity = try #require(change(draft(observation(), catalog), entry: "identity"))

    #expect(identity.after == json(#"{"status": "observed", "note": "Seen.", "firmware": ["0x41"]}"#))
  }

  @Test func aConflictingIdentityIsNeverOverwritten() {
    let catalog = inventedCatalog(identity: """
      {"category": "0x7E", "subcategory": "0x7F", "productKey": "0x00001A", "verification": {"status": "conflicting", "note": "Two documents disagree."}}
      """)
    let result = draft(observation(), catalog)

    #expect(change(result, entry: "identity") == nil)
    #expect(codes(result) == ["conflicting-not-overwritten"])
    #expect(result.disagreements[0].detail == "The catalog marks identity 0x7E/0x7F conflicting; an observation does not settle which document is right.")
  }

  @Test func aDeviceTheCatalogDoesNotKnowIsReportedAndNothingIsWritten() {
    let result = draft(observation(["category": .string("0x70")]), inventedCatalog())

    #expect(result.outcome == .needsHuman)
    #expect(codes(result) == ["unknown-device"])
    #expect(result.changes.isEmpty)
    #expect(result.matched == nil)
    #expect(result.disagreements[0].detail.contains("0x70"))
    #expect(result.disagreements[0].detail == """
      Category 0x70, subcategory 0x7F and firmware 0x41 match no profile. A profile needs a name, aliases, an identity, capabilities, \
      an engine and sources, each backed by a public document or an observation.
      """)
  }

  @Test func aFirmwareNoIdentityCoversIsReportedAndNothingIsWritten() {
    let catalog = inventedCatalog(identity: #"{"category": "0x7E", "subcategory": "0x7F", "productKey": "0x00001A", "firmware": {"from": "0x30", "through": "0x40"}}"#)
    let result = draft(observation(), catalog)

    #expect(codes(result) == ["firmware-not-covered"])
    #expect(result.changes.isEmpty)
    #expect(result.disagreements[0].detail == "Category 0x7E, subcategory 0x7F is in the catalog, but no identity covers firmware 0x41. A maintainer decides whether to widen one.")
  }

  @Test func theIdentityIsMatchedByFirmwareAmongProfilesSharingACategory() {
    var catalog = ProfileCatalog(profiles: [:])
    catalog.profiles["1111"] = profile("1111", identities: #"[{"category": "0x7E", "subcategory": "0x7F", "firmware": {"from": "0x00", "through": "0x40"}}]"#)
    catalog.profiles["2222"] = profile("2222", identities: #"[{"category": "0x7E", "subcategory": "0x7F", "firmware": {"from": "0x41", "through": "0xFF"}}]"#)

    #expect(draft(observation(), catalog).matched?.model == "2222")
  }

  @Test func twoProfilesClaimingTheSameIdentityAreAmbiguous() {
    var catalog = ProfileCatalog(profiles: [:])
    catalog.profiles["1111"] = profile("1111", identities: #"[{"category": "0x7E", "subcategory": "0x7F"}]"#)
    catalog.profiles["2222"] = profile("2222", identities: #"[{"category": "0x7E", "subcategory": "0x7F"}]"#)
    let result = draft(observation(), catalog)

    #expect(codes(result) == ["ambiguous"])
    #expect(result.disagreements[0].detail == "2 profiles claim category 0x7E, subcategory 0x7F at firmware 0x41.")
  }

  @Test func aFileThatNamesAnotherProductThanTheMatchIsWarnedAbout() {
    let result = draft(observation(["model": .string("Some Other Product 1234")]), inventedCatalog())

    #expect(result.warnings.filter { $0.contains("different product") }.count == 1)
    #expect(!(String(decoding: Array(result.json.text.utf8), as: UTF8.self)).contains("Some Other Product"))
  }

  @Test func aFileThatNamesTheMatchedProductByModelOrNameIsNotWarnedAbout() {
    #expect(draft(observation(["model": .string("Item 9999 of the shelf")]), inventedCatalog()).warnings == [])
    #expect(draft(observation(["model": .string("Invented 9999 (Bench Unit)")]), inventedCatalog()).warnings == [])
    #expect(draft(observation(["model": .null]), inventedCatalog()).warnings == [])
  }

  @Test func theIdentityWasNotReportedWhenAFieldIsNull() {
    let result = draft(observation(["firmware": .null]), inventedCatalog())

    #expect(result.outcome == .noChange)
    #expect(result.warnings == ["The device's identity was not reported, so no profile was matched."])
  }

  @Test func anIdentityRequestThatWasNotAnsweredMeansNoProfileIsMatched() {
    let data = observation().setting(["checks", "1", "outcome"], to: .string("silent"))
    let result = draft(data, inventedCatalog())

    #expect(result.matched == nil)
    #expect(result.changes.isEmpty)
    #expect(result.warnings == ["The device's identity was not reported, so no profile was matched."])
  }

  @Test func aCheckThisToolDoesNotReadIsIgnoredWithAWarning() {
    let data = observation().setting(["checks", "3"], to: json(#"{"name": "Ping", "outcome": "answered", "detail": "x"}"#))

    #expect(draft(data, inventedCatalog()).warnings.first == "A check this tool does not read was ignored.")
  }

  @Test func theFirstOutcomeOfARepeatedCheckIsTheOneUsed() {
    let data = observation().setting(["checks", "3"], to: json(#"{"name": "ID Request", "outcome": "silent", "detail": "x"}"#))
    let result = draft(data, inventedCatalog())

    #expect(result.matched != nil)
    #expect(result.skipped.map(\.check) == ["ID Request"])
  }

  @Test func eachSkippedCheckIsListedOnce() {
    let data = observation().setting("checks", to: json("""
      [{"name": "ID Request", "outcome": "answered", "detail": "x"},
       {"name": "Status Request", "outcome": "silent", "detail": "x"},
       {"name": "Status Request", "outcome": "refused", "detail": "x"}]
      """))

    #expect(draft(data, inventedCatalog()).skipped == [SkippedCheck(check: "Status Request", reason: "outcome was silent; says nothing about the device")])
  }
}

struct EngineDraftTests {
  @Test func anEngineTheEntryGivesIsMarkedObserved() throws {
    let engine = try #require(change(draft(observation(), inventedCatalog()), entry: "engine"))

    #expect(engine.selector == json(#"{"engine": "i2cs", "category": "0x7E", "subcategory": "0x7F"}"#))
    #expect(engine.after["note"]?.string == "Seen on a device running firmware 0x41: Get Insteon Engine Version answered with i2CS.")
    #expect(engine.target == "engine i2CS 0x7E/0x7F")
  }

  @Test func aDifferentEngineIsADisagreementAndWritesNothing() {
    let result = draft(observation(["engine": .string("i2")]), inventedCatalog())

    #expect(codes(result) == ["engine-differs"])
    #expect(change(result, entry: "engine") == nil)
    #expect(result.disagreements[0].detail == "The device reported i2; the catalog gives i2CS for category 0x7E, subcategory 0x7F at firmware 0x41.")
  }

  @Test func aFirmwareNoEngineEntryCoversIsADisagreementAndWritesNothing() {
    let engines = #"[{"engine": "i2cs", "category": "0x7E", "subcategory": "0x7F", "firmware": {"only": ["0x42"]}}]"#
    let result = draft(observation(), inventedCatalog(engines: engines))

    #expect(codes(result) == ["firmware-not-covered"])
    #expect(change(result, entry: "engine") == nil)
    #expect(result.disagreements[0].detail == "No engine entry covers category 0x7E, subcategory 0x7F at firmware 0x41; the device reported i2CS.")
  }

  @Test func aProfileWithNoEngineEntriesIsReportedTheSameWay() {
    #expect(codes(draft(observation(), inventedCatalog(engines: "[]"))) == ["firmware-not-covered"])
  }

  @Test func anEngineAlreadyObservedOnThisFirmwareIsNotMarkedAgain() {
    let engines = #"[{"engine": "i2cs", "category": "0x7E", "subcategory": "0x7F", "verification": \#(observed(["0x41"]))}]"#
    let result = draft(observation(), inventedCatalog(engines: engines))

    #expect(change(result, entry: "engine") == nil)
    #expect(result.unchanged.map(\.target).contains("engine i2CS 0x7E/0x7F"))
  }

  @Test func aCheckThatWasNotAnsweredIsNotReadEvenIfTheDeviceFieldsAreFilled() {
    let data = observation().setting(["checks", "0", "outcome"], to: .string("silent"))
    let result = draft(data, inventedCatalog())

    #expect(change(result, entry: "engine") == nil)
    #expect(result.skipped.map(\.check).contains("Get Insteon Engine Version"))
  }

  @Test func anEngineTheDeviceDidNotReportIsNotRead() {
    #expect(change(draft(observation(["engine": .null]), inventedCatalog()), entry: "engine") == nil)
  }

  @Test func theEntryIsChosenByTheFirmwareItCovers() throws {
    let engines = """
      [{"engine": "i2", "category": "0x7E", "subcategory": "0x7F", "firmware": {"except": ["0x41"]}},
       {"engine": "i2cs", "category": "0x7E", "subcategory": "0x7F", "firmware": {"only": ["0x41"]}}]
      """
    let catalog = inventedCatalog(engines: engines)

    let marked = try #require(change(draft(observation(), catalog), entry: "engine"))
    #expect(marked.selector["engine"] == .string("i2cs"))
    #expect(codes(draft(observation(["firmware": .string("0x42")]), catalog)) == ["engine-differs"])
  }

  @Test func aConflictingEngineIsNeverOverwritten() {
    let engines = #"[{"engine": "i2cs", "category": "0x7E", "subcategory": "0x7F", "verification": {"status": "conflicting", "note": "Two documents disagree."}}]"#
    let result = draft(observation(), inventedCatalog(engines: engines))

    #expect(codes(result) == ["conflicting-not-overwritten"])
    #expect(result.disagreements[0].detail.hasPrefix("The catalog marks engine i2CS 0x7E/0x7F conflicting"))
  }
}

struct ProductKeyDraftTests {
  @Test func aKeyEqualToTheCatalogsIsMarkedObservedOnTheKey() throws {
    let key = try #require(change(draft(observation(), inventedCatalog()), entry: "identity", field: "productKeyVerification"))

    #expect(key.after["note"]?.string == "Seen on a device running firmware 0x41: Product Data Request reported product key 0x00001A.")
    #expect(key.target == "product key of identity 0x7E/0x7F")
  }

  @Test func theKeyMarkSitsNextToAnOlderNote() throws {
    let catalog = inventedCatalog(identity: """
      {"category": "0x7E", "subcategory": "0x7F", "productKey": "0x00001A", "productKeyVerification": {"status": "inferred", "note": "Read from a shared identity."}}
      """)
    let key = try #require(change(draft(observation(), catalog), entry: "identity", field: "productKeyVerification"))

    #expect(key.after["note"]?.string == "Seen on a device running firmware 0x41: Product Data Request reported product key 0x00001A. Read from a shared identity.")
  }

  @Test func aDifferentKeyIsADisagreementAndWritesNothing() {
    let data = observation().setting("productKey", to: .string("0x000050"))
    let result = draft(data, inventedCatalog())

    #expect(codes(result) == ["key-differs"])
    #expect(change(result, entry: "identity", field: "productKeyVerification") == nil)
    #expect(result.disagreements[0].detail == "The device reported product key 0x000050; the catalog gives 0x00001A for identity 0x7E/0x7F.")
  }

  @Test func aKeyForAnIdentityWithoutOneIsReportedNotAdded() {
    let result = draft(observation(), inventedCatalog(identity: #"{"category": "0x7E", "subcategory": "0x7F"}"#))

    #expect(codes(result) == ["key-not-in-catalog"])
    #expect(result.disagreements[0].detail == "The device reported product key 0x00001A; the catalog gives none for identity 0x7E/0x7F. Adding a value is a maintainer decision.")
  }

  @Test func noKeyReportedAgainstACatalogKeyIsADisagreement() {
    let result = draft(observation().setting("productKey", to: .string("none")), inventedCatalog())

    #expect(codes(result) == ["key-not-reported"])
    #expect(result.disagreements[0].detail == "Product Data Request was answered with no key; the catalog gives 0x00001A for identity 0x7E/0x7F.")
  }

  @Test func noKeyReportedAgainstACatalogThatSaysNoneIsMarked() throws {
    let catalog = inventedCatalog(identity: #"{"category": "0x7E", "subcategory": "0x7F", "productKey": "none"}"#)
    let key = try #require(change(draft(observation().setting("productKey", to: .string("none")), catalog), entry: "identity", field: "productKeyVerification"))

    #expect(key.after["note"]?.string == "Seen on a device running firmware 0x41: Product Data Request answered and reported no product key.")
  }

  @Test func noKeyReportedAgainstACatalogWithoutOneGoesIntoTheIdentityNote() throws {
    let catalog = inventedCatalog(identity: #"{"category": "0x7E", "subcategory": "0x7F"}"#)
    let result = draft(observation().setting("productKey", to: .string("none")), catalog)
    let identity = try #require(change(result, entry: "identity"))

    #expect(identity.after["note"]?.string?.hasSuffix(" Product Data Request answered and reported no product key.") == true)
    #expect(result.disagreements.isEmpty)
  }

  @Test func aSilentRequestLeavesTheKeyAlone() {
    let data = observation().setting("productKey", to: nil).setting(["checks", "2", "outcome"], to: .string("silent"))
    let result = draft(data, inventedCatalog())

    #expect(change(result, entry: "identity", field: "productKeyVerification") == nil)
    #expect(result.disagreements.isEmpty)
  }

  @Test func aKeyAlreadyObservedOnThisFirmwareIsNotMarkedAgain() {
    let catalog = inventedCatalog(identity: #"{"category": "0x7E", "subcategory": "0x7F", "productKey": "0x00001A", "productKeyVerification": \#(observed(["0x41"]))}"#)
    let result = draft(observation(), catalog)

    #expect(change(result, entry: "identity", field: "productKeyVerification") == nil)
    #expect(result.unchanged.map(\.target).contains("product key of identity 0x7E/0x7F"))
  }
}

struct ContributorTextTests {
  @Test func theContributorsNoteAndDetailsNeverReachAChangeOrTheReport() {
    let data = observation()
      .setting("note", to: .string("Zebra pattern marker note."))
      .setting(["checks", "1", "detail"], to: .string("Zebra pattern marker detail."))

    #expect(!draft(data, inventedCatalog()).json.text.contains("Zebra"))
  }
}
