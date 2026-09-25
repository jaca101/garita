import Foundation

/// Fotografía del ClamAV que usa Garita.
struct EstadoMotor {
    /// true = el ClamAV que va dentro de Garita.app; false = el de Homebrew.
    var integrado = false
    /// Certificado con el que se verifican las firmas descargadas (solo el integrado).
    var certificados: URL?
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

    /// Opciones para clamscan: con el ClamAV integrado hay que decirle dónde
    /// están sus firmas y su certificado (el de Homebrew ya lo sabe).
    var opcionesClamscan: [String] {
        guard integrado, let carpetaFirmas, let certificados else { return [] }
        return ["--database=\(carpetaFirmas.path)", "--cvdcertsdir=\(certificados.path)"]
    }

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

/// Localiza ClamAV y comprueba que esté listo para usar.
///
/// 1. Primero, el ClamAV integrado en Garita.app (ver preparar-clamav.sh):
///      programas en Contents/Helpers, librerías en Contents/Frameworks,
///      certificado en Contents/Resources/clamav/certs.
///    Sus firmas y su configuración van en ~/Library/Application Support/Garita/clamav/.
/// 2. Si no lo hay (p. ej. compilación de desarrollo sin él), el de Homebrew:
///      binarios en <prefijo>/bin, configuración en <prefijo>/etc/clamav y firmas
///      en <prefijo>/var/lib/clamav (<prefijo> = /opt/homebrew o /usr/local).
enum MotorClamAV {

    /// Carpeta de datos del ClamAV integrado: firmas y freshclam.conf.
    static var carpetaDatos: URL {
        URL.applicationSupportDirectory.appending(path: "Garita/clamav")
    }

    /// Carpetas donde buscamos primero. Las apps lanzadas desde el Finder no heredan
    /// el PATH de la terminal, así que no basta con mirar el PATH.
    static let carpetasConocidas = ["/opt/homebrew/bin", "/usr/local/bin"]

    /// Revisa el sistema. Ejecuta `clamscan --version`, así que conviene
    /// llamarla fuera del hilo principal.
    static func detectar() -> EstadoMotor {
        var estado = EstadoMotor()
        let fm = FileManager.default
        let ayudantes = Bundle.main.bundleURL.appending(path: "Contents/Helpers")

        if fm.isExecutableFile(atPath: ayudantes.appending(path: "clamscan").path),
           fm.isExecutableFile(atPath: ayudantes.appending(path: "freshclam").path) {
            // ClamAV integrado.
            estado.integrado = true
            estado.clamscan = ayudantes.appending(path: "clamscan")
            estado.freshclam = ayudantes.appending(path: "freshclam")
            estado.certificados = Bundle.main.resourceURL?.appending(path: "clamav/certs")
            estado.configFreshclam = carpetaDatos.appending(path: "freshclam.conf")
            estado.configExiste = fm.fileExists(atPath: estado.configFreshclam!.path)
            estado.carpetaFirmas = carpetaDatos.appending(path: "firmas")
            estado.hayFirmas = contieneFirmas(estado.carpetaFirmas!)
        } else {
            // ClamAV de Homebrew.
            estado.clamscan = buscarBinario("clamscan")
            estado.freshclam = buscarBinario("freshclam")
        }
        estado.homebrew = buscarBinario("brew")

        if let clamscan = estado.clamscan,
           let resultado = Proceso.ejecutar(clamscan, argumentos: ["--version"]) {
            (estado.version, estado.firmas) = interpretarVersion(resultado.salida)
        }

        // Carpeta <prefijo> de Homebrew = la carpeta que contiene /bin
        if !estado.integrado, let freshclam = estado.freshclam {
            let prefijo = freshclam.deletingLastPathComponent().deletingLastPathComponent()

            let config = prefijo.appending(path: "etc/clamav/freshclam.conf")
            estado.configFreshclam = config
            estado.configExiste = FileManager.default.fileExists(atPath: config.path)

            let firmas = prefijo.appending(path: "var/lib/clamav")
            estado.carpetaFirmas = firmas
            estado.hayFirmas = contieneFirmas(firmas)
        }

        // Versión y fecha de las firmas: de la cabecera del archivo "daily".
        if let carpeta = estado.carpetaFirmas, let cabecera = leerCabeceraFirmas(carpeta) {
            estado.firmas = cabecera
        }
        return estado
    }

    /// Carpeta de firmas de Homebrew en este Mac, si existe y tiene firmas
    /// (para no descargarlas otra vez la primera vez que se usa el integrado).
    static var firmasDeHomebrew: URL? {
        ["/opt/homebrew/var/lib/clamav", "/usr/local/var/lib/clamav"]
            .map { URL(filePath: $0) }
            .first { contieneFirmas($0) }
    }

    /// Lee la cabecera de daily.cld o daily.cvd: 512 bytes de texto separados
    /// por ":", p. ej. "ClamAV-VDB:24 Sep 2026 06-24 +0000:28133:355677:90:…:1790231059".
    /// El tercer campo es la versión y el noveno la fecha (segundos desde 1970).
    static func leerCabeceraFirmas(_ carpeta: URL) -> InfoFirmas? {
        for nombre in ["daily.cld", "daily.cvd"] {
            guard let archivo = try? FileHandle(forReadingFrom: carpeta.appending(path: nombre)) else { continue }
            defer { try? archivo.close() }
            guard let datos = try? archivo.read(upToCount: 512) else { continue }
            let campos = String(decoding: datos, as: UTF8.self).split(separator: ":", omittingEmptySubsequences: false)
            guard campos.count >= 9, campos[0] == "ClamAV-VDB",
                  let segundos = TimeInterval(campos[8].trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)))
            else { continue }
            return InfoFirmas(numero: String(campos[2]), fecha: Date(timeIntervalSince1970: segundos))
        }
        return nil
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
