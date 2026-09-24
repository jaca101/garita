import AppKit
import SwiftUI

/// Escaneo bajo demanda: botón para elegir archivos o carpetas y el resultado
/// del último escaneo. En la ventana, además, se pueden soltar archivos encima.
/// (También se puede escanear desde el Finder con clic derecho →
/// "Escanear con Garita"; ver ServicioFinder.swift.)
struct SeccionEscaneo: View {
    /// Solo en la ventana: en el panel de la barra no se puede arrastrar,
    /// porque se cierra en cuanto se hace clic en el Finder.
    var admiteArrastrar = false

    @Environment(ModeloApp.self) private var modelo
    /// true mientras el usuario arrastra algo por encima de la zona.
    @State private var arrastrandoEncima = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Escanear").font(.subheadline.bold())

            if modelo.escaneando {
                enCurso
            } else if admiteArrastrar {
                zonaParaSoltar
            } else {
                botonElegir
            }

            if let resultado = modelo.resultadoEscaneo, !modelo.escaneando {
                VistaResultado(resultado: resultado)
            }
        }
    }

    /// Mientras clamscan trabaja.
    private var enCurso: some View {
        HStack {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading) {
                Text("Escaneando \(descripcion(modelo.rutasEscaneo))…")
                    .lineLimit(1).truncationMode(.middle)
                if let progreso = modelo.progresoEscaneo {
                    VistaProgreso(progreso: progreso)
                }
            }
            Spacer()
            Button("Cancelar") { modelo.cancelarEscaneo() }
        }
    }

    /// Botón que abre el selector de archivos.
    private var botonElegir: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                elegirArchivos()
            } label: {
                Label("Escanear archivo o carpeta…", systemImage: "doc.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(modelo.motor?.listo != true)

            Text("También desde el Finder: clic derecho → Escanear con Garita")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Rectángulo punteado (solo en la ventana): se puede soltar encima o
    /// hacer clic para elegir.
    private var zonaParaSoltar: some View {
        let activo = modelo.motor?.listo == true

        return Button {
            elegirArchivos()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "arrow.down.doc").font(.title2)
                Text("Suelta aquí archivos o carpetas")
                Text("o haz clic para elegirlos").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                    .foregroundStyle(arrastrandoEncima ? Color.accentColor : .secondary)
            )
        }
        .buttonStyle(.plain)
        .disabled(!activo)
        .opacity(activo ? 1 : 0.4)
        .dropDestination(for: URL.self) { urls, _ in
            modelo.escanear(urls)
            return true
        } isTargeted: { encima in
            arrastrandoEncima = encima
        }
    }

    /// Abre el selector de archivos de macOS.
    private func elegirArchivos() {
        let selector = NSOpenPanel()
        selector.canChooseFiles = true
        selector.canChooseDirectories = true
        selector.allowsMultipleSelection = true
        selector.prompt = "Escanear"
        NSApplication.shared.activate()
        if selector.runModal() == .OK {
            modelo.escanear(selector.urls)
        }
    }

    /// "informe.pdf", "Descargas" o "3 elementos".
    private func descripcion(_ rutas: [URL]) -> String {
        rutas.count == 1 ? rutas[0].lastPathComponent : "\(rutas.count) elementos"
    }
}

/// Resumen del último escaneo: limpio, amenazas encontradas o problemas.
private struct VistaResultado: View {
    @Environment(ModeloApp.self) private var modelo
    let resultado: ResultadoEscaneo
    /// Cuántos archivos ilegibles listar como mucho.
    private let maxProblemas = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Primero "cancelado": al detenerlo, clamscan también sale con un código de error.
            if resultado.cancelado {
                Label("Escaneo cancelado", systemImage: "stop.circle").foregroundStyle(.secondary)
            } else if let fallo = resultado.fallo {
                Label(fallo, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
            } else if resultado.detecciones.isEmpty {
                Label("Limpio", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                    .bold()
                Text(resumen).font(.caption).foregroundStyle(.secondary)
            } else {
                let n = resultado.detecciones.count
                Label(n == 1 ? "1 amenaza encontrada" : "\(n) amenazas encontradas",
                      systemImage: "exclamationmark.shield.fill")
                    .foregroundStyle(.red)
                    .bold()
                Text(resumen).font(.caption).foregroundStyle(.secondary)
                if n > 1 && resultado.detecciones.contains(where: { !$0.aislada }) {
                    Button("Poner todas en cuarentena", systemImage: "lock.shield") {
                        modelo.aislarTodas()
                    }
                }
                ForEach(resultado.detecciones) { deteccion in
                    FilaDeteccion(deteccion: deteccion)
                }
            }

            if !resultado.problemas.isEmpty {
                // Lista visible (sin desplegable: la ventana no se redimensiona al
                // desplegar). Como mucho `maxProblemas` líneas, para no hacerla enorme.
                let n = resultado.problemas.count
                VStack(alignment: .leading, spacing: 4) {
                    Label(n == 1 ? "1 archivo sin analizar del todo" : "\(n) archivos sin analizar del todo",
                          systemImage: "exclamationmark.triangle.fill")
                    ForEach(resultado.problemas.prefix(maxProblemas), id: \.self) { problema in
                        Text(problema.descripcion).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                    }
                    if n > maxProblemas {
                        Text("y \(n - maxProblemas) más")
                    }
                    Text("«Access denied» en carpetas protegidas: Garita necesita Acceso total al disco.")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
    }

    /// "12 archivos analizados en 7 s"
    private var resumen: String {
        let segundos = "en \(Int(resultado.duracion.rounded())) s"
        switch resultado.archivosAnalizados {
        case 1?: return "1 archivo analizado \(segundos)"
        case let n?: return "\(n) archivos analizados \(segundos)"
        case nil: return "Escaneo terminado \(segundos)"
        }
    }
}

/// Una amenaza: nombre del archivo, nombre del virus, botón para verlo en el
/// Finder y botón para ponerlo en cuarentena.
private struct FilaDeteccion: View {
    @Environment(ModeloApp.self) private var modelo
    let deteccion: Deteccion

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading) {
                Text(deteccion.archivo.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(deteccion.amenaza).font(.caption).foregroundStyle(.red)
            }
            .help(deteccion.archivo.path)
            Spacer()
            if deteccion.aislada {
                Label("En cuarentena", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Mostrar en el Finder", systemImage: "magnifyingglass") {
                    NSWorkspace.shared.activateFileViewerSelecting([deteccion.archivo])
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Mostrar en el Finder")

                Button("Aislar") { modelo.aislar(deteccion) }
                    .controlSize(.small)
                    .help("Mover a la cuarentena")
            }
        }
        .padding(6)
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// "127 archivos analizados · 3:05" y el último archivo terminado.
/// El reloj se actualiza cada segundo aunque no lleguen archivos nuevos
/// (p. ej. mientras clamscan revisa por dentro un .dmg grande).
struct VistaProgreso: View {
    let progreso: ProgresoEscaneo

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { contexto in
            VStack(alignment: .leading, spacing: 1) {
                Text("\(progreso.archivos == 1 ? "1 archivo analizado" : "\(progreso.archivos) archivos analizados") · \(tiempo(hasta: contexto.date))")
                    .monospacedDigit()
                if let ultimo = progreso.ultimo {
                    Text("Último: \(ultimo)")
                        .lineLimit(1).truncationMode(.middle)
                } else {
                    Text("Cargando las firmas…")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// "0:42" o "1:03:05"
    private func tiempo(hasta ahora: Date) -> String {
        let s = max(0, Int(ahora.timeIntervalSince(progreso.inicio)))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}
