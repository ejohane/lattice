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
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.3")
  ],
  targets: [
    .executableTarget(
      name: "LatticeCapture",
      dependencies: [
        .product(name: "Sparkle", package: "Sparkle")
      ],
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("Carbon")
      ]
    )
  ]
)
