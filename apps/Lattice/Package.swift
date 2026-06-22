// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Lattice",
  platforms: [
    .macOS(.v14),
    .iOS(.v17)
  ],
  products: [
    .library(name: "LatticeCore", targets: ["LatticeCore"]),
    .library(name: "LatticeEditor", targets: ["LatticeEditor"])
  ],
  dependencies: [],
  targets: [
    .target(
      name: "LatticeCore"
    ),
    .target(
      name: "LatticeEditor"
    ),
    .testTarget(
      name: "LatticeCoreTests",
      dependencies: ["LatticeCore"]
    ),
    .testTarget(
      name: "LatticeEditorTests",
      dependencies: ["LatticeEditor"]
    )
  ]
)
