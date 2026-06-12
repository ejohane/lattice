// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "LatticeCapture",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "LatticeCapture", targets: ["LatticeCapture"])
  ],
  targets: [
    .executableTarget(
      name: "LatticeCapture",
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("Carbon")
      ]
    )
  ]
)
