// swift-tools-version: 6.3

import PackageDescription

// The Swift sources and tests sit in `Sources` and `SwiftTests`. The Python tests keep `tests`,
// which a case-insensitive file system can't tell apart from SwiftPM's default `Tests`.
let package = Package(
  name: "insteon-device-catalog",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "CatalogJSON", targets: ["CatalogJSON"]),
    .executable(name: "catalog", targets: ["catalog"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMinor(from: "1.8.2"))
  ],
  targets: [
    .target(name: "CatalogJSON", path: "Sources/CatalogJSON"),
    .executableTarget(
      name: "catalog",
      dependencies: [.product(name: "ArgumentParser", package: "swift-argument-parser")],
      path: "Sources/catalog"
    ),
    .testTarget(
      name: "CatalogJSONTests",
      dependencies: ["CatalogJSON"],
      path: "SwiftTests/CatalogJSONTests"
    )
  ]
)
