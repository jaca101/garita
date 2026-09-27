import Foundation

/// Estado del escaneo rápido, para mostrarlo en el panel.
enum EstadoClamd: Equatable {
    case desactivado
    case arrancando
    case activo(memoriaMB: Int?)
    case error(String)
}

/// "Escaneo rápido" (opcional): el servicio clamd de ClamAV.
///
/// clamd carga las firmas UNA vez (~8 s y ~1,6 GB de memoria) y se queda en
/// marcha; clamdscan le pide los escaneos, que así empiezan al instante en vez
/// de tardar ~7 s en cargar firmas cada vez. Garita lo arranca como proceso
/// propio y lo cierra al salir.
///
///   configuración: ~/Library/Application Support/Garita/clamav/clamd.conf
///   registro:      ~/Library/Application Support/Garita/clamav/clamd.log
///   socket:        <carpeta temporal privada del usuario>/garita-clamd.sock
///                  (macOS limita la ruta de un socket a 104 caracteres)
@MainActor
final class ServicioClamd {

    static var config: URL { MotorClamAV.carpetaDatos.appending(path: "clamd.conf") }
    static var registro: URL { MotorClamAV.carpetaDatos.appending(path: "clamd.log") }
    static var socket: URL { URL(filePath: NSTemporaryDirectory()).appending(path: "garita-clamd.sock") }

    private var proceso: Process?
    /// true mientras lo paramos nosotros (para no confundirlo con un cierre inesperado).
    private var deteniendo = false
    /// Qué hacer si clamd se cierra solo (lo usa el modelo para mostrar el error).
    var alCerrarseSolo: (() -> Void)?

    // MARK: - Programas

    /// clamd y clamdscan van junto a clamscan, en Contents/Helpers (solo el ClamAV integrado).
    static func ayudante(_ nombre: String, _ motor: EstadoMotor) -> URL? {
        guard motor.integrado, let clamscan = motor.clamscan else { return nil }
        let url = clamscan.deletingLastPathComponent().appending(path: nombre)
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    static func disponible(_ motor: EstadoMotor) -> Bool {
        ayudante("clamd", motor) != nil && ayudante("clamdscan", motor) != nil
    }

    /// Cómo escanear a través de clamd.
    static func programa(_ motor: EstadoMotor) -> Programa? {
        guard let clamdscan = ayudante("clamdscan", motor) else { return nil }
        return Programa(ejecutable: clamdscan, opciones: ["--config-file=\(config.path)"], esClamd: true)
    }

    // MARK: - Configuración

    /// Mismos límites que usa Garita con clamscan (ver Escaner.opcionesLimites).
    static func escribirConfig(_ motor: EstadoMotor) throws {
        guard let firmas = motor.carpetaFirmas, let certificados = motor.certificados else { return }
        try FileManager.default.createDirectory(at: MotorClamAV.carpetaDatos, withIntermediateDirectories: true)
        let texto = """
        # clamd.conf de Garita (lo genera la app; los cambios se sobrescriben).
        LocalSocket \(socket.path)
        # Solo nuestro usuario puede hablar con clamd:
        LocalSocketMode 600
        # Garita lo arranca y lo para; no se separa como demonio:
        Foreground yes
        DatabaseDirectory \(firmas.path)
        CVDCertsDirectory \(certificados.path)
        # Mismos límites que clamscan en Garita:
        MaxFileSize 2000M
        MaxScanSize 4000M
        MaxFiles 100000
        MaxScanTime 600000
        AlertExceedsMax yes

        """
        try texto.write(to: config, atomically: true, encoding: .utf8)
    }

    /// Cierra cualquier clamd de Garita que haya quedado de una ejecución anterior.
    static func cerrarHuerfanos() {
        _ = Proceso.ejecutar(URL(filePath: "/usr/bin/pkill"), argumentos: ["-f", "clamd --config-file=\(config.path)"])
        try? FileManager.default.removeItem(at: socket)
    }

    // MARK: - Arrancar, recargar, parar

    /// Arranca clamd y espera a que responda (tiene que cargar las firmas).
    func arrancar(_ motor: EstadoMotor) async -> EstadoClamd {
        detener()
        Self.cerrarHuerfanos()
        guard let clamd = Self.ayudante("clamd", motor), let clamdscan = Self.ayudante("clamdscan", motor),
              let certificados = motor.certificados else {
            return .error("Este ClamAV no incluye clamd.")
        }
        do {
            try Self.escribirConfig(motor)
        } catch {
            return .error("No se pudo escribir clamd.conf: \(error.localizedDescription)")
        }

        let p = Process()
        p.executableURL = clamd
        p.arguments = ["--config-file=\(Self.config.path)"]
        p.environment = ProcessInfo.processInfo.environment.merging(["CVD_CERTS_DIR": certificados.path]) { $1 }
        FileManager.default.createFile(atPath: Self.registro.path, contents: nil)
        let registro = try? FileHandle(forWritingTo: Self.registro)
        p.standardOutput = registro
        p.standardError = registro
        p.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.deteniendo else { return }
                self.proceso = nil
                self.alCerrarseSolo?()
            }
        }
        do {
            try p.run()
        } catch {
            return .error("No se pudo arrancar clamd: \(error.localizedDescription)")
        }
        proceso = p

        // Esperamos hasta 3 minutos a que responda (normalmente, ~8 s).
        let config = Self.config.path
        let responde = await Task.detached {
            Proceso.ejecutar(clamdscan, argumentos: ["--config-file=\(config)", "--ping", "180:1"])?.codigo == 0
        }.value
        guard responde, p.isRunning else {
            detener()
            return .error("clamd no arrancó (detalles en clamd.log).")
        }
        return .activo(memoriaMB: await memoriaMB())
    }

    /// Tras actualizar las firmas, que clamd las vuelva a cargar.
    func recargar(_ motor: EstadoMotor) async {
        guard proceso != nil, let programa = Self.programa(motor) else { return }
        _ = await Task.detached {
            Proceso.ejecutar(programa.ejecutable, argumentos: programa.opciones + ["--reload"])
        }.value
    }

    func detener() {
        deteniendo = true
        proceso?.terminate()
        proceso?.waitUntilExit()
        proceso = nil
        deteniendo = false
        try? FileManager.default.removeItem(at: Self.socket)
    }

    /// Memoria que ocupa clamd ahora (en MB): su huella real ("phys_footprint"),
    /// la misma que muestra el Monitor de Actividad. Incluye la parte que macOS
    /// comprime cuando clamd está inactivo (`ps` solo cuenta la que no lo está,
    /// y tras un rato sin uso daba casi 0).
    func memoriaMB() async -> Int? {
        guard let pid = proceso?.processIdentifier else { return nil }
        var uso = rusage_info_v4()
        let ok = withUnsafeMutablePointer(to: &uso) { puntero in
            puntero.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) == 0
            }
        }
        return ok ? Int(uso.ri_phys_footprint / 1_048_576) : nil
    }
}
