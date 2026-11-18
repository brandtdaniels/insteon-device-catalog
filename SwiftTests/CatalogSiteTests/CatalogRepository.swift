import Foundation

/// The catalog repository this test file sits in.
enum CatalogRepository {
  static let url = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}
