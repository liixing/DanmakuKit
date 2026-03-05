// swift-tools-version:5.1
import PackageDescription

let package = Package(
    name: "DanmakuKit",
    platforms: [.iOS(.v10),.tvOS(.v13)],
    products: [
        .library(name: "DanmakuKit", targets: ["DanmakuKit"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "DanmakuKit", dependencies:[])
    ]
)

