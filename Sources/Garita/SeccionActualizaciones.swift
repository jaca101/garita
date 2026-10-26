import SwiftUI

/// Versión de Garita y sus actualizaciones (ver Actualizaciones.swift).
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
        }
    }
}
