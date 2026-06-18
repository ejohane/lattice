// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Lattice",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "Lattice", targets: ["Lattice"]),
    .library(name: "LatticeCore", targets: ["LatticeCore"])
  ],
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.3")
  ],
  targets: [
    .target(
      name: "LatticeCore"
    ),
    .executableTarget(
      name: "Lattice",
      dependencies: [
        "LatticeCore",
        .product(name: "Sparkle", package: "Sparkle")
      ],
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("Carbon")
      ]
    ),
    .testTarget(
      name: "LatticeCoreTests",
      dependencies: ["LatticeCore"]
    )
  ]
)
