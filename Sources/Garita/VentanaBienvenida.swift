import AppKit
import SwiftUI

/// Se abre la primera vez (si Garita no tiene Acceso total al disco) y guía
/// para concederlo. También se puede abrir desde la sección del motor.
struct VentanaBienvenida: View {
    @Environment(ModeloApp.self) private var modelo
    @Environment(\.dismissWindow) private var cerrarVentana

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading) {
                    Text("Bienvenido a Garita").font(.title2.bold())
                    Text("Un paso más para que pueda protegerlo todo")
                        .foregroundStyle(.secondary)
                }
            }

            Text("Para escanear cualquier carpeta de tu Mac, incluidas las protegidas (Mail, Mensajes, Safari, datos de otras apps…), Garita necesita **Acceso total al disco**. macOS no deja que una app lo active sola: tienes que hacerlo tú, una sola vez.")
                .fixedSize(horizontal: false, vertical: true)

            estado

            if !modelo.accesoTotal {
                Paso(numero: 1, texto: "Abre los ajustes de Acceso total al disco.") {
                    Button("Abrir Ajustes") { AccesoDisco.abrirAjustes() }
                }
                Paso(numero: 2, texto: "Activa **Garita** en la lista. Si no aparece, pulsa «+» y elígela, o arrástrala desde el Finder.") {
                    Button("Mostrar Garita en el Finder") { AccesoDisco.mostrarGaritaEnFinder() }
                }
                Paso(numero: 3, texto: "Vuelve aquí. Si macOS te lo pide, o esto no cambia a ✓, reinicia Garita.") {
                    Button("Reiniciar Garita") { AccesoDisco.reiniciarGarita() }
                }
            }

            HStack {
                Spacer()
                if modelo.accesoTotal {
                    Button("Empezar") { cerrar() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Ahora no") { cerrar() }
                        .help("Puedes hacerlo más tarde desde la sección «Motor ClamAV»")
                }
            }
        }
        .padding(20)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { modelo.comprobarAccesoTotal() }
    }

    private var estado: some View {
        Label {
            Text(modelo.accesoTotal ? "Garita tiene Acceso total al disco" : "Aún no tiene Acceso total al disco")
                .bold()
        } icon: {
            Image(systemName: modelo.accesoTotal ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(modelo.accesoTotal ? .green : .orange)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func cerrar() {
        modelo.bienvenidaVista = true
        cerrarVentana(id: "bienvenida")
    }
}

/// Un paso numerado con su botón.
private struct Paso<Boton: View>: View {
    let numero: Int
    let texto: LocalizedStringKey
    @ViewBuilder let boton: Boton

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(numero)")
                .font(.headline)
                .frame(width: 24, height: 24)
                .background(Color.accentColor.opacity(0.2), in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(texto).fixedSize(horizontal: false, vertical: true)
                boton
            }
        }
    }
}
