import AppKit
import Observation

/// Estado compartido de toda la app. Las vistas lo leen y se redibujan solas
/// cuando cambia (gracias a @Observable).
@MainActor
@Observable
final class ModeloApp {
    /// Resultado de la última detección del motor (nil hasta la primera comprobación).
    var motor: EstadoMotor?

    /// true mientras freshclam está trabajando.
    var actualizandoFirmas = false
    /// Resultado de la última actualización de firmas, para mostrarlo en el panel.
    var mensajeFirmas: String?
    var errorFirmas = false

    /// Última vez que freshclam terminó bien (se guarda entre arranques).
    var ultimaComprobacion: Date? = UserDefaults.standard.object(forKey: "ultimaComprobacionFirmas") as? Date {
        didSet { UserDefaults.standard.set(ultimaComprobacion, forKey: "ultimaComprobacionFirmas") }
    }

    /// true mientras clamscan está trabajando en un escaneo a demanda.
    var escaneando = false
    /// Qué se está escaneando ahora (para mostrarlo en el panel).
    var rutasEscaneo: [URL] = []
    /// Resultado del último escaneo a demanda.
    var resultadoEscaneo: ResultadoEscaneo?
    /// Rutas que llegaron mientras no se podía escanear (motor aún sin detectar
    /// o escaneo en curso). Se escanean en cuanto se pueda.
    private var pendientes: [URL] = []
    /// Se incrementa para pedir que se abra la ventana (lo vigila IconoBarra,
    /// que es quien puede abrir ventanas de SwiftUI).
    var peticionesDeVentana = 0
    /// PID de clamscan mientras escanea, para poder cancelarlo.
    private var pidEscaneo: Int32?
    private var escaneoCancelado = false

    /// Archivos en cuarentena, lo más reciente primero.
    var cuarentena: [ElementoCuarentena] = Cuarentena.listar()
    /// Último error al aislar, restaurar o eliminar (para mostrarlo en el panel).
    var errorCuarentena: String?

    // MARK: Vigilante (la lógica está en ModeloApp+Vigilante.swift)

    /// Vigilar las carpetas de descargas (se guarda entre arranques).
    var vigilanteActivo = UserDefaults.standard.object(forKey: "vigilanteActivo") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(vigilanteActivo, forKey: "vigilanteActivo")
            aplicarVigilante()
        }
    }
    /// Si el vigilante detecta una amenaza: true = aislarla al momento; false = solo avisar.
    var aislarAutomaticamente = UserDefaults.standard.object(forKey: "aislarAutomaticamente") as? Bool ?? true {
        didSet { UserDefaults.standard.set(aislarAutomaticamente, forKey: "aislarAutomaticamente") }
    }
    /// Carpetas vigiladas (de las predeterminadas, las que existen).
    var carpetasVigiladas: [URL] = ModeloApp.carpetasPorDefecto.filter {
        FileManager.default.fileExists(atPath: $0.path)
    }
    /// Lo que ha hecho el vigilante, lo más reciente primero.
    var actividad: [EventoVigilante] = []
    /// Archivos que el vigilante está escaneando ahora (vacío si no hay ninguno).
    var vigilanteEscaneando: [URL] = []
    /// Archivos nuevos a la espera de escanear (p. ej. mientras otro lote está en marcha).
    @ObservationIgnored var colaVigilante: [URL] = []
    @ObservationIgnored var vigilante: Vigilante?

    /// ¿Hay algo que el usuario deba resolver? Motor incompleto, firmas antiguas
    /// o amenazas del vigilante sin aislar.
    var necesitaAtencion: Bool {
        guard let motor else { return false }
        return !motor.listo || motor.firmasAntiguas
            || actividad.contains { $0.pendienteDeResolver }
    }

    /// ¿Ha dado el usuario permiso para notificaciones? (se pregunta al arrancar)
    var notificacionesPermitidas = false
    /// Avisos enviados, lo más reciente primero (se guardan en historial.json).
    var historial: [Aviso] = Historial.cargar()

    /// Cuántas ventanas de Garita hay abiertas (principal, historial). Con alguna
    /// abierta, Garita es app normal (Dock y ⌘Tab); con ninguna, solo barra de menú.
    @ObservationIgnored var ventanasAbiertas = 0

    /// Para revisar solo una vez, al arrancar, si hay que abrir la ventana.
    var revisionInicialHecha = false

    init() {
        comprobarMotor()
        vigilante = Vigilante { [weak self] archivos in
            self?.recibirDelVigilante(archivos)
        }
        aplicarVigilante()
        comprobarNotificaciones()
    }

    /// Pide permiso para notificar (macOS solo pregunta la primera vez) y apunta la respuesta.
    func comprobarNotificaciones() {
        Task {
            notificacionesPermitidas = await Notificaciones.pedirPermiso()
        }
    }

    /// Vuelve a detectar ClamAV en segundo plano, sin bloquear la interfaz.
    func comprobarMotor() {
        Task {
            motor = await Task.detached { MotorClamAV.detectar() }.value
            escanearPendientes()
            escanearColaVigilante()
        }
    }

    /// Ejecuta freshclam en segundo plano y, al acabar, vuelve a detectar el motor
    /// para que el panel muestre la nueva versión y fecha de las firmas.
    func actualizarFirmas() {
        guard let motor, !actualizandoFirmas else { return }
        actualizandoFirmas = true
        mensajeFirmas = nil

        Task {
            let resultado = await Task.detached { Firmas.actualizar(motor: motor) }.value
            actualizandoFirmas = false
            mensajeFirmas = resultado.mensaje
            errorFirmas = !resultado.ok
            if resultado.ok {
                ultimaComprobacion = Date()
            }
            comprobarMotor()
        }
    }

    /// Escanea archivos o carpetas en segundo plano.
    func escanear(_ rutas: [URL]) {
        guard !rutas.isEmpty else { return }
        // Si aún no se puede, lo guardamos para después (p. ej. el Finder ha
        // arrancado Garita con "Escanear con Garita" y el motor no está detectado).
        guard let clamscan = motor?.clamscan, motor?.listo == true, !escaneando else {
            pendientes += rutas
            return
        }
        escaneando = true
        escaneoCancelado = false
        rutasEscaneo = rutas
        resultadoEscaneo = nil

        Task {
            var resultado = await Task.detached {
                Escaner.escanear(rutas, con: clamscan) { pid in
                    Task { @MainActor in self.pidEscaneo = pid }
                }
            }.value
            resultado.cancelado = escaneoCancelado
            pidEscaneo = nil
            escaneando = false
            resultadoEscaneo = resultado
            // Si el usuario no está mirando Garita (p. ej. cerró el panel), le avisamos.
            if !NSApplication.shared.isActive, let aviso = Notificaciones.aviso(para: resultado) {
                avisar([aviso])
            }
            escanearPendientes()
        }
    }

    /// Escanea, todas juntas, las rutas que quedaron a la espera.
    private func escanearPendientes() {
        guard !pendientes.isEmpty, motor?.listo == true, !escaneando else { return }
        let rutas = pendientes
        pendientes = []
        escanear(rutas)
    }

    /// Escaneo pedido desde el Finder (clic derecho → "Escanear con Garita").
    /// Abre la ventana para que se vea el progreso y el resultado.
    func escanearDesdeFinder(_ rutas: [URL]) {
        peticionesDeVentana += 1
        escanear(rutas)
    }

    /// Detiene el escaneo en curso.
    func cancelarEscaneo() {
        guard let pidEscaneo else { return }
        escaneoCancelado = true
        Proceso.detener(pid: pidEscaneo)
    }

    // MARK: - Avisos

    /// Apunta los avisos en el historial y los muestra como notificación.
    /// Sin permiso para notificar, si alguno es importante (amenazas) abrimos la
    /// ventana para que no pase desapercibido.
    func avisar(_ avisos: [Aviso]) {
        guard !avisos.isEmpty else { return }
        historial.insert(contentsOf: avisos, at: 0)
        if historial.count > Historial.maximo {
            historial.removeLast(historial.count - Historial.maximo)
        }
        Historial.guardar(historial)

        if notificacionesPermitidas {
            avisos.forEach(Notificaciones.enviar)
        } else if avisos.contains(where: \.importante) {
            peticionesDeVentana += 1
        }
    }

    func borrarHistorial() {
        historial = []
        Historial.guardar(historial)
    }

    // MARK: - Ventanas

    /// Llamar al aparecer/desaparecer cada ventana de Garita.
    func ventanaAbierta() {
        ventanasAbiertas += 1
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    func ventanaCerrada() {
        ventanasAbiertas = max(0, ventanasAbiertas - 1)
        if ventanasAbiertas == 0 {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Cuarentena

    /// Vuelve a leer la carpeta de cuarentena (por si ha cambiado desde fuera).
    func recargarCuarentena() {
        cuarentena = Cuarentena.listar()
    }

    /// Mueve a la cuarentena un archivo detectado en el último escaneo.
    func aislar(_ deteccion: Deteccion) {
        errorCuarentena = nil
        do {
            let elemento = try Cuarentena.aislar(deteccion.archivo, amenaza: deteccion.amenaza)
            cuarentena.insert(elemento, at: 0)
            // Marcamos la detección como aislada para que el panel lo refleje.
            if let i = resultadoEscaneo?.detecciones.firstIndex(where: { $0.id == deteccion.id }) {
                resultadoEscaneo?.detecciones[i].aislada = true
            }
        } catch {
            errorCuarentena = "No se pudo aislar \(deteccion.archivo.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Aísla todas las detecciones del último escaneo que aún no lo estén.
    func aislarTodas() {
        for deteccion in resultadoEscaneo?.detecciones ?? [] where !deteccion.aislada {
            aislar(deteccion)
        }
    }

    /// Devuelve un archivo a su sitio y lo muestra en el Finder.
    func restaurar(_ elemento: ElementoCuarentena) -> URL? {
        errorCuarentena = nil
        do {
            let destino = try Cuarentena.restaurar(elemento)
            cuarentena.removeAll { $0.id == elemento.id }
            // Si vuelve a una carpeta vigilada, que el vigilante no lo aísle otra vez.
            vigilante?.ignorarUnaVez(destino)
            return destino
        } catch {
            errorCuarentena = "No se pudo restaurar \(elemento.nombreOriginal): \(error.localizedDescription)"
            return nil
        }
    }

    /// Borra definitivamente un archivo de la cuarentena.
    func eliminar(_ elemento: ElementoCuarentena) {
        errorCuarentena = nil
        do {
            try Cuarentena.eliminar(elemento)
            cuarentena.removeAll { $0.id == elemento.id }
        } catch {
            errorCuarentena = "No se pudo eliminar \(elemento.nombreOriginal): \(error.localizedDescription)"
        }
    }
}
