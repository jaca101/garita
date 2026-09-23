import AppKit
import SwiftUI

/// Escaneo bajo demanda: zona para soltar archivos (o hacer clic y elegirlos)
/// y el resultado del último escaneo.
struct SeccionEscaneo: View {
    @Environment(ModeloApp.self) private var modelo
    /// true mientras el usuario arrastra algo por encima de la zona.
    @State private var arrastrandoEncima = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Escanear").font(.subheadline.bold())

            if modelo.escaneando {
                enCurso
            } else {
                zonaParaSoltar
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

    /// Rectángulo punteado: se puede soltar encima o hacer clic para elegir.
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
    let resultado: ResultadoEscaneo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Primero "cancelado": al detenerlo, clamscan también sale con un código de error.
            if resultado.cancelado {
                Label("Escaneo cancelado", systemImage: "stop.circle").foregroundStyle(.secondary)
            } else if let fallo = resultado.fallo {
                Label(fallo, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
            } else if resultado.detecciones.isEmpty {
                Label("Limpio · \(resumen)", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)
            } else {
                Label("\(resultado.detecciones.count) amenaza(s) encontrada(s) · \(resumen)",
                      systemImage: "exclamationmark.shield.fill")
                    .foregroundStyle(.red)
                    .bold()
                ForEach(resultado.detecciones) { deteccion in
                    FilaDeteccion(deteccion: deteccion)
                }
            }

            if !resultado.problemas.isEmpty {
                DisclosureGroup("\(resultado.problemas.count) archivo(s) no se pudieron leer") {
                    ForEach(resultado.problemas, id: \.self) { problema in
                        Text(problema).font(.caption).textSelection(.enabled)
                    }
                    Text("Si son de carpetas protegidas, Garita necesita Acceso total al disco.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
    }

    /// "12 archivos en 7 s"
    private var resumen: String {
        let archivos = resultado.archivosAnalizados.map { "\($0) archivo(s)" } ?? "?"
        return "\(archivos) en \(Int(resultado.duracion.rounded())) s"
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
