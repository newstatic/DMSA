// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "DMSA",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DMSA", targets: ["DMSA"])
    ],
    dependencies: [
        // ObjectBox Swift 暂时注释，因为需要特殊安装步骤
        // .package(url: "https://github.com/objectbox/objectbox-swift", from: "1.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "DMSA",
            dependencies: [
                // .product(name: "ObjectBox", package: "objectbox-swift"),
            ],
            path: "Sources/DMSA",
            resources: [
                .copy("Resources/DMSA.entitlements"),
                .process("Resources/en.lproj"),
                .process("Resources/zh-Hans.lproj")
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Sources/DMSA/Resources/Info.plist"])
            ]
        ),
        .testTarget(
            name: "DMSATests",
            dependencies: ["DMSA"],
            path: "Tests/DMSATests"
        ),
    ]
)
