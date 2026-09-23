// swift-tools-version: 6.0
// Garita — interfaz de barra de menú para ClamAV en macOS.
// Se compila con Swift Package Manager (sin proyecto de Xcode) y
// se empaqueta como .app con el script construir.sh.

import PackageDescription

let package = Package(
    name: "Garita",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Garita",
            path: "Sources/Garita"
        )
    ]
)
