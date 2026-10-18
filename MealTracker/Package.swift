// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MealTrackerCore",
    defaultLocalization: "sv",
    platforms: [.iOS("18.0"), .macOS(.v13)],
    products: [
        .library(name: "MealTrackerCore", targets: ["MealTrackerCore"]),
        .library(name: "MealTrackerCatalog", targets: ["MealTrackerCatalog"]),
        .library(name: "MealTrackerDiary", targets: ["MealTrackerDiary"]),
        .library(name: "MealTrackerOpenFoodFacts", targets: ["MealTrackerOpenFoodFacts"]),
        .library(name: "MealTrackerLocalization", targets: ["MealTrackerLocalization"]),
        .library(name: "MealTrackerHealth", targets: ["MealTrackerHealth"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1")
    ],
    targets: [
        .target(name: "MealTrackerHealth"),
        .testTarget(name: "MealTrackerHealthTests", dependencies: ["MealTrackerHealth"]),
        .target(name: "MealTrackerCore", path: "Sources/MealTrackerCore"),
        .target(name: "MealTrackerCatalog", dependencies: ["MealTrackerCore", .product(name: "GRDB", package: "GRDB.swift")], resources: [.copy("Resources/DevelopmentPack")]),
        .target(name: "MealTrackerDiary", dependencies: ["MealTrackerCore", .product(name: "GRDB", package: "GRDB.swift")]),
        .target(name: "MealTrackerOpenFoodFacts", dependencies: ["MealTrackerCore", .product(name: "GRDB", package: "GRDB.swift")], resources: [.process("Resources")]),
        .target(name: "MealTrackerLocalization", dependencies: ["MealTrackerCore"], resources: [.process("Resources")]),
        .testTarget(name: "MealTrackerStorageTests", dependencies: ["MealTrackerCatalog", "MealTrackerDiary", "MealTrackerOpenFoodFacts", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "MealTrackerOpenFoodFactsTests", dependencies: ["MealTrackerOpenFoodFacts", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "MealTrackerLocalizationTests", dependencies: ["MealTrackerLocalization"]),
        .testTarget(name: "MealTrackerCoreTests", dependencies: ["MealTrackerCore"], path: "Tests/MealTrackerCoreTests", resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v5]
)
