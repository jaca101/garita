import AppKit

/// Servicio de macOS "Escanear con Garita": aparece al hacer clic derecho sobre
/// archivos o carpetas en el Finder.
///
/// Cómo funciona:
/// 1. Info.plist declara el servicio (clave NSServices): su nombre en el menú,
///    qué tipos acepta (cualquier archivo o carpeta) y el mensaje a enviar.
/// 2. Al elegirlo, macOS arranca Garita si no lo estaba y llama al método de
///    abajo, cuyo nombre coincide con NSMessage ("escanearConGarita").
final class ServicioFinder: NSObject {
    private let modelo: ModeloApp

    init(modelo: ModeloApp) {
        self.modelo = modelo
    }

    /// macOS nos pasa los archivos seleccionados en un "portapapeles" propio del servicio.
    @MainActor
    @objc func escanearConGarita(
        _ portapapeles: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let urls = portapapeles.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []

        guard !urls.isEmpty else {
            error.pointee = "No se recibió ningún archivo." as NSString
            return
        }
        modelo.escanearDesdeFinder(urls)
    }
}

/// Delegado de la app (la parte de AppKit): registra el servicio al arrancar.
@MainActor
final class DelegadoApp: NSObject, NSApplicationDelegate {
    /// Estado único de la app. Vive aquí para que el servicio y las vistas
    /// compartan el mismo.
    let modelo = ModeloApp()
    private var servicio: ServicioFinder?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let servicio = ServicioFinder(modelo: modelo)
        self.servicio = servicio
        NSApplication.shared.servicesProvider = servicio
    }
}
