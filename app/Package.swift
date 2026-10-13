// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MacDownloadManager",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DownloadCore"),
        .executableTarget(name: "mdm-native-host", dependencies: ["DownloadCore"]),
        .executableTarget(name: "MacDownloadManager", dependencies: ["DownloadCore"]),
    ]
)
