import AppKit
import SwiftUI

/// Lista de archivos en cuarentena, con opciones para restaurarlos o eliminarlos.
struct SeccionCuarentena: View {
    @Environment(ModeloApp.self) private var modelo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Cuarentena").font(.subheadline.bold())
                if !modelo.cuarentena.isEmpty {
                    Text("\(modelo.cuarentena.count)")
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .background(.orange.opacity(0.3), in: Capsule())
                }
                Spacer()
                Button("Abrir carpeta", systemImage: "folder") {
                    NSWorkspace.shared.open(Cuarentena.carpeta)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Mostrar la carpeta de cuarentena en el Finder")
                .disabled(modelo.cuarentena.isEmpty)
            }

            if modelo.cuarentena.isEmpty {
                Text("No hay archivos en cuarentena.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(modelo.cuarentena) { elemento in
                    FilaCuarentena(elemento: elemento)
                }
            }

            if let error = modelo.errorCuarentena {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Un archivo en cuarentena: nombre, amenaza, fecha y acciones.
private struct FilaCuarentena: View {
    @Environment(ModeloApp.self) private var modelo
    let elemento: ElementoCuarentena

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading) {
                Text(elemento.nombreOriginal).lineLimit(1).truncationMode(.middle)
                Text("\(elemento.amenaza) · \(elemento.fecha.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .help("Venía de: \(elemento.rutaOriginal)")
            Spacer()
            Menu {
                Button("Restaurar a su ubicación…", systemImage: "arrow.uturn.backward") {
                    restaurar()
                }
                Button("Eliminar definitivamente…", systemImage: "trash", role: .destructive) {
                    eliminar()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    // Confirmamos con una alerta clásica de macOS (NSAlert): funciona igual en
    // la ventana que en el panel de la barra de menú.

    private func restaurar() {
        let ok = confirmar(
            titulo: "¿Restaurar «\(elemento.nombreOriginal)»?",
            texto: "Este archivo contiene «\(elemento.amenaza)». Volverá a:\n\(elemento.rutaOriginal)\n\nRestáuralo solo si estás seguro de que es un falso positivo.",
            boton: "Restaurar")
        if ok, let destino = modelo.restaurar(elemento) {
            NSWorkspace.shared.activateFileViewerSelecting([destino])
        }
    }

    private func eliminar() {
        let ok = confirmar(
            titulo: "¿Eliminar «\(elemento.nombreOriginal)» definitivamente?",
            texto: "El archivo se borrará para siempre (no va a la Papelera). Esta acción no se puede deshacer.",
            boton: "Eliminar")
        if ok {
            modelo.eliminar(elemento)
        }
    }

    private func confirmar(titulo: String, texto: String, boton: String) -> Bool {
        let alerta = NSAlert()
        alerta.messageText = titulo
        alerta.informativeText = texto
        alerta.alertStyle = .warning
        alerta.addButton(withTitle: boton)
        alerta.addButton(withTitle: "Cancelar")
        NSApplication.shared.activate()
        return alerta.runModal() == .alertFirstButtonReturn
    }
}
