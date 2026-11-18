import Foundation
import Testing

/// `catalog ingest` reads files and runs git; it never reaches a network.
struct NoNetworkTests {
  static let sources: [URL] = {
    let manager = FileManager.default
    let folders = ["Sources/CatalogIngest", "Sources/catalog"]
    var files: [URL] = []

    for folder in folders {
      let url = Fixtures.repository.appendingPathComponent(folder)
      for name in (try? manager.contentsOfDirectory(atPath: url.path)) ?? [] where name.hasSuffix(".swift") {
        if folder == "Sources/catalog", !name.hasPrefix("Ingest") { continue }
        files.append(url.appendingPathComponent(name))
      }
    }

    return files
  }()

  static let allowedImports: Set<String> = ["ArgumentParser", "CatalogBuild", "CatalogIngest", "CatalogJSON", "CatalogRules", "CatalogSchema", "Foundation"]

  @Test func theIngestSourcesAreThere() {
    #expect(Self.sources.count >= 5)
  }

  @Test func theIngestSourcesImportOnlyWhatTheyNeed() throws {
    for file in Self.sources {
      let text = try String(contentsOf: file, encoding: .utf8)
      let imports = text.split(separator: "\n").filter { $0.hasPrefix("import ") || $0.hasPrefix("@testable import ") }.map { String($0.split(separator: " ").last ?? "") }

      for name in imports {
        #expect(Self.allowedImports.contains(name), "\(file.lastPathComponent) imports \(name)")
      }
    }
  }

  @Test func theIngestSourcesNameNoNetworkApi() throws {
    let banned = ["URLSession", "URLRequest", "NSURLConnection", "CFNetwork", "CFSocket", "NWConnection", "FoundationNetworking", "URLSessionConfiguration"]

    for file in Self.sources {
      let text = try String(contentsOf: file, encoding: .utf8)

      for word in banned {
        #expect(!text.contains(word), "\(file.lastPathComponent) names \(word)")
      }
    }
  }
}
