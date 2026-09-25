import AppKit
import SwiftUI

/// Confirmación antes de marcar algo como seguro (es una decisión importante:
/// Garita dejará de avisar de ese archivo).
@MainActor
func confirmarSeguro(nombre: String, amenaza: String) -> Bool {
    let alerta = NSAlert()
    alerta.messageText = "¿Marcar «\(nombre)» como seguro?"
    alerta.informativeText = """
    ClamAV lo detecta como «\(amenaza)». Garita dejará de avisar de este archivo \
    mientras no cambie (se reconoce por su huella SHA-256; si cambia un solo byte, \
    se vuelve a analizar).

    Hazlo solo si has comprobado que es un falso positivo, por ejemplo comparando \
    su huella con la que publica el fabricante.
    """
    alerta.alertStyle = .warning
    alerta.addButton(withTitle: "Marcar como seguro")
    alerta.addButton(withTitle: "Cancelar")
    NSApplication.shared.activate()
    return alerta.runModal() == .alertFirstButtonReturn
}

/// Enlace «N archivos marcados como seguros…» con la lista en un globo.
struct EnlaceSeguros: View {
    @Environment(ModeloApp.self) private var modelo
    @State private var mostrar = false

    var body: some View {
        if !modelo.seguros.isEmpty {
            let n = modelo.seguros.count
            Button(n == 1 ? "1 archivo marcado como seguro…" : "\(n) archivos marcados como seguros…") {
                mostrar = true
            }
            .buttonStyle(.link)
            .font(.caption)
            .popover(isPresented: $mostrar, arrowEdge: .trailing) {
                ListaSeguros()
                    .environment(modelo)
            }
        }
    }
}

/// Los archivos seguros, con su huella y un botón para quitarlos de la lista.
private struct ListaSeguros: View {
    @Environment(ModeloApp.self) private var modelo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Archivos marcados como seguros").font(.headline)
            Text("Garita no avisa de ellos mientras no cambien.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(modelo.seguros) { seguro in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(seguro.nombre).bold()
                                Text("\(seguro.amenaza) · marcado \(seguro.fecha.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(seguro.sha256)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            .help(seguro.ruta)
                            Spacer()
                            Button("Quitar") { modelo.quitarSeguro(seguro) }
                                .controlSize(.small)
                                .help("Volver a avisar de este archivo")
                        }
                    }
                }
            }
            .frame(maxHeight: 320)
        }
        .padding()
        .frame(width: 520)
    }
}
