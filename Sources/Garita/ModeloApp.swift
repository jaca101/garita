import Foundation
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

    /// ¿Hay algo que el usuario deba resolver? (motor incompleto o firmas antiguas)
    var necesitaAtencion: Bool {
        guard let motor else { return false }
        return !motor.listo || motor.firmasAntiguas
    }

    /// Para revisar solo una vez, al arrancar, si hay que abrir la ventana.
    var revisionInicialHecha = false

    init() {
        comprobarMotor()
    }

    /// Vuelve a detectar ClamAV en segundo plano, sin bloquear la interfaz.
    func comprobarMotor() {
        Task {
            motor = await Task.detached { MotorClamAV.detectar() }.value
            escanearPendientes()
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
}
