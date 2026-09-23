import SwiftUI

/// Contenido principal de Garita. Se usa en dos sitios: el panel que se
/// despliega desde la barra de menú y la ventana "Garita".
/// Iremos añadiendo secciones: vigilante y cuarentena.
struct MenuPrincipal: View {
    /// true en la ventana, false en el panel de la barra.
    var enVentana = false

    @Environment(\.openWindow) private var abrirVentana

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Garita", systemImage: "shield.lefthalf.filled")
                    .font(.headline)
                Spacer()
                if !enVentana {
                    // El panel se cierra al hacer clic fuera, así que no sirve para
                    // arrastrar desde el Finder; la ventana sí.
                    Button("Abrir en ventana", systemImage: "macwindow") {
                        abrirVentana(id: "principal")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Abrir en una ventana (para arrastrar archivos desde el Finder)")
                }
            }

            Divider()

            SeccionEscaneo()

            Divider()

            SeccionFirmas()

            Divider()

            SeccionMotor()

            Divider()

            Button("Salir de Garita") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 320)
    }
}
