import AppKit
import SwiftUI

/// Ventana con todos los avisos que ha dado Garita, lo más reciente primero.
struct VentanaHistorial: View {
    @Environment(ModeloApp.self) private var modelo

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if modelo.historial.isEmpty {
                ContentUnavailableView("Sin avisos",
                                       systemImage: "clock.arrow.circlepath",
                                       description: Text("Aquí aparecerán las notificaciones de Garita."))
            } else {
                List(modelo.historial) { aviso in
                    FilaAviso(aviso: aviso)
                }
            }

            Divider()
            HStack {
                Text(modelo.historial.count == 1 ? "1 aviso" : "\(modelo.historial.count) avisos")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Mostrar archivo") {
                    NSWorkspace.shared.activateFileViewerSelecting([Historial.archivo])
                }
                .help("historial.json en el Finder")
                Button("Borrar historial…", role: .destructive) {
                    if confirmarBorrado() { modelo.borrarHistorial() }
                }
                .disabled(modelo.historial.isEmpty)
            }
            .padding(10)
        }
        .frame(minWidth: 360, minHeight: 300)
    }

    private func confirmarBorrado() -> Bool {
        let alerta = NSAlert()
        alerta.messageText = "¿Borrar el historial de avisos?"
        alerta.informativeText = "Se borrarán los \(modelo.historial.count) avisos. No afecta a la cuarentena."
        alerta.alertStyle = .warning
        alerta.addButton(withTitle: "Borrar")
        alerta.addButton(withTitle: "Cancelar")
        return alerta.runModal() == .alertFirstButtonReturn
    }
}

/// Un aviso: icono, título, fecha y texto.
private struct FilaAviso: View {
    let aviso: Aviso

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: aviso.importante ? "exclamationmark.shield.fill" : "info.circle")
                .foregroundStyle(aviso.importante ? .red : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(aviso.titulo).bold()
                    Spacer()
                    Text(aviso.fecha.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(aviso.texto)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
    }
}
