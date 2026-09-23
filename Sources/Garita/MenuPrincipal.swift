import SwiftUI

/// Panel que aparece al pulsar el icono de la barra de menú.
/// Iremos añadiendo secciones: vigilante, escaneo a demanda, firmas y cuarentena.
struct MenuPrincipal: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Garita", systemImage: "shield.lefthalf.filled")
                .font(.headline)

            Divider()

            SeccionMotor()

            Divider()

            SeccionFirmas()

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
