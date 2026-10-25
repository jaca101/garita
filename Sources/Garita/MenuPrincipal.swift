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

    /// Altura máxima de la parte central: la pantalla menos un margen para la
    /// barra de menú, el título de la ventana, la cabecera y el pie.
    private var altoMaximoCentro: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 800) - 200
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cabecera
                .padding()

            Divider()

            if enVentana {
                // En la ventana, sin scroll: las secciones se reparten en columnas
                // y la ventana se ensancha lo que haga falta.
                ColumnasFluidas(anchoColumna: 340, altoMaximo: altoMaximoCentro) {
                    seccionesEnTarjetas
                }
                .padding()
            } else {
                // En el desplegable, la parte central se desplaza si no cabe;
                // cabecera y pie quedan fijos.
                ScrollView {
                    secciones
                        .padding()
                }
                .frame(maxHeight: altoMaximoCentro)
            }

            Divider()

            pie
                .padding()
        }
        .frame(width: enVentana ? nil : 320)
        // Tamaño = el que pida el contenido, para que la ventana crezca con él
        // en vez de recortarlo (en el desplegable, el ancho es fijo).
        .fixedSize(horizontal: enVentana, vertical: true)
        // En la ventana: atender el selector que se pidió desde el desplegable.
        .onAppear { atenderSelectorPendiente(); atenderConfirmacionPendiente() }
        .onChange(of: modelo.selectorPendiente) { atenderSelectorPendiente() }
        .onChange(of: modelo.confirmacionPendiente?.id) { atenderConfirmacionPendiente() }
        // Todas las secciones piden sus confirmaciones por aquí.
        .environment(\.pedirConfirmacion, AccionConfirmar(enVentana: enVentana) { pedirConfirmacion($0) })
    }

    /// Confirmaciones: igual que los selectores (en la ventana, como hoja; desde
    /// el desplegable, abriendo antes la ventana, que la muestra).
    private func pedirConfirmacion(_ confirmacion: Confirmacion) {
        if enVentana {
            Selectores.mostrar(confirmacion)
        } else {
            modelo.confirmacionPendiente = confirmacion
            cerrarDesplegable()
            abrirVentana(id: "principal")
            NSApplication.shared.activate()
        }
    }

    private func atenderConfirmacionPendiente() {
        guard enVentana, let confirmacion = modelo.confirmacionPendiente else { return }
        modelo.confirmacionPendiente = nil
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            Selectores.mostrar(confirmacion)
        }
    }

    /// Selectores de archivos: en la ventana, como hoja pegada a ella. Desde el
    /// desplegable no (se cerraría al aparecer el selector): se abre la ventana
    /// y ella lo muestra.
    private func pedirSelector(_ tipo: Selector) {
        if enVentana {
            Selectores.mostrar(tipo, modelo: modelo)
        } else {
            modelo.selectorPendiente = tipo
            cerrarDesplegable()
            abrirVentana(id: "principal")
            NSApplication.shared.activate()
        }
    }

    private func atenderSelectorPendiente() {
        guard enVentana, let tipo = modelo.selectorPendiente else { return }
        modelo.selectorPendiente = nil
        // Un instante, para que la ventana esté ya delante y con su tamaño.
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            Selectores.mostrar(tipo, modelo: modelo)
        }
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
        }
    }

    private var secciones: some View {
        VStack(alignment: .leading, spacing: 12) {
            SeccionVigilante(pedirSelector: pedirSelector)

            Divider()

            SeccionEscaneo(admiteArrastrar: enVentana, pedirSelector: pedirSelector)

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

    /// Las mismas secciones, cada una en su tarjeta, para repartirlas en columnas.
    @ViewBuilder
    private var seccionesEnTarjetas: some View {
        SeccionVigilante(pedirSelector: pedirSelector).tarjeta()
        SeccionEscaneo(admiteArrastrar: true, pedirSelector: pedirSelector).tarjeta()
        SeccionCuarentena().tarjeta()
        SeccionProgramados(cerrarDesplegable: nil).tarjeta()
        SeccionFirmas().tarjeta()
        SeccionMotor().tarjeta()
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
            HStack {
                // El panel se cierra al hacer clic fuera, así que no sirve para
                // arrastrar desde el Finder; la ventana sí (y sale en ⌘Tab).
                Button("Abrir en una ventana", systemImage: "macwindow") {
                    cerrarDesplegable()     // el panel de la barra se va…
                    abrirVentana(id: "principal")   // …y queda solo la ventana
                    NSApplication.shared.activate()
                }
                .help("Abrir Garita en una ventana: se ve todo sin desplazarse, sale en ⌘Tab y admite arrastrar archivos")
                Spacer()
                Button("Salir de Garita") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
    }
}
