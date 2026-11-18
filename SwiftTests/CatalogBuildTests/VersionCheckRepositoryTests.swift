import CatalogBuild
import Foundation
import Testing

/// The version rule against real git history in a temporary repository.
struct VersionCheckRepositoryTests {
  /// Runs the rule the way the command does: the base is a commit, the current state is `HEAD` and `VERSION` on disk.
  static func problem(in repository: TemporaryRepository, base: String) -> VersionProblem? {
    do {
      try VersionCheck(git: ProcessGit(root: repository.url)).verify(base: base, root: repository.url)
      return nil
    } catch {
      return error
    }
  }

  @Test func checksTwoRealCommits() throws {
    let repository = try TemporaryRepository()
    try repository.write("VERSION", "0.10\n")
    try repository.write("schema/device-profile.json", "{}\n")
    try repository.write("devices/a.json", "{}\n")
    let base = try repository.commit("base")

    try repository.write("devices/a.json", #"{"name": "a"}"#)
    try repository.commit("data only")
    #expect(Self.problem(in: repository, base: base) == nil)

    try repository.write("schema/device-profile.json", #"{"title": "x"}"#)
    try repository.commit("schema without a bump")
    #expect(Self.problem(in: repository, base: base) == .schemaChangedWithoutBump)

    try repository.write("VERSION", "0.11\n")
    try repository.commit("bump")
    #expect(Self.problem(in: repository, base: base) == nil)

    try repository.write("VERSION", "0.9\n")
    try repository.commit("lower")
    #expect(Self.problem(in: repository, base: base) == .wentDown)
  }

  @Test func reportsABaseGitDoesNotKnow() throws {
    let repository = try TemporaryRepository()
    try repository.write("VERSION", "0.10\n")
    try repository.commit("base")
    let missing = String(repeating: "0", count: 40)
    #expect(Self.problem(in: repository, base: missing) == .cannotCompare(base: missing))
  }

  @Test func reportsAMissingVersionFile() throws {
    let repository = try TemporaryRepository()
    try repository.write("devices/a.json", "{}\n")
    let base = try repository.commit("base")
    #expect(Self.problem(in: repository, base: base) == .unreadable(file: "VERSION"))
  }
}
