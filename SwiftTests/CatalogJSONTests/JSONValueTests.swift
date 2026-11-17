import CatalogJSON
import Testing

struct JSONValueTests {
  @Test func objectsKeepMemberOrder() {
    let object = JSONValue.object([
      JSONMember(key: "b", value: .int(1)),
      JSONMember(key: "a", value: .int(2))
    ])
    guard case .object(let members) = object else { return }
    #expect(members.map(\.key) == ["b", "a"])
  }
}
