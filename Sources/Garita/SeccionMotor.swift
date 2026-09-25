import AppKit
import SwiftUI

/// Muestra si ClamAV está listo y, si falta algo, qué hacer para arreglarlo.
struct SeccionMotor: View {
    @Environment(ModeloApp.self) private var modelo
    @Environment(\.openWindow) private var abrirVentana

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Motor ClamAV").font(.subheadline.bold())
                Spacer()
                Button("Comprobar", systemImage: "arrow.clockwise") {
                    modelo.comprobarMotor()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Volver a comprobar")
            }

            if let motor = modelo.motor {
                detalle(motor)
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func detalle(_ motor: EstadoMotor) -> some View {
        Fila(ok: motor.clamscan != nil, texto: "clamscan", ruta: motor.clamscan?.path)
        Fila(ok: motor.freshclam != nil, texto: "freshclam", ruta: motor.freshclam?.path)

        if let version = motor.version {
            Text(motor.integrado ? "\(version), integrado en Garita" : "\(version), de Homebrew")
                .font(.caption).foregroundStyle(.secondary)
        }

        // Solo tiene sentido revisar configuración y firmas si freshclam existe.
        // (Con el ClamAV integrado, Garita crea y mantiene su freshclam.conf.)
        if motor.freshclam != nil {
            if !motor.integrado {
                Fila(ok: motor.configExiste, texto: "freshclam.conf", ruta: motor.configFreshclam?.path)
            }
            Fila(ok: motor.hayFirmas, texto: "Base de firmas", ruta: motor.carpetaFirmas?.path)
        }

        // Escaneo rápido (opcional): solo con el ClamAV integrado, que trae clamd.
        if ServicioClamd.disponible(motor) {
            EscaneoRapido()
        }

        // Acceso total al disco: opcional, pero sin él no se leen carpetas protegidas.
        HStack {
            Fila(ok: modelo.accesoTotal, texto: "Acceso total al disco",
                 ruta: "Ajustes del Sistema → Privacidad y seguridad → Acceso total al disco")
            if !modelo.accesoTotal {
                Spacer()
                Button("Configurar…") {
                    abrirVentana(id: "bienvenida")
                    NSApplication.shared.activate()
                }
                .controlSize(.small)
            }
        }

        // Instrucciones para lo primero que falte (de una en una, en orden).
        if (motor.clamscan == nil || motor.freshclam == nil) && motor.homebrew == nil {
            // Paso 1 de 2: sin Homebrew no se puede instalar ClamAV.
            Instruccion(
                texto: "Paso 1 de 2: ClamAV se instala con Homebrew, que no está en este Mac. Pega esto en la app Terminal y sigue sus instrucciones:",
                comando: #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#)
            HStack {
                Link("Qué es Homebrew (brew.sh)", destination: URL(string: "https://brew.sh/es/")!)
                    .font(.caption)
                Spacer()
                Text("Al terminar, pulsa ↻").font(.caption).foregroundStyle(.secondary)
            }
        } else if motor.clamscan == nil || motor.freshclam == nil, let brew = motor.homebrew {
            // Usamos la ruta completa de brew: en una Terminal recién instalada
            // puede que "brew" aún no esté en el PATH.
            Instruccion(
                texto: "ClamAV no está instalado. Pega esto en la app Terminal y, al terminar, pulsa ↻:",
                comando: "\(brew.path) install clamav")
        } else if modelo.actualizandoFirmas && !motor.hayFirmas {
            Label("Descargando las firmas de virus por primera vez…", systemImage: "arrow.down.circle")
                .font(.callout)
                .foregroundStyle(.orange)
        } else if (!motor.integrado && !motor.configExiste) || !motor.hayFirmas {
            // Lo resuelve el botón "Actualizar firmas" (ver SeccionFirmas).
            Text("Pulsa «Actualizar firmas» para terminar de prepararlo.")
                .font(.callout)
                .foregroundStyle(.orange)
        } else {
            Label("Listo para escanear", systemImage: "checkmark.shield.fill")
                .foregroundStyle(.green)
        }
    }
}

/// Una línea de comprobación: ✓/✗ + nombre, con la ruta como ayuda al pasar el ratón.
private struct Fila: View {
    let ok: Bool
    let texto: String
    let ruta: String?

    var body: some View {
        Label {
            Text(texto)
        } icon: {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
        }
        .help(ruta ?? "No encontrado")
    }
}

/// Explicación + comando para pegar en la Terminal, con botón de copiar.
private struct Instruccion: View {
    let texto: String
    let comando: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(texto).font(.callout)
            HStack(alignment: .top) {
                Text(comando)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Copiar", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(comando, forType: .string)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Copiar al portapapeles")
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

/// Interruptor del escaneo rápido (clamd) y su estado.
private struct EscaneoRapido: View {
    @Environment(ModeloApp.self) private var modelo

    var body: some View {
        @Bindable var modelo = modelo
        VStack(alignment: .leading, spacing: 2) {
            Toggle("Escaneo rápido (clamd)", isOn: $modelo.escaneoRapido)
                .help("Mantiene las firmas cargadas en memoria (~1,6 GB) para que los escaneos del vigilante y los manuales empiecen al instante. Los programados siguen con clamscan.")
            Group {
                switch modelo.estadoClamd {
                case .desactivado:
                    Text("Desactivado: cada escaneo carga las firmas (~7 s).")
                case .arrancando:
                    Text("Cargando las firmas en memoria…").foregroundStyle(.orange)
                case .activo(let mb):
                    Text("Activo" + (mb.map { String(format: " · %.1f GB de memoria", Double($0) / 1024) } ?? ""))
                        .foregroundStyle(.green)
                case .error(let motivo):
                    Text(motivo).foregroundStyle(.red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
