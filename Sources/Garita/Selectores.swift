import AppKit

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
