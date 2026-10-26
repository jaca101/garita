import SwiftUI

/// Versión de Garita, sus actualizaciones (ver Actualizaciones.swift) y cómo
/// apoyar el proyecto.
struct SeccionActualizaciones: View {
    @Environment(ModeloApp.self) private var modelo

    var body: some View {
        @Bindable var actualizaciones = modelo.actualizaciones
        VStack(alignment: .leading, spacing: 8) {
            Text("Garita \(actualizaciones.version)").font(.subheadline.bold())

            Toggle("Buscar actualizaciones automáticamente", isOn: $actualizaciones.automaticas)
                .help("Una vez al día. Antes de instalar una versión nueva, Garita pregunta.")

            Button("Buscar actualizaciones…") {
                actualizaciones.buscarAhora()
            }
            .disabled(!actualizaciones.puedeBuscar)

            Divider()

            Text("Garita es gratis, no tiene publicidad y no envía tus datos a ningún sitio. Si te resulta útil, puedes apoyar su desarrollo:")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                Link(destination: Enlaces.kofi) {
                    Label("Una vez (Ko-fi)", systemImage: "cup.and.saucer")
                }
                .help("Donativo puntual con PayPal o tarjeta")
                Link(destination: Enlaces.liberapay) {
                    Label("Cada mes (Liberapay)", systemImage: "heart")
                }
                .help("Donativo mensual; Liberapay es una organización sin ánimo de lucro")
            }
            .font(.callout)

            Link(destination: Enlaces.telegram) {
                Label("Dudas o ayuda: @jaca101 en Telegram", systemImage: "paperplane")
            }
            .font(.callout)
        }
    }
}

/// Enlaces del proyecto (los mismos usuarios que en .github/FUNDING.yml).
enum Enlaces {
    static let kofi = URL(string: "https://ko-fi.com/jaca101")!
    static let liberapay = URL(string: "https://liberapay.com/jaca101/")!
    static let telegram = URL(string: "https://t.me/jaca101")!
}
