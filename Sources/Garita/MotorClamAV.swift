import Foundation

/// Fotografía de lo que hay instalado de ClamAV en este Mac.
struct EstadoMotor {
    /// Ruta a `clamscan` (el escáner), o nil si no se encontró.
    var clamscan: URL?
    /// Ruta a `freshclam` (el actualizador de firmas), o nil si no se encontró.
    var freshclam: URL?
    /// Ruta a `brew` (Homebrew), para guiar la instalación de ClamAV si falta.
    var homebrew: URL?
    /// Versión del motor, p. ej. "ClamAV 1.5.4".
    var version: String?
    /// Versión y fecha de la base de firmas (nil si aún no hay firmas).
    var firmas: InfoFirmas?
    /// Dónde debería estar `freshclam.conf` (sin él, freshclam se niega a arrancar).
    var configFreshclam: URL?
    var configExiste = false
    /// Carpeta donde freshclam guarda la base de firmas.
    var carpetaFirmas: URL?
    var hayFirmas = false

    /// Todo lo necesario para poder escanear.
    var listo: Bool {
        clamscan != nil && freshclam != nil && configExiste && hayFirmas
    }

    /// A partir de estos días sin actualizar, consideramos las firmas antiguas.
    static let diasFirmasAntiguas = 3

    /// ¿Faltan firmas o tienen más de `diasFirmasAntiguas` días?
    var firmasAntiguas: Bool {
        guard let firmas else { return true }
        let limite = Date().addingTimeInterval(-Double(Self.diasFirmasAntiguas) * 86_400)
        return firmas.fecha < limite
    }
}

/// Versión y fecha de publicación de las firmas de virus.
struct InfoFirmas {
    var numero: String   // p. ej. "27770"
    var fecha: Date      // cuándo publicó ClamAV esas firmas
}

/// Localiza los binarios de ClamAV y comprueba que estén listos para usar.
///
/// Suponemos una instalación de Homebrew: los binarios están en `<prefijo>/bin`,
/// la configuración en `<prefijo>/etc/clamav` y las firmas en `<prefijo>/var/lib/clamav`,
/// donde `<prefijo>` es `/opt/homebrew` (Apple Silicon) o `/usr/local` (Intel).
enum MotorClamAV {

    /// Carpetas donde buscamos primero. Las apps lanzadas desde el Finder no heredan
    /// el PATH de la terminal, así que no basta con mirar el PATH.
    static let carpetasConocidas = ["/opt/homebrew/bin", "/usr/local/bin"]

    /// Revisa el sistema. Ejecuta `clamscan --version`, así que conviene
    /// llamarla fuera del hilo principal.
    static func detectar() -> EstadoMotor {
        var estado = EstadoMotor()
        estado.clamscan = buscarBinario("clamscan")
        estado.freshclam = buscarBinario("freshclam")
        estado.homebrew = buscarBinario("brew")

        if let clamscan = estado.clamscan,
           let resultado = Proceso.ejecutar(clamscan, argumentos: ["--version"]) {
            (estado.version, estado.firmas) = interpretarVersion(resultado.salida)
        }

        // Carpeta <prefijo> = la carpeta que contiene /bin
        if let freshclam = estado.freshclam {
            let prefijo = freshclam.deletingLastPathComponent().deletingLastPathComponent()

            let config = prefijo.appending(path: "etc/clamav/freshclam.conf")
            estado.configFreshclam = config
            estado.configExiste = FileManager.default.fileExists(atPath: config.path)

            let firmas = prefijo.appending(path: "var/lib/clamav")
            estado.carpetaFirmas = firmas
            estado.hayFirmas = contieneFirmas(firmas)
        }
        return estado
    }

    /// Busca un ejecutable primero en las carpetas conocidas y luego en el PATH.
    static func buscarBinario(_ nombre: String) -> URL? {
        let pathDelEntorno = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map(String.init)

        for carpeta in carpetasConocidas + pathDelEntorno {
            let ruta = URL(filePath: carpeta).appending(path: nombre)
            if FileManager.default.isExecutableFile(atPath: ruta.path) {
                return ruta
            }
        }
        return nil
    }

    /// ¿Hay en la carpeta algún fichero de firmas (.cvd o .cld)?
    static func contieneFirmas(_ carpeta: URL) -> Bool {
        let ficheros = (try? FileManager.default.contentsOfDirectory(atPath: carpeta.path)) ?? []
        return ficheros.contains { $0.hasSuffix(".cvd") || $0.hasSuffix(".cld") }
    }

    /// Interpreta la salida de `clamscan --version`, que tiene una de estas formas:
    ///   "ClamAV 1.5.4"                                   (sin firmas)
    ///   "ClamAV 1.5.4/27770/Tue Sep 22 07:24:12 2026"    (con firmas)
    static func interpretarVersion(_ texto: String) -> (String, InfoFirmas?) {
        let partes = texto.split(separator: "/", maxSplits: 2).map(String.init)
        guard let version = partes.first else { return ("ClamAV (versión desconocida)", nil) }
        guard partes.count == 3 else { return (version, nil) }

        // La fecha usa el formato de C en inglés; los días de una cifra llevan
        // doble espacio ("Sep  2"), así que normalizamos los espacios primero.
        let fechaTexto = partes[2].split(separator: " ").joined(separator: " ")
        let formato = DateFormatter()
        formato.locale = Locale(identifier: "en_US_POSIX")
        formato.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        guard let fecha = formato.date(from: fechaTexto) else { return (version, nil) }

        return (version, InfoFirmas(numero: partes[1], fecha: fecha))
    }
}
