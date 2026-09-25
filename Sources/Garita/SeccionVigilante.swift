import AppKit
import ServiceManagement
import SwiftUI

/// El vigilante de descargas: interruptor, carpetas, modo y actividad reciente.
struct SeccionVigilante: View {
    @Environment(ModeloApp.self) private var modelo

    /// Muestra el selector de carpetas (ver MenuPrincipal.pedirSelector).
    var pedirSelector: (Selector) -> Void = { _ in }

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
                Text("No hay ninguna carpeta vigilada.")
                    .font(.callout).foregroundStyle(.orange)
            } else {
                ForEach(modelo.carpetasVigiladas, id: \.self) { carpeta in
                    FilaCarpeta(carpeta: carpeta)
                }
            }

            HStack {
                Button("Añadir carpeta…", systemImage: "plus") { pedirSelector(.añadirCarpetas) }
                    .controlSize(.small)
                Spacer()
                if modelo.carpetasVigiladas.map(\.path) != ModeloApp.carpetasPorDefecto
                    .filter({ FileManager.default.fileExists(atPath: $0.path) }).map(\.path) {
                    Button("Restablecer") { modelo.restablecerCarpetasVigiladas() }
                        .buttonStyle(.link)
                        .font(.caption)
                        .help("Volver a Descargas y aMule Downloads")
                }
            }

            Toggle("Aislar amenazas automáticamente", isOn: $modelo.aislarAutomaticamente)
                .font(.callout)
                .disabled(!modelo.vigilanteActivo)
                .help("Si está desactivado, Garita solo avisa y tú decides si aislar")

            Toggle("Abrir Garita al iniciar sesión", isOn: Binding(
                get: { modelo.abrirAlIniciar },
                set: { modelo.cambiarAbrirAlIniciar($0) }))
                .font(.callout)
                .help("Garita se abrirá sola al encender el Mac (Ajustes → General → Ítems de inicio)")
            if modelo.inicioRequiereAprobacion {
                HStack {
                    Text("macOS pide aprobarlo en Ítems de inicio.")
                        .font(.caption).foregroundStyle(.orange)
                    Button("Abrir Ajustes…") { SMAppService.openSystemSettingsLoginItems() }
                        .controlSize(.small)
                }
            }
            if let error = modelo.errorInicio {
                Text("No se pudo cambiar: \(error)").font(.caption).foregroundStyle(.red)
            }

            estado

            if !modelo.notificacionesPermitidas && modelo.vigilanteActivo {
                HStack(alignment: .top) {
                    Text("Notificaciones desactivadas: si encuentra algo, Garita abrirá su ventana.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Ajustes…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                    }
                    .controlSize(.small)
                }
            }

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
    @Environment(\.pedirConfirmacion) private var pedirConfirmacion
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
            if evento.pendienteDeResolver, case .amenaza(let amenaza) = evento.resultado {
                VStack(spacing: 4) {
                    Button("Aislar") { modelo.aislar(evento) }
                        .controlSize(.small)
                    Button("Es seguro") {
                        let modelo = modelo, evento = evento
                        pedirConfirmacion(.seguro(nombre: evento.archivo.lastPathComponent, amenaza: amenaza) {
                            modelo.marcarSeguro(evento)
                        })
                    }
                    .controlSize(.small)
                }
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

/// Una carpeta vigilada: nombre, aviso si no existe y botón para quitarla.
private struct FilaCarpeta: View {
    @Environment(ModeloApp.self) private var modelo
    let carpeta: URL

    var body: some View {
        let existe = FileManager.default.fileExists(atPath: carpeta.path)
        HStack {
            Label {
                Text(FileManager.default.displayName(atPath: carpeta.path))
                    .lineLimit(1).truncationMode(.middle)
                if !existe {
                    Text("no disponible").font(.caption).foregroundStyle(.orange)
                }
            } icon: {
                Image(systemName: existe ? "folder" : "folder.badge.questionmark")
            }
            .font(.callout)
            .foregroundStyle(modelo.vigilanteActivo && existe ? .primary : .secondary)
            .help(carpeta.path)

            Spacer()

            Button("Dejar de vigilar", systemImage: "minus.circle") {
                modelo.quitarCarpetaVigilada(carpeta)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Dejar de vigilar esta carpeta")
        }
    }
}
