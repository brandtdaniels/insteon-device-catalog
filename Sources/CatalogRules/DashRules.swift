/// The dash rule: no data file holds an em dash or an en dash.
public enum DashRules {
  /// The line for a file whose text holds an em dash or an en dash, or none.
  ///
  /// - Parameters:
  ///   - file: The path from the repository root, such as `devices/2852.json`.
  ///   - text: The file's contents.
  public static func problems(file: String, text: String) -> [String] {
    text.hasEmOrEnDash ? ["\(file): has an em or en dash; use a hyphen, comma or colon"] : []
  }
}
