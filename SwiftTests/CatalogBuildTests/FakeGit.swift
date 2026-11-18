import CatalogBuild

/// A ``GitReading`` that answers from tables, so a rule test needs no repository.
struct FakeGit: GitReading {
  /// File contents keyed by `"<revision>:<path>"`. A missing key is a file git can't show.
  var files: [String: String] = [:]
  /// The paths changed between any two revisions, or `nil` when git can't compare them.
  var changed: [String]? = []

  func contents(of path: String, at revision: String) -> String? {
    files["\(revision):\(path)"]
  }

  func changedPaths(from base: String, to head: String) throws(GitError) -> [String] {
    guard let changed else { throw GitError(arguments: ["diff", "--name-only", base, head]) }
    return changed
  }
}
