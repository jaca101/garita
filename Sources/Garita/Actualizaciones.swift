import AppKit
import Sparkle

/// Actualizaciones de Garita con Sparkle (https://sparkle-project.org).
///
/// Cada día, Sparkle lee el "appcast" (un XML con la última versión) publicado
/// en GitHub Releases (SUFeedURL en Info.plist). Si hay una versión nueva, la
/// descarga, comprueba su firma EdDSA con la clave pública de Info.plist
/// (SUPublicEDKey) y pregunta antes de instalarla. Una actualización que no
/// esté firmada con la clave privada de Garita (en el llavero del autor) se rechaza.
///
/// Para probar con un appcast local:
///   defaults write io.github.jaca101.garita PruebaAppcast http://127.0.0.1:8765/appcast.xml
/// y para volver al de GitHub:
///   defaults delete io.github.jaca101.garita PruebaAppcast
@MainActor
@Observable
final class Actualizaciones: NSObject {

    /// false mientras Sparkle ya está buscando o instalando (el botón se desactiva).
    private(set) var puedeBuscar = false

    /// Buscar solas una vez al día (lo guarda Sparkle en las preferencias).
    var automaticas: Bool {
        get { access(keyPath: \.automaticas); return controlador.updater.automaticallyChecksForUpdates }
        set { withMutation(keyPath: \.automaticas) { controlador.updater.automaticallyChecksForUpdates = newValue } }
    }

    /// Versión instalada, p. ej. "0.2.2".
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"

    @ObservationIgnored private var controlador: SPUStandardUpdaterController!
    @ObservationIgnored private var observacion: NSKeyValueObservation?

    override init() {
        super.init()
        controlador = SPUStandardUpdaterController(startingUpdater: true,
                                                   updaterDelegate: self,
                                                   userDriverDelegate: self)
        observacion = controlador.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.puedeBuscar = self.controlador.updater.canCheckForUpdates
            }
        }
    }

    /// "Buscar actualizaciones…": siempre muestra el resultado (también "ya tienes la última").
    func buscarAhora() {
        NSApplication.shared.activate()
        controlador.checkForUpdates(nil)
    }
}

extension Actualizaciones: SPUUpdaterDelegate {
    /// El appcast de pruebas, si se ha configurado (ver arriba); si no, el de Info.plist.
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        UserDefaults.standard.string(forKey: "PruebaAppcast")
    }
}

extension Actualizaciones: SPUStandardUserDriverDelegate {
    /// Garita vive en la barra de menú (sin Dock), así que Sparkle no puede
    /// contar con que la app esté delante: le decimos que sabemos avisar.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Cuando Sparkle va a enseñar su ventana ("Hay una versión nueva…"),
    /// traemos Garita delante para que no quede escondida detrás de otras apps.
    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                               forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        guard handleShowingUpdate else { return }
        Task { @MainActor in NSApplication.shared.activate() }
    }
}
