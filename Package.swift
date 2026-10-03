// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PasteFlow",
    platforms: [.macOS(.v14)],
    targets: [
        // 순수 로직(큐·DB 등) — 테스트 대상
        .target(name: "PasteFlowCore"),
        // 앱 본체(AppKit) — scripts/build.sh가 .app으로 조립·서명
        .executableTarget(name: "PasteFlow", dependencies: ["PasteFlowCore"]),
        .testTarget(name: "PasteFlowCoreTests", dependencies: ["PasteFlowCore"]),
    ],
    swiftLanguageModes: [.v5]
)
