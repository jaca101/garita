import AppKit
import SwiftUI

/// Escaneo bajo demanda: botón para elegir archivos o carpetas y el resultado
/// del último escaneo. (También se puede escanear desde el Finder con clic
/// derecho → "Escanear con Garita"; ver ServicioFinder.swift.)
struct SeccionEscaneo: View {
    @Environment(ModeloApp.self) private var modelo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Escanear").font(.subheadline.bold())

            if modelo.escaneando {
                enCurso
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
                Text("Cargar las firmas tarda unos segundos.")
                    .font(.caption).foregroundStyle(.secondary)
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
                ForEach(resultado.detecciones) { deteccion in
                    FilaDeteccion(deteccion: deteccion)
                }
            }

            if !resultado.problemas.isEmpty {
                // Lista visible (sin desplegable: la ventana no se redimensiona al
                // desplegar). Como mucho `maxProblemas` líneas, para no hacerla enorme.
                let n = resultado.problemas.count
                VStack(alignment: .leading, spacing: 4) {
                    Label(n == 1 ? "1 archivo no se pudo leer" : "\(n) archivos no se pudieron leer",
                          systemImage: "exclamationmark.triangle.fill")
                    ForEach(resultado.problemas.prefix(maxProblemas), id: \.self) { problema in
                        Text(problema).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                    }
                    if n > maxProblemas {
                        Text("y \(n - maxProblemas) más")
                    }
                    Text("Si son de carpetas protegidas, Garita necesita Acceso total al disco.")
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

/// Una amenaza: nombre del archivo, nombre del virus y botón para verlo en el Finder.
private struct FilaDeteccion: View {
    let deteccion: Deteccion

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading) {
                Text(deteccion.archivo.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(deteccion.amenaza).font(.caption).foregroundStyle(.red)
            }
            .help(deteccion.archivo.path)
            Spacer()
            Button("Mostrar en el Finder", systemImage: "magnifyingglass") {
                NSWorkspace.shared.activateFileViewerSelecting([deteccion.archivo])
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Mostrar en el Finder")
        }
        .padding(6)
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }
}
