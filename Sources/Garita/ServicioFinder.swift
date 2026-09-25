import AppKit
import OSLog
import UserNotifications

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

/// Delegado de la app (la parte de AppKit): registra el servicio del Finder al
/// arrancar y atiende las notificaciones.
@MainActor
final class DelegadoApp: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Estado único de la app. Vive aquí para que el servicio y las vistas
    /// compartan el mismo.
    let modelo = ModeloApp()
    private var servicio: ServicioFinder?
    /// Registro en el log del sistema (se ve con: log show --predicate 'subsystem == "local.garita"').
    private nonisolated let registro = Logger(subsystem: "local.garita", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let servicio = ServicioFinder(modelo: modelo)
        self.servicio = servicio
        NSApplication.shared.servicesProvider = servicio
        UNUserNotificationCenter.current().delegate = self
        // Las notificaciones de ejecuciones anteriores ya no llevan a ningún sitio;
        // las retiramos (siguen en el historial de Garita).
        Notificaciones.retirarAntiguas()
        // Por si un análisis a fondo quedó a medias (Garita cerrada, apagón…).
        Task.detached(priority: .background) { AnalisisAFondo.limpiarRestos() }
    }

    /// "Reabrir" la app: doble clic en Garita.app estando ya abierta, o pulsar una
    /// de sus notificaciones. Por defecto SwiftUI mostraría/ocultaría el desplegable
    /// de la barra; nosotros abrimos siempre la ventana.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        registro.info("Reabrir la app → abrir la ventana")
        modelo.peticionesDeVentana += 1
        return false
    }

    /// Mostrar las notificaciones también cuando Garita está en primer plano.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// Al pulsar una notificación, abrimos la ventana de Garita.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        registro.info("Notificación pulsada → abrir la ventana")
        await MainActor.run {
            modelo.peticionesDeVentana += 1
        }
    }
}
