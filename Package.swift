// swift-tools-version: 6.0
// Garita — interfaz de barra de menú para ClamAV en macOS.
// Se compila con Swift Package Manager (sin proyecto de Xcode) y
// se empaqueta como .app con el script construir.sh.

import PackageDescription

let package = Package(
    name: "Garita",
    platforms: [.macOS(.v15)],
    dependencies: [
        // Actualizaciones automáticas (https://sparkle-project.org).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Garita",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Garita",
            // Sparkle.framework va en Garita.app/Contents/Frameworks (lo copia construir.sh).
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        )
    ]
)
