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
    .library(name: "CatalogRules", targets: ["CatalogRules"]),
    .library(name: "CatalogBuild", targets: ["CatalogBuild"]),
    .library(name: "CatalogSite", targets: ["CatalogSite"]),
    .executable(name: "catalog", targets: ["catalog"]),
    .executable(name: "catalog-dev", targets: ["catalog-dev"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMinor(from: "1.8.2"))
  ],
  targets: [
    .target(name: "CatalogJSON", path: "Sources/CatalogJSON"),
    .target(name: "CatalogSchema", dependencies: ["CatalogJSON"], path: "Sources/CatalogSchema"),
    .target(name: "CatalogRules", dependencies: ["CatalogJSON"], path: "Sources/CatalogRules"),
    .target(name: "CatalogBuild", dependencies: ["CatalogJSON", "CatalogSchema", "CatalogRules"], path: "Sources/CatalogBuild"),
    .target(name: "CatalogSite", dependencies: ["CatalogJSON", "CatalogBuild"], path: "Sources/CatalogSite"),
    .executableTarget(
      name: "catalog",
      dependencies: [
        "CatalogBuild",
        "CatalogSite",
        .product(name: "ArgumentParser", package: "swift-argument-parser")
      ],
      path: "Sources/catalog"
    ),
    .target(name: "CatalogSweep", dependencies: ["CatalogJSON", "CatalogBuild"], path: "Sources/CatalogSweep"),
    .executableTarget(
      name: "catalog-dev",
      dependencies: [
        "CatalogSweep",
        .product(name: "ArgumentParser", package: "swift-argument-parser")
      ],
      path: "Sources/catalog-dev"
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
    ),
    .testTarget(
      name: "CatalogBuildTests",
      dependencies: ["CatalogJSON", "CatalogSchema", "CatalogBuild"],
      path: "SwiftTests/CatalogBuildTests"
    ),
    .testTarget(
      name: "CatalogSweepTests",
      dependencies: ["CatalogJSON", "CatalogBuild", "CatalogSweep"],
      path: "SwiftTests/CatalogSweepTests"
    ),
    .testTarget(
      name: "CatalogSiteTests",
      dependencies: ["CatalogJSON", "CatalogBuild", "CatalogSite"],
      path: "SwiftTests/CatalogSiteTests"
    ),
    .testTarget(
      name: "CatalogRulesTests",
      dependencies: ["CatalogJSON", "CatalogSchema", "CatalogRules", "CatalogBuild"],
      path: "SwiftTests/CatalogRulesTests"
    )
  ]
)
