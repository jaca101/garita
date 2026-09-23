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

        // Ventana con el mismo panel. No se abre sola al arrancar: la abre
        // IconoBarra cuando hay algo que resolver o al escanear desde el Finder.
        Window("Garita", id: "principal") {
            MenuPrincipal()
                .environment(modelo)
                .onAppear {
                    // Las apps sin Dock no pasan al frente solas: la traemos delante.
                    NSApplication.shared.activate()
                }
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

/// El icono de la barra: escudo normal si todo va bien, escudo con aviso si no.
///
/// Además, es la única vista que existe desde el arranque (el panel no se crea
/// hasta que se pulsa el icono), así que desde aquí se abre la ventana cuando toca.
private struct IconoBarra: View {
    @Environment(ModeloApp.self) private var modelo
    @Environment(\.openWindow) private var abrirVentana

    var body: some View {
        Image(systemName: modelo.necesitaAtencion ? "exclamationmark.shield.fill" : "shield.lefthalf.filled")
            .onChange(of: modelo.motor == nil, initial: true) {
                // Esperamos a que termine la primera detección, y revisamos una sola vez.
                guard modelo.motor != nil, !modelo.revisionInicialHecha else { return }
                modelo.revisionInicialHecha = true
                if modelo.necesitaAtencion {
                    mostrarVentana()
                }
            }
            .onChange(of: modelo.peticionesDeVentana) {
                mostrarVentana()
            }
    }

    private func mostrarVentana() {
        abrirVentana(id: "principal")
        // Si ya estaba abierta, openWindow no la trae delante por sí solo.
        NSApplication.shared.activate()
    }
}
