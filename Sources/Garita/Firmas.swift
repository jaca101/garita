import Foundation

/// Actualiza la base de firmas de virus con `freshclam`.
enum Firmas {

    /// Crea `freshclam.conf` a partir del ejemplo que instala Homebrew
    /// (`freshclam.conf.sample`). El ejemplo trae una línea `Example` que hace que
    /// freshclam se niegue a arrancar; la comentamos y dejamos el resto tal cual.
    static func crearConfig(en config: URL) throws {
        let ejemplo = URL(filePath: config.path + ".sample")
        let texto = try String(contentsOf: ejemplo, encoding: .utf8)

        let lineas = texto.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasPrefix("Example") ? "#" + $0 : String($0) }

        try lineas.joined(separator: "\n").write(to: config, atomically: true, encoding: .utf8)
    }

    /// Ejecuta freshclam y devuelve un mensaje para mostrar al usuario.
    /// Puede tardar varios minutos la primera vez (descarga unos 200 MB).
    /// Bloquea: llamarla fuera del hilo principal.
    static func actualizar(motor: EstadoMotor) -> (ok: Bool, mensaje: String) {
        guard let freshclam = motor.freshclam, let config = motor.configFreshclam else {
            return (false, "No se encontró freshclam.")
        }

        if !motor.configExiste {
            do {
                try crearConfig(en: config)
            } catch {
                return (false, "No se pudo crear \(config.path): \(error.localizedDescription)")
            }
        }

        guard let resultado = Proceso.ejecutar(freshclam, argumentos: []) else {
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
