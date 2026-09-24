import SwiftUI

/// Contenido principal de Garita. Se usa en dos sitios: el panel que se
/// despliega desde la barra de menú y la ventana "Garita".
struct MenuPrincipal: View {
    /// true en la ventana, false en el panel de la barra.
    var enVentana = false

    @Environment(ModeloApp.self) private var modelo
    @Environment(\.openWindow) private var abrirVentana
    @Environment(\.dismissWindow) private var cerrarVentana
    /// Dentro del panel de la barra, cierra el panel.
    @Environment(\.dismiss) private var cerrarDesplegable

    /// Altura máxima de la parte central (con scroll): la pantalla menos un margen
    /// para la barra de menú, la cabecera y el pie.
    private var altoMaximoCentro: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 800) - 200
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cabecera
                .padding()

            Divider()

            // La parte central se desplaza si no cabe; cabecera y pie quedan fijos.
            ScrollView {
                secciones
                    .padding()
            }
            .frame(maxHeight: altoMaximoCentro)

            Divider()

            pie
                .padding()
        }
        .frame(width: 320)
        // Altura = la que pida el contenido (con el tope de arriba), para que la
        // ventana crezca con él en vez de recortarlo.
        .fixedSize(horizontal: false, vertical: true)
    }

    private var cabecera: some View {
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
            Button("Historial", systemImage: "clock.arrow.circlepath") {
                if !enVentana { cerrarDesplegable() }
                abrirVentana(id: "historial")
                NSApplication.shared.activate()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Historial de avisos")
            if !enVentana {
                // El panel se cierra al hacer clic fuera, así que no sirve para
                // arrastrar desde el Finder; la ventana sí (y sale en ⌘Tab).
                Button("Abrir ventana", systemImage: "macwindow") {
                    cerrarDesplegable()     // el panel de la barra se va…
                    abrirVentana(id: "principal")   // …y queda solo la ventana
                    NSApplication.shared.activate()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Abrir en una ventana (sale en ⌘Tab y admite arrastrar archivos)")
            }
        }
    }

    private var secciones: some View {
        VStack(alignment: .leading, spacing: 12) {
            SeccionVigilante()

            Divider()

            SeccionEscaneo(admiteArrastrar: enVentana)

            Divider()

            SeccionCuarentena()

            Divider()

            SeccionProgramados(cerrarDesplegable: enVentana ? nil : { cerrarDesplegable() })

            Divider()

            SeccionFirmas()

            Divider()

            SeccionMotor()
        }
    }

    @ViewBuilder
    private var pie: some View {
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
}
