// swift-tools-version: 6.3

import PackageDescription

// The Swift sources and tests sit in `Sources` and `SwiftTests`. The Python tests keep `tests`,
// which a case-insensitive file system can't tell apart from SwiftPM's default `Tests`.
let package = Package(
  name: "insteon-device-catalog",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "CatalogJSON", targets: ["CatalogJSON"]),
    .library(name: "CatalogSchema", targets: ["CatalogSchema"]),
    .executable(name: "catalog", targets: ["catalog"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMinor(from: "1.8.2"))
  ],
  targets: [
    .target(name: "CatalogJSON", path: "Sources/CatalogJSON"),
    .target(name: "CatalogSchema", dependencies: ["CatalogJSON"], path: "Sources/CatalogSchema"),
    .executableTarget(
      name: "catalog",
      dependencies: [.product(name: "ArgumentParser", package: "swift-argument-parser")],
      path: "Sources/catalog"
    ),
    .testTarget(
      name: "CatalogJSONTests",
      dependencies: ["CatalogJSON"],
      path: "SwiftTests/CatalogJSONTests"
    ),
    .testTarget(
      name: "CatalogSchemaTests",
      dependencies: ["CatalogJSON", "CatalogSchema"],
      path: "SwiftTests/CatalogSchemaTests"
    )
  ]
)
