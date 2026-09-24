import SwiftUI

/// Lista de escaneos programados: activar/desactivar, ejecutar ahora, editar, eliminar.
struct SeccionProgramados: View {
    @Environment(ModeloApp.self) private var modelo
    @Environment(\.openWindow) private var abrirVentana
    /// Dentro del panel de la barra, cierra el panel antes de abrir el editor.
    var cerrarDesplegable: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Escaneos programados").font(.subheadline.bold())
                Spacer()
                Button("Añadir", systemImage: "plus") { abrirEditor(nil) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Programar un escaneo")
            }

            if modelo.programados.isEmpty {
                Text("Ninguno. Pulsa + para programar uno.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            ForEach(modelo.programados) { tarea in
                FilaProgramada(tarea: tarea, editar: { abrirEditor(tarea) })
            }

            // Si hay alguna pendiente pero algo lo impide (batería, margen…), lo decimos.
            if modelo.tareaEnCurso == nil, modelo.programados.contains(where: \.pendiente),
               let motivo = modelo.motivoEspera {
                Label(motivo, systemImage: "clock")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func abrirEditor(_ tarea: TareaProgramada?) {
        modelo.editar(tarea)
        cerrarDesplegable?()
        abrirVentana(id: "programar")
        NSApplication.shared.activate()
    }
}

/// Una tarea: interruptor, carpeta, cuándo, último resultado y acciones.
private struct FilaProgramada: View {
    @Environment(ModeloApp.self) private var modelo
    let tarea: TareaProgramada
    let editar: () -> Void

    private var enCurso: Bool { modelo.tareaEnCurso == tarea.id }

    var body: some View {
        HStack(alignment: .top) {
            Toggle("Activa", isOn: Binding(
                get: { tarea.activa },
                set: { modelo.cambiarActiva(tarea, $0) }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(FileManager.default.displayName(atPath: tarea.carpeta))
                    .lineLimit(1).truncationMode(.middle)
                    .help(tarea.carpeta)
                Text(tarea.descripcion)
                    .font(.caption).foregroundStyle(.secondary)
                if enCurso {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("Escaneando…").font(.caption)
                    }
                } else if let resultado = tarea.ultimoResultado {
                    Text("Último: \(tarea.ultimaEjecucion.formatted(.relative(presentation: .named))) · \(resultado)")
                        .font(.caption)
                        .foregroundStyle(resultado.contains("amenaza") ? .red : .secondary)
                        .lineLimit(2)
                }
            }
            .opacity(tarea.activa ? 1 : 0.5)

            Spacer()

            if enCurso {
                Button("Detener") { modelo.detenerProgramado() }
                    .controlSize(.small)
            } else {
                Menu {
                    Button("Ejecutar ahora", systemImage: "play") { modelo.ejecutar(tarea) }
                        .disabled(modelo.tareaEnCurso != nil || modelo.motor?.listo != true)
                    Button("Editar…", systemImage: "pencil") { editar() }
                    Button("Eliminar", systemImage: "trash", role: .destructive) { modelo.eliminar(tarea) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }
}
