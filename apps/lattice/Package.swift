// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Lattice",
  platforms: [
    .macOS(.v14),
    .iOS(.v17)
  ],
  products: [
    .executable(name: "Lattice", targets: ["Lattice"]),
    .library(name: "LatticeCore", targets: ["LatticeCore"]),
    .library(name: "LatticeEditor", targets: ["LatticeEditor"]),
    .library(name: "LatticeShared", targets: ["LatticeShared"]),
    .library(name: "LatticeMacCore", targets: ["LatticeMacCore"])
  ],
  dependencies: [
    .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.4.0"),
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.3")
  ],
  targets: [
    .target(
      name: "LatticeCore",
      dependencies: ["LatticeEditor"],
      linkerSettings: [
        .linkedLibrary("sqlite3"),
        .linkedFramework("EventKit")
      ]
    ),
    .target(
      name: "LatticeEditor"
    ),
    .target(
      name: "LatticeMacCore",
      dependencies: ["LatticeEditor"]
    ),
    .target(
      name: "LatticeShared",
      dependencies: [
        "LatticeCore",
        "LatticeEditor"
      ],
      resources: [
        .process("Resources")
      ]
    ),
    .target(
      name: "LatticeTestSupport",
      dependencies: ["LatticeCore"],
      path: "Tests/LatticeTestSupport"
    ),
    .executableTarget(
      name: "Lattice",
      dependencies: [
        .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
        "LatticeEditor",
        "LatticeMacCore",
        .product(name: "Sparkle", package: "Sparkle")
      ],
      linkerSettings: [
        .linkedFramework("AppKit")
      ]
    ),
    .testTarget(
      name: "LatticeMacCoreTests",
      dependencies: [
        .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
        "Lattice",
        "LatticeMacCore"
      ]
    ),
    .testTarget(
      name: "LatticeCoreTests",
      dependencies: [
        "LatticeCore",
        "LatticeEditor",
        "LatticeTestSupport"
      ]
    ),
    .testTarget(
      name: "LatticeSharedTests",
      dependencies: [
        "LatticeShared",
        "LatticeTestSupport"
      ]
    )
  ]
)
