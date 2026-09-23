import SwiftUI

/// Punto de entrada de la app.
///
/// Garita vive solo en la barra de menú (sin Dock ni ⌘Tab, gracias a LSUIElement
/// en Info.plist). Al arrancar, si hay algo que resolver (falta parte del motor o
/// las firmas son antiguas), abre además una ventana con el panel para avisar.
/// También la abre al escanear desde el Finder (clic derecho → "Escanear con Garita").
@main
struct GaritaApp: App {
    /// La parte de AppKit: guarda el estado de la app y registra el servicio del Finder.
    @NSApplicationDelegateAdaptor private var delegado: DelegadoApp

    /// Estado único de la app, compartido con todas las vistas.
    private var modelo: ModeloApp { delegado.modelo }

    var body: some Scene {
        // El icono de la barra de menú, con el panel desplegable.
        MenuBarExtra {
            MenuPrincipal()
                .environment(modelo)
        } label: {
            IconoBarra()
                .environment(modelo)
        }
        .menuBarExtraStyle(.window)

        // Ventana con el mismo panel, más la zona para arrastrar archivos.
        // No se abre sola al arrancar: la abre IconoBarra cuando hay algo que
        // resolver o al escanear desde el Finder, o el usuario desde el panel.
        //
        // Mientras está abierta, Garita pasa a ser una app "normal" (Dock y ⌘Tab),
        // para poder volver a ella con ⌘Tab y arrastrar desde el Finder.
        // Al cerrarla, vuelve a vivir solo en la barra de menú.
        Window("Garita", id: "principal") {
            MenuPrincipal(enVentana: true)
                .environment(modelo)
                .onAppear { modelo.ventanaAbierta() }
                .onDisappear { modelo.ventanaCerrada() }
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .commands {
            // El menú de la app solo aparece con la ventana abierta. Ahí, ⌘Q cierra
            // la ventana en vez de la app, para no dejar de vigilar sin querer.
            // (Cerrar sesión o apagar el Mac siguen cerrando Garita con normalidad:
            // esto solo cambia la opción del menú.)
            CommandGroup(replacing: .appTermination) {
                Button("Cerrar ventana (Garita sigue en la barra)") {
                    (NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow)?.performClose(nil)
                }
                .keyboardShortcut("q")

                Button("Salir de Garita del todo") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: [.command, .option])
            }
        }

        // Bienvenida: la primera vez, si falta el Acceso total al disco.
        Window("Bienvenido a Garita", id: "bienvenida") {
            VentanaBienvenida()
                .environment(modelo)
                .onAppear { modelo.ventanaAbierta() }
                .onDisappear { modelo.ventanaCerrada() }
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)

        // Historial de avisos (botón 🕘 en la cabecera).
        Window("Historial de Garita", id: "historial") {
            VentanaHistorial()
                .environment(modelo)
                .onAppear { modelo.ventanaAbierta() }
                .onDisappear { modelo.ventanaCerrada() }
        }
        .defaultSize(width: 440, height: 520)
        .defaultLaunchBehavior(.suppressed)
    }
}

/// El icono de la barra: escudo con "G" si todo va bien, con "!" si no.
///
/// Además, es la única vista que existe desde el arranque (el panel no se crea
/// hasta que se pulsa el icono), así que desde aquí se abre la ventana cuando toca.
private struct IconoBarra: View {
    @Environment(ModeloApp.self) private var modelo
    @Environment(\.openWindow) private var abrirVentana

    var body: some View {
        // Escudo con "G", o con "!" si hay algo que resolver (ver DibujoIcono.swift).
        Image(nsImage: DibujoIcono.barra(aviso: modelo.necesitaAtencion))
            .onChange(of: modelo.motor == nil, initial: true) {
                // Esperamos a que termine la primera detección, y revisamos una sola vez.
                guard modelo.motor != nil, !modelo.revisionInicialHecha else { return }
                modelo.revisionInicialHecha = true
                if modelo.necesitaAtencion {
                    mostrarVentana()
                }
                // La primera vez, si falta el Acceso total al disco, la bienvenida
                // (se abre la última para que quede delante).
                if !modelo.accesoTotal && !modelo.bienvenidaVista {
                    mostrarVentana(id: "bienvenida", titulo: "Bienvenido a Garita")
                }
            }
            .onChange(of: modelo.peticionesDeVentana) {
                mostrarVentana()
            }
    }

    private func mostrarVentana(id: String = "principal", titulo: String = "Garita") {
        abrirVentana(id: id)
        NSApplication.shared.activate()

        // Si ya estaba abierta, openWindow no la trae delante, y macOS puede
        // terminar de activar la app después (p. ej. al pulsar una notificación)
        // y dejarla detrás de otras. Así que, un instante después, la buscamos
        // y la ponemos delante nosotros.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            let ventana = NSApplication.shared.windows.first {
                !($0 is NSPanel)    // el desplegable de la barra es un NSPanel
                    && ($0.identifier?.rawValue.hasPrefix(id) == true || $0.title == titulo)
            }
            ventana?.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate()
        }
    }
}
