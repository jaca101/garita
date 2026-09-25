import AppKit
import Observation
import ServiceManagement

/// Cómo va un escaneo largo: desde cuándo, cuántos archivos y cuál fue el último.
struct ProgresoEscaneo {
    var inicio = Date()
    var archivos = 0
    var ultimo: String?

    mutating func avanzar(_ archivos: Int, _ ultimo: String) {
        self.archivos = archivos
        self.ultimo = ultimo
    }
}

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

    /// Último intento de actualización automática (para no reintentar sin parar si falla).
    @ObservationIgnored var ultimoIntentoAutomatico: Date?

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
    /// Progreso del escaneo a demanda en curso (nil si no hay ninguno).
    var progresoEscaneo: ProgresoEscaneo?
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
    /// Carpetas vigiladas, elegidas por el usuario (se guardan entre arranques).
    /// La primera vez: las predeterminadas que existan (Descargas, aMule Downloads).
    var carpetasVigiladas: [URL] = ModeloApp.cargarCarpetasVigiladas() {
        didSet {
            UserDefaults.standard.set(carpetasVigiladas.map(\.path), forKey: "carpetasVigiladas")
            aplicarVigilante()
        }
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

    // MARK: Escaneos programados (la lógica está en ModeloApp+Programados.swift)

    var programados: [TareaProgramada] = Programados.cargar()
    /// La tarea que se está ejecutando ahora (nil si ninguna).
    var tareaEnCurso: UUID?
    /// Progreso de la tarea en curso.
    var progresoProgramado: ProgresoEscaneo?
    /// Tarea abierta en el editor ("Programar escaneo").
    var borradorTarea: TareaProgramada?
    @ObservationIgnored var pidProgramado: Int32?
    @ObservationIgnored var programadoCancelado = false
    /// Arranque de Garita o último despertar del Mac (para dejar un margen).
    @ObservationIgnored var despertoEn = Date()

    /// ¿Tiene Garita Acceso total al disco? Se vuelve a comprobar cada vez que
    /// Garita pasa a primer plano (p. ej. al volver de Ajustes del Sistema).
    var accesoTotal = AccesoDisco.concedido()
    /// La ventana de bienvenida ya se mostró y se cerró ("Empezar" o "Ahora no").
    var bienvenidaVista = UserDefaults.standard.bool(forKey: "bienvenidaVista") {
        didSet { UserDefaults.standard.set(bienvenidaVista, forKey: "bienvenidaVista") }
    }

    /// ¿Se abre Garita al iniciar sesión? (ítem de inicio de macOS, vía SMAppService)
    var abrirAlIniciar = SMAppService.mainApp.status == .enabled
    /// macOS pide aprobarlo en Ajustes → General → Ítems de inicio.
    var inicioRequiereAprobacion = SMAppService.mainApp.status == .requiresApproval
    var errorInicio: String?

    /// Para revisar solo una vez, al arrancar, si hay que abrir la ventana.
    var revisionInicialHecha = false

    init() {
        comprobarMotor()
        vigilante = Vigilante { [weak self] archivos in
            self?.recibirDelVigilante(archivos)
        }
        aplicarVigilante()
        comprobarNotificaciones()
        configurarInicioLaPrimeraVez()
        arrancarProgramador()

        // Al volver a Garita (p. ej. desde Ajustes), revisamos el Acceso total al disco.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.comprobarAccesoTotal() }
        }
    }

    // MARK: - Abrir al iniciar sesión

    /// Activa o desactiva que Garita se abra al iniciar sesión.
    func cambiarAbrirAlIniciar(_ activar: Bool) {
        errorInicio = nil
        do {
            if activar {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorInicio = error.localizedDescription
        }
        let estado = SMAppService.mainApp.status
        abrirAlIniciar = estado == .enabled
        inicioRequiereAprobacion = estado == .requiresApproval
    }

    /// La primera vez que Garita se abre desde /Applications, la apuntamos para
    /// que arranque al iniciar sesión (un antivirus debe estar siempre en marcha).
    /// Solo una vez: si luego el usuario lo desactiva, se respeta.
    private func configurarInicioLaPrimeraVez() {
        let clave = "inicioConfigurado"
        guard Bundle.main.bundlePath.hasPrefix("/Applications/"),
              !UserDefaults.standard.bool(forKey: clave) else { return }
        UserDefaults.standard.set(true, forKey: clave)
        cambiarAbrirAlIniciar(true)
    }

    func comprobarAccesoTotal() {
        accesoTotal = AccesoDisco.concedido()
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
            revisarActualizacionAutomatica()
            escanearPendientes()
            escanearColaVigilante()
        }
    }

    /// Actualiza las firmas sola si no hay ninguna, o si la última actualización
    /// correcta fue hace más de 12 horas. Si falla (p. ej. sin conexión), no lo
    /// reintenta hasta pasados 30 minutos. Se llama al arrancar y cada minuto.
    func revisarActualizacionAutomatica() {
        guard let motor, motor.freshclam != nil, !actualizandoFirmas else { return }
        if let intento = ultimoIntentoAutomatico, Date().timeIntervalSince(intento) < 30 * 60 { return }
        let antiguas = ultimaComprobacion.map { Date().timeIntervalSince($0) > Firmas.intervaloAutomatico } ?? true
        guard !motor.hayFirmas || antiguas else { return }
        ultimoIntentoAutomatico = Date()
        actualizarFirmas()
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
        guard let motor, let clamscan = motor.clamscan, motor.listo, !escaneando else {
            pendientes += rutas
            return
        }
        let opciones = motor.opcionesClamscan
        escaneando = true
        escaneoCancelado = false
        rutasEscaneo = rutas
        resultadoEscaneo = nil
        progresoEscaneo = ProgresoEscaneo()

        Task {
            var resultado = await Task.detached {
                let alArrancar: @Sendable (Int32) -> Void = { pid in
                    Task { @MainActor in self.pidEscaneo = pid }
                }
                let alAvanzar: @Sendable (Int, String) -> Void = { archivos, ultimo in
                    Task { @MainActor in self.progresoEscaneo?.avanzar(archivos, ultimo) }
                }
                let primero = Escaner.escanear(rutas, con: clamscan, opciones: opciones,
                                               alArrancar: alArrancar, alAvanzar: alAvanzar)
                // Lo que no se pudo analizar entero por los límites, a fondo.
                return AnalisisAFondo.completar(primero, clamscan: clamscan, opciones: opciones,
                                                prioridadBaja: false, alArrancar: alArrancar, alAvanzar: alAvanzar)
            }.value
            progresoEscaneo = nil
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

    /// Apunta los avisos en el historial y (si `notificar`) los muestra como
    /// notificación. Sin permiso para notificar, si alguno es importante
    /// (amenazas) abrimos la ventana para que no pase desapercibido.
    func avisar(_ avisos: [Aviso], notificar: Bool = true) {
        guard !avisos.isEmpty else { return }
        historial.insert(contentsOf: avisos, at: 0)
        if historial.count > Historial.maximo {
            historial.removeLast(historial.count - Historial.maximo)
        }
        Historial.guardar(historial)

        guard notificar else { return }
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
