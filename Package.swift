// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "DownloadsSyncApp",
    platforms: [
        .macOS(.v11)
    ],
    targets: [
        .executableTarget(
            name: "DownloadsSyncApp",
            path: "DownloadsSyncApp"
        )
    ]
)
