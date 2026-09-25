import Foundation

/// Actualiza la base de firmas de virus con `freshclam`.
enum Firmas {

    /// Cada cuánto se actualizan solas (ClamAV publica varias veces al día).
    static let intervaloAutomatico: TimeInterval = 12 * 3600

    /// Homebrew: crea `freshclam.conf` a partir del ejemplo que instala Homebrew
    /// (`freshclam.conf.sample`). El ejemplo trae una línea `Example` que hace que
    /// freshclam se niegue a arrancar; la comentamos y dejamos el resto tal cual.
    static func crearConfigHomebrew(en config: URL) throws {
        let ejemplo = URL(filePath: config.path + ".sample")
        let texto = try String(contentsOf: ejemplo, encoding: .utf8)

        let lineas = texto.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasPrefix("Example") ? "#" + $0 : String($0) }

        try lineas.joined(separator: "\n").write(to: config, atomically: true, encoding: .utf8)
    }

    /// ClamAV integrado: escribe su propio `freshclam.conf` (se reescribe cada vez,
    /// así las rutas siempre apuntan a donde está la app ahora).
    static func escribirConfigIntegrada(_ motor: EstadoMotor) throws {
        guard let config = motor.configFreshclam, let firmas = motor.carpetaFirmas,
              let certificados = motor.certificados else { return }
        try FileManager.default.createDirectory(at: firmas, withIntermediateDirectories: true)
        let texto = """
        # freshclam.conf de Garita (lo genera la app; los cambios se sobrescriben).
        # Dónde se guardan las firmas:
        DatabaseDirectory \(firmas.path)
        # Certificado para verificar que las firmas descargadas son auténticas:
        CVDCertsDirectory \(certificados.path)
        # Servidor oficial de ClamAV:
        DatabaseMirror database.clamav.net

        """
        try texto.write(to: config, atomically: true, encoding: .utf8)
    }

    /// Si el ClamAV integrado aún no tiene firmas pero en este Mac hay unas de
    /// Homebrew, las copiamos: freshclam solo tendrá que bajar lo que falte
    /// (en vez de ~110 MB).
    static func copiarFirmasDeHomebrewSiHay(_ motor: EstadoMotor) {
        guard motor.integrado, !motor.hayFirmas, let destino = motor.carpetaFirmas,
              let origen = MotorClamAV.firmasDeHomebrew else { return }
        let fm = FileManager.default
        let nombres = (try? fm.contentsOfDirectory(atPath: origen.path)) ?? []
        for nombre in nombres where [".cvd", ".cld", ".sign"].contains(where: nombre.hasSuffix) {
            try? fm.copyItem(at: origen.appending(path: nombre), to: destino.appending(path: nombre))
        }
    }

    /// Ejecuta freshclam y devuelve un mensaje para mostrar al usuario.
    /// La primera vez puede tardar unos minutos (descarga unos 110 MB).
    /// Bloquea: llamarla fuera del hilo principal.
    static func actualizar(motor: EstadoMotor) -> (ok: Bool, mensaje: String) {
        guard let freshclam = motor.freshclam, let config = motor.configFreshclam else {
            return (false, "No se encontró freshclam.")
        }

        var argumentos: [String] = []
        var entorno: [String: String] = [:]
        do {
            if motor.integrado {
                try escribirConfigIntegrada(motor)
                copiarFirmasDeHomebrewSiHay(motor)
                if let firmas = motor.carpetaFirmas, let certificados = motor.certificados {
                    argumentos = ["--config-file=\(config.path)",
                                  "--datadir=\(firmas.path)",
                                  "--cvdcertsdir=\(certificados.path)"]
                    // freshclam comprueba las firmas nuevas en un subproceso que no
                    // recibe --cvdcertsdir; por eso también se lo decimos por aquí.
                    entorno = ["CVD_CERTS_DIR": certificados.path]
                }
            } else if !motor.configExiste {
                try crearConfigHomebrew(en: config)
            }
        } catch {
            return (false, "No se pudo preparar la configuración (\(config.path)): \(error.localizedDescription)")
        }

        guard let resultado = Proceso.ejecutar(freshclam, argumentos: argumentos, entorno: entorno) else {
            return (false, "No se pudo ejecutar freshclam.")
        }

        // freshclam devuelve 0 si ha actualizado o ya estaba al día.
        // Cualquier otro código es un error; mostramos sus últimas líneas.
        if resultado.codigo == 0 {
            return (true, "Firmas actualizadas.")
        } else {
            let ultimas = resultado.salida.split(separator: "\n").suffix(3).joined(separator: "\n")
            return (false, "freshclam falló (código \(resultado.codigo)):\n\(ultimas)")
        }
    }
}
