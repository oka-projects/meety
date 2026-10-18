// swift-tools-version: 6.0
// MeetyKit: tudo do Meety que não é o alvo do app.
//
//   ExceptionCatcher  Objective-C: captura as exceções do AVFoundation, que o Swift não captura.
//   MeetyCore         modelos, biblioteca, motor Python, áudio, gravação, modelos de IA, resumos.
//   MeetyUI           as telas (SwiftUI).
import PackageDescription

let package = Package(
    name: "MeetyKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MeetyCore", targets: ["MeetyCore"]),
        .library(name: "MeetyUI", targets: ["MeetyUI"]),
    ],
    dependencies: [
        // Separação de falantes no Neural Engine (Core ML), sem token do Hugging Face.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.10.0"),
    ],
    targets: [
        .target(name: "ExceptionCatcher"),
        .target(
            name: "MeetyCore",
            dependencies: [
                "ExceptionCatcher",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "MeetyUI",
            dependencies: ["MeetyCore"],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MeetyCoreTests",
            dependencies: ["MeetyCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
