import AppKit
import SwiftUI

/// El vigilante de descargas: interruptor, carpetas, modo y actividad reciente.
struct SeccionVigilante: View {
    @Environment(ModeloApp.self) private var modelo

    /// Cuántas entradas de actividad mostramos.
    private let maxVisibles = 5

    var body: some View {
        @Bindable var modelo = modelo

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Vigilante de descargas").font(.subheadline.bold())
                Spacer()
                Toggle("Activo", isOn: $modelo.vigilanteActivo)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }

            if modelo.carpetasVigiladas.isEmpty {
                Text("No se encontró ninguna carpeta que vigilar.")
                    .font(.callout).foregroundStyle(.orange)
            } else {
                ForEach(modelo.carpetasVigiladas, id: \.self) { carpeta in
                    Label(FileManager.default.displayName(atPath: carpeta.path), systemImage: "folder")
                        .font(.callout)
                        .foregroundStyle(modelo.vigilanteActivo ? .primary : .secondary)
                        .help(carpeta.path)
                }
            }

            Toggle("Aislar amenazas automáticamente", isOn: $modelo.aislarAutomaticamente)
                .font(.callout)
                .disabled(!modelo.vigilanteActivo)
                .help("Si está desactivado, Garita solo avisa y tú decides si aislar")

            estado

            ForEach(modelo.actividad.prefix(maxVisibles)) { evento in
                FilaActividad(evento: evento)
            }
        }
    }

    @ViewBuilder
    private var estado: some View {
        if !modelo.vigilanteActivo {
            Text("En pausa: las descargas nuevas no se escanean.")
                .font(.caption).foregroundStyle(.orange)
        } else if !modelo.vigilanteEscaneando.isEmpty {
            HStack {
                ProgressView().controlSize(.small)
                let n = modelo.vigilanteEscaneando.count
                Text(n == 1 ? "Analizando \(modelo.vigilanteEscaneando[0].lastPathComponent)…"
                            : "Analizando \(n) archivos nuevos…")
                    .font(.caption)
                    .lineLimit(1).truncationMode(.middle)
            }
        } else if modelo.actividad.isEmpty {
            Text("Esperando descargas nuevas…")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Una línea del registro: icono, archivo, qué pasó y cuándo.
private struct FilaActividad: View {
    @Environment(ModeloApp.self) private var modelo
    let evento: EventoVigilante

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icono.nombre)
                .foregroundStyle(icono.color)
            VStack(alignment: .leading) {
                Text(evento.archivo.lastPathComponent)
                    .lineLimit(1).truncationMode(.middle)
                Text("\(detalle) · \(evento.fecha.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(icono.color == .green ? .secondary : icono.color)
                    .lineLimit(2)
            }
            .help(evento.archivo.path)
            Spacer()
            if evento.pendienteDeResolver {
                Button("Aislar") { modelo.aislar(evento) }
                    .controlSize(.small)
            }
        }
        .font(.callout)
    }

    private var icono: (nombre: String, color: Color) {
        switch evento.resultado {
        case .limpio:      ("checkmark.circle.fill", .green)
        case .aislado:     ("lock.shield.fill", .red)
        case .amenaza:     ("exclamationmark.shield.fill", .red)
        case .noAnalizado: ("exclamationmark.triangle.fill", .orange)
        case .error:       ("xmark.octagon.fill", .red)
        }
    }

    private var detalle: String {
        switch evento.resultado {
        case .limpio:                  "limpio"
        case .aislado(let amenaza):    "\(amenaza) · aislado"
        case .amenaza(let amenaza):    "\(amenaza) · sin aislar"
        case .noAnalizado(let motivo): motivo
        case .error(let fallo):        fallo
        }
    }
}
