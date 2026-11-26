import Foundation

#if canImport(JavaScriptCore)
import JavaScriptCore
#endif

/// Runs the page's script outside a browser: in JavaScriptCore where the platform has it, and in
/// Node.js where it doesn't.
enum PageScript {
  struct Failure: Error, CustomStringConvertible {
    let description: String
  }

  static let source: String = (try? String(contentsOf: CatalogRepository.url.appendingPathComponent("templates/detail.js"), encoding: .utf8)) ?? ""

  /// What `InsteonDetails.render` gives for each profile, both given as JSON texts.
  static func render(profiles: [String], commandSets: [String]) throws -> [String] {
    let program = """
      \(source)
      ;var catalogResult = (function (profiles, commandSets) {
        return JSON.stringify(profiles.map(function (profile) { return InsteonDetails.render(profile, commandSets); }));
      })([\(profiles.joined(separator: ","))], [\(commandSets.joined(separator: ","))]);
      if (typeof process !== "undefined") { process.stdout.write(catalogResult); }
      catalogResult;
      """

    return try JSONDecoder().decode([String].self, from: Data(try evaluate(program).utf8))
  }

  #if canImport(JavaScriptCore)
  private static func evaluate(_ program: String) throws -> String {
    guard let context = JSContext() else { throw Failure(description: "JavaScriptCore gave no context") }

    let value = context.evaluateScript(program)

    if let exception = context.exception { throw Failure(description: "the script threw \(exception)") }
    guard let text = value?.toString() else { throw Failure(description: "the script gave nothing") }

    return text
  }
  #else
  private static func evaluate(_ program: String) throws -> String {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("catalog-script-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let script = folder.appendingPathComponent("run.js")
    let output = folder.appendingPathComponent("out.txt")
    try Data(program.utf8).write(to: script)
    try Data().write(to: output)

    // The output goes to a file, so a large result can't fill a pipe nobody is reading.
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", script.path]
    process.standardOutput = try FileHandle(forWritingTo: output)
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      throw Failure(description: "node exited with \(process.terminationStatus); the page tests need Node.js on this platform")
    }

    return String(decoding: try Data(contentsOf: output), as: UTF8.self)
  }
  #endif
}
