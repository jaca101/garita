import AppKit
import SwiftUI

/// Qué selector de archivos hay que mostrar.
enum Selector: Equatable {
    case escanear          // archivos o carpetas a escanear
    case añadirCarpetas    // carpetas para el vigilante
}

/// Selectores de archivos (NSOpenPanel) como hoja de la ventana de Garita.
///
/// Desde el desplegable de la barra no se pueden mostrar bien: el desplegable
/// se cierra en cuanto el selector toma el foco, y el usuario deja de ver qué
/// pasa. Por eso el desplegable abre la ventana y el selector aparece pegado a
/// ella (ver MenuPrincipal.pedirSelector).
@MainActor
enum Selectores {

    /// La ventana "Garita" (no el desplegable de la barra, que es un NSPanel).
    static func ventanaPrincipal() -> NSWindow? {
        NSApplication.shared.windows.first {
            !($0 is NSPanel) && $0.isVisible
                && ($0.identifier?.rawValue.hasPrefix("principal") == true || $0.title == "Garita")
        }
    }

    static func mostrar(_ tipo: Selector, modelo: ModeloApp) {
        let selector = NSOpenPanel()
        selector.canChooseDirectories = true
        switch tipo {
        case .escanear:
            selector.canChooseFiles = true
            selector.allowsMultipleSelection = true
            selector.prompt = "Escanear"
        case .añadirCarpetas:
            selector.canChooseFiles = false
            selector.allowsMultipleSelection = true
            selector.prompt = "Vigilar"
            selector.message = "Elige las carpetas que Garita debe vigilar"
        }

        let alTerminar: (NSApplication.ModalResponse) -> Void = { respuesta in
            guard respuesta == .OK else { return }
            switch tipo {
            case .escanear: modelo.escanear(selector.urls)
            case .añadirCarpetas: modelo.añadirCarpetasVigiladas(selector.urls)
            }
        }

        NSApplication.shared.activate()
        if let ventana = ventanaPrincipal() {
            selector.beginSheetModal(for: ventana, completionHandler: alTerminar)
        } else {
            alTerminar(selector.runModal())   // por si acaso no hay ventana
        }
    }
}

// MARK: - Confirmaciones

/// Una pregunta de confirmación y lo que se hace si el usuario acepta.
struct Confirmacion: Identifiable, Sendable {
    let id = UUID()
    var titulo: String
    var texto: String
    var boton: String
    var accion: @MainActor @Sendable () -> Void
}

extension Confirmacion {
    /// La de "Marcar como seguro" (se usa en tres sitios).
    static func seguro(nombre: String, amenaza: String,
                       accion: @escaping @MainActor @Sendable () -> Void) -> Confirmacion {
        Confirmacion(
            titulo: "¿Marcar «\(nombre)» como seguro?",
            texto: """
            ClamAV lo detecta como «\(amenaza)». Garita dejará de avisar de este archivo \
            mientras no cambie (se reconoce por su huella SHA-256; si cambia un solo byte, \
            se vuelve a analizar).

            Hazlo solo si has comprobado que es un falso positivo, por ejemplo comparando \
            su huella con la que publica el fabricante.
            """,
            boton: "Marcar como seguro",
            accion: accion)
    }
}

extension Selectores {
    /// Muestra la confirmación como hoja de la ventana de Garita y, si el
    /// usuario acepta, ejecuta la acción.
    static func mostrar(_ confirmacion: Confirmacion) {
        let alerta = NSAlert()
        alerta.messageText = confirmacion.titulo
        alerta.informativeText = confirmacion.texto
        alerta.alertStyle = .warning
        alerta.addButton(withTitle: confirmacion.boton)
        alerta.addButton(withTitle: "Cancelar")

        NSApplication.shared.activate()
        if let ventana = ventanaPrincipal() {
            alerta.beginSheetModal(for: ventana) { respuesta in
                if respuesta == .alertFirstButtonReturn {
                    MainActor.assumeIsolated { confirmacion.accion() }
                }
            }
        } else if alerta.runModal() == .alertFirstButtonReturn {
            confirmacion.accion()
        }
    }
}

/// Cómo pedir una confirmación desde cualquier vista (se usa como función:
/// `pedirConfirmacion(confirmacion)`). MenuPrincipal pone la suya: en el
/// desplegable abre antes la ventana.
struct AccionConfirmar: Equatable, Sendable {
    /// Solo sirve para comparar (SwiftUI compara los valores del entorno para
    /// saber si tiene que redibujar): la acción depende de dónde se usa.
    var enVentana: Bool
    var ejecutar: @MainActor @Sendable (Confirmacion) -> Void

    @MainActor func callAsFunction(_ confirmacion: Confirmacion) { ejecutar(confirmacion) }

    static func == (a: Self, b: Self) -> Bool { a.enVentana == b.enVentana }
}

extension EnvironmentValues {
    @Entry var pedirConfirmacion = AccionConfirmar(enVentana: true) { Selectores.mostrar($0) }
}
