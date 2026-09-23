import SwiftUI

/// Contenido principal de Garita. Se usa en dos sitios: el panel que se
/// despliega desde la barra de menú y la ventana "Garita".
struct MenuPrincipal: View {
    /// true en la ventana, false en el panel de la barra.
    var enVentana = false

    @Environment(ModeloApp.self) private var modelo
    @Environment(\.openWindow) private var abrirVentana
    @Environment(\.dismissWindow) private var cerrarVentana

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // El mismo escudo que en la barra (con "!" si hay algo que resolver).
                Label {
                    Text("Garita")
                } icon: {
                    Image(nsImage: DibujoIcono.barra(aviso: modelo.necesitaAtencion))
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                .font(.headline)
                Spacer()
                if !enVentana {
                    // El panel se cierra al hacer clic fuera, así que no sirve para
                    // arrastrar desde el Finder; la ventana sí (y sale en ⌘Tab).
                    Button("Abrir ventana", systemImage: "macwindow") {
                        abrirVentana(id: "principal")
                        NSApplication.shared.activate()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Abrir en una ventana (sale en ⌘Tab y admite arrastrar archivos)")
                }
            }

            Divider()

            SeccionVigilante()

            Divider()

            SeccionEscaneo(admiteArrastrar: enVentana)

            Divider()

            SeccionCuarentena()

            Divider()

            SeccionFirmas()

            Divider()

            SeccionMotor()

            Divider()

            if enVentana {
                // En la ventana solo la cerramos: Garita sigue en la barra de menú.
                Button("Cerrar ventana") {
                    cerrarVentana(id: "principal")
                }
                .keyboardShortcut("w")
            } else {
                Button("Salir de Garita") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding()
        .frame(width: 320)
        // Altura = la que pida el contenido, para que la ventana crezca con él
        // (p. ej. al mostrar un resultado) en vez de recortarlo.
        .fixedSize(horizontal: false, vertical: true)
    }
}
