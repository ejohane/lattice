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
    .library(name: "LatticeShared", targets: ["LatticeShared"])
  ],
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.3")
  ],
  targets: [
    .target(
      name: "LatticeCore",
      linkerSettings: [
        .linkedLibrary("sqlite3"),
        .linkedFramework("EventKit")
      ]
    ),
    .target(
      name: "LatticeEditor",
      dependencies: ["LatticeCore"]
    ),
    .target(
      name: "LatticeShared",
      dependencies: [
        "LatticeCore",
        "LatticeEditor"
      ]
    ),
    .executableTarget(
      name: "Lattice",
      dependencies: [
        "LatticeShared",
        .product(name: "Sparkle", package: "Sparkle")
      ],
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("Carbon")
      ]
    ),
    .testTarget(
      name: "LatticeCoreTests",
      dependencies: [
        "LatticeCore",
        "LatticeEditor"
      ]
    ),
    .testTarget(
      name: "LatticeSharedTests",
      dependencies: ["LatticeShared"]
    )
  ]
)
