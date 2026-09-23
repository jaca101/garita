import SwiftUI

/// Contenido principal de Garita. Se usa en dos sitios: el panel que se
/// despliega desde la barra de menú y la ventana "Garita".
/// Iremos añadiendo secciones: vigilante y cuarentena.
struct MenuPrincipal: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Garita", systemImage: "shield.lefthalf.filled")
                .font(.headline)

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
        // Altura = la que pida el contenido, para que la ventana crezca con él
        // (p. ej. al mostrar un resultado) en vez de recortarlo.
        .fixedSize(horizontal: false, vertical: true)
    }
}
