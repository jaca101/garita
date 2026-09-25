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
    @State private var verProblemas = false

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
                    HStack(alignment: .top, spacing: 4) {
                        ProgressView().controlSize(.mini)
                        if let progreso = modelo.progresoProgramado {
                            VistaProgreso(progreso: progreso)
                        }
                    }
                } else if let resultado = tarea.ultimoResultado {
                    Text("Último: \(tarea.ultimaEjecucion.formatted(.relative(presentation: .named))) · \(resultado)")
                        .font(.caption)
                        .foregroundStyle(resultado.contains("amenaza") ? .red : .secondary)
                        .lineLimit(2)
                    if let problemas = tarea.ultimosProblemas, !problemas.isEmpty {
                        Button("Ver los \(problemas.count) sin analizar…") { verProblemas = true }
                            .buttonStyle(.link)
                            .font(.caption)
                            .popover(isPresented: $verProblemas, arrowEdge: .trailing) {
                                ListaProblemas(problemas: problemas)
                            }
                    }
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

/// Lista de archivos que no se pudieron analizar (del todo), con su motivo.
private struct ListaProblemas: View {
    let problemas: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sin analizar del todo en el último escaneo").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(problemas, id: \.self) { linea in
                        Text(linea)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 360)
            Text("Suelen ser archivos de más de 2 GB, comprimidos con contraseña o que superan los límites de ClamAV.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 520)
    }
}
