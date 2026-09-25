import SwiftUI

/// Muestra la antigüedad de las firmas de virus y el botón para actualizarlas.
struct SeccionFirmas: View {
    @Environment(ModeloApp.self) private var modelo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Firmas de virus").font(.subheadline.bold())

            if let motor = modelo.motor, let firmas = motor.firmas {
                let antiguas = motor.firmasAntiguas
                Label {
                    Text("Versión \(firmas.numero), publicadas \(firmas.fecha.formatted(.relative(presentation: .named)))")
                } icon: {
                    Image(systemName: antiguas ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(antiguas ? .orange : .green)
                }
                .help(firmas.fecha.formatted(date: .complete, time: .shortened))
            } else {
                Label("Aún no hay firmas descargadas", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }

            if let ultima = modelo.ultimaComprobacion {
                Text("Última comprobación: \(ultima.formatted(.relative(presentation: .named))) · se actualizan solas cada 12 h")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Actualizar firmas") {
                    modelo.actualizarFirmas()
                }
                .disabled(modelo.actualizandoFirmas || modelo.motor?.freshclam == nil)

                if modelo.actualizandoFirmas {
                    ProgressView().controlSize(.small)
                    Text("Descargando…").font(.caption).foregroundStyle(.secondary)
                }
            }

            if let mensaje = modelo.mensajeFirmas {
                Text(mensaje)
                    .font(.caption)
                    .foregroundStyle(modelo.errorFirmas ? .red : .secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
