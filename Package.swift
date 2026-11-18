// swift-tools-version: 6.3

import PackageDescription

// The Swift sources and tests sit in `Sources` and `SwiftTests`. `CatalogTestSupport` holds the
// cases and helpers the tests share; it is not a product.
let package = Package(
  name: "insteon-device-catalog",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "CatalogJSON", targets: ["CatalogJSON"]),
    .library(name: "CatalogSchema", targets: ["CatalogSchema"]),
    .library(name: "CatalogRules", targets: ["CatalogRules"]),
    .library(name: "CatalogBuild", targets: ["CatalogBuild"]),
    .library(name: "CatalogSite", targets: ["CatalogSite"]),
    .library(name: "CatalogIngest", targets: ["CatalogIngest"]),
    .executable(name: "catalog", targets: ["catalog"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMinor(from: "1.8.2")),
    .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMinor(from: "5.0.3"))
  ],
  targets: [
    .target(name: "CatalogJSON", path: "Sources/CatalogJSON"),
    .target(name: "CatalogSchema", dependencies: ["CatalogJSON"], path: "Sources/CatalogSchema"),
    .target(name: "CatalogRules", dependencies: ["CatalogJSON"], path: "Sources/CatalogRules"),
    .target(
      name: "CatalogBuild",
      dependencies: ["CatalogJSON", "CatalogSchema", "CatalogRules", .product(name: "Crypto", package: "swift-crypto")],
      path: "Sources/CatalogBuild"
    ),
    .target(name: "CatalogSite", dependencies: ["CatalogJSON", "CatalogBuild"], path: "Sources/CatalogSite"),
    .target(
      name: "CatalogIngest",
      dependencies: ["CatalogJSON", "CatalogSchema", "CatalogRules", "CatalogBuild"],
      path: "Sources/CatalogIngest"
    ),
    .executableTarget(
      name: "catalog",
      dependencies: [
        "CatalogBuild",
        "CatalogSite",
        "CatalogIngest",
        .product(name: "ArgumentParser", package: "swift-argument-parser")
      ],
      path: "Sources/catalog"
    ),
    .target(
      name: "CatalogTestSupport",
      dependencies: ["CatalogJSON", "CatalogBuild"],
      path: "SwiftTests/CatalogTestSupport"
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
      dependencies: ["CatalogJSON", "CatalogSchema", "CatalogBuild", "CatalogTestSupport"],
      path: "SwiftTests/CatalogBuildTests"
    ),
    .testTarget(
      name: "CatalogSiteTests",
      dependencies: ["CatalogJSON", "CatalogBuild", "CatalogSite"],
      path: "SwiftTests/CatalogSiteTests",
      exclude: ["Fixtures"]
    ),
    .testTarget(
      name: "CatalogIngestTests",
      dependencies: ["CatalogJSON", "CatalogSchema", "CatalogBuild", "CatalogIngest", "CatalogTestSupport"],
      path: "SwiftTests/CatalogIngestTests",
      exclude: ["Golden"]
    ),
    .testTarget(
      name: "CatalogRulesTests",
      dependencies: ["CatalogJSON", "CatalogSchema", "CatalogRules", "CatalogBuild"],
      path: "SwiftTests/CatalogRulesTests"
    )
  ]
)
