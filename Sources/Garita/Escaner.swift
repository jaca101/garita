import Foundation

/// Un archivo en el que clamscan ha encontrado una amenaza.
struct Deteccion: Identifiable {
    let id = UUID()
    let archivo: URL
    let amenaza: String   // p. ej. "Eicar-Test-Signature"
    /// true cuando ya se ha movido a la cuarentena.
    var aislada = false
}

/// Un archivo que no se pudo analizar (o no del todo), con el motivo.
struct Problema: Hashable {
    let archivo: URL
    let motivo: String    // p. ej. "Access denied" o "no analizado: demasiado grande"

    /// "archivo.zip: Access denied"
    var descripcion: String { "\(archivo.lastPathComponent): \(motivo)" }
}

/// Resultado completo de un escaneo.
struct ResultadoEscaneo {
    var detecciones: [Deteccion] = []
    /// Archivos que clamscan no pudo leer o no analizó enteros.
    var problemas: [Problema] = []
    /// Número de archivos analizados, según el resumen de clamscan.
    var archivosAnalizados: Int?
    var duracion: TimeInterval = 0
    var cancelado = false
    /// Si clamscan ni siquiera pudo ejecutarse, el motivo.
    var fallo: String?
}

/// Escanea archivos y carpetas con `clamscan`.
enum Escaner {

    /// Límites de tamaño. Por defecto clamscan se salta SIN AVISAR los archivos de
    /// más de 100 MB; los subimos a 2 GB y le pedimos que avise de lo que se salte
    /// (sale como "Heuristics.Limits.Exceeded… FOUND", que tratamos como problema).
    static let opcionesLimites = [
        "--max-filesize=2000M",
        "--max-scansize=2000M",
        "--alert-exceeds-max=yes",
    ]

    /// Escanea las rutas dadas (archivos o carpetas, recursivamente).
    /// Bloquea hasta que termina: llamarla fuera del hilo principal.
    /// `alArrancar` recibe el PID de clamscan, para poder cancelarlo.
    ///
    /// `alAvanzar` recibe, como mucho 4 veces por segundo, cuántos archivos van
    /// analizados y el nombre del último (clamscan escribe una línea por archivo
    /// al terminarlo).
    static func escanear(
        _ rutas: [URL],
        con clamscan: URL,
        opciones: [String] = [],
        prioridadBaja: Bool = false,
        alArrancar: @escaping @Sendable (Int32) -> Void,
        alAvanzar: @escaping @Sendable (_ archivos: Int, _ ultimo: String) -> Void = { _, _ in }
    ) -> ResultadoEscaneo {
        let inicio = Date()
        var analizados = 0
        var ultimoAviso = Date.distantPast
        var enResumen = false

        // -r: entrar en subcarpetas. No usamos --infected porque entonces clamscan
        // no dice qué archivos no pudo leer; filtramos nosotros las líneas "OK".
        let argumentos = ["-r"] + opcionesLimites + opciones + rutas.map(\.path)

        guard let proceso = Proceso.ejecutar(
            clamscan, argumentos: argumentos, prioridadBaja: prioridadBaja, alArrancar: alArrancar,
            alRecibirLinea: { linea in
                // Cada línea "/ruta/archivo: estado" es un archivo terminado.
                if linea.hasPrefix("----------- SCAN SUMMARY") { enResumen = true }
                guard !enResumen, !linea.hasPrefix("LibClamAV"),
                      let separador = linea.range(of: ": ", options: .backwards) else { return }
                analizados += 1
                // Para no saturar la interfaz, avisamos como mucho cada 0,25 s.
                if Date().timeIntervalSince(ultimoAviso) > 0.25 {
                    ultimoAviso = Date()
                    alAvanzar(analizados, URL(filePath: String(linea[..<separador.lowerBound])).lastPathComponent)
                }
            }) else {
            return ResultadoEscaneo(fallo: "No se pudo ejecutar clamscan.")
        }

        var resultado = interpretar(proceso.salida)
        resultado.duracion = Date().timeIntervalSince(inicio)

        // Códigos de clamscan: 0 = limpio, 1 = amenazas, 2 = hubo errores.
        // Si hay otro código y no sacamos nada en claro, lo mostramos tal cual.
        if proceso.codigo > 2 && resultado.archivosAnalizados == nil {
            resultado.fallo = "clamscan terminó con código \(proceso.codigo)."
        }
        return resultado
    }

    /// Interpreta la salida de clamscan línea a línea. Formato de cada línea:
    ///   /ruta/archivo: OK
    ///   /ruta/archivo: Eicar-Test-Signature FOUND
    ///   /ruta/archivo: Access denied
    /// y al final un resumen con líneas como "Scanned files: 2".
    static func interpretar(_ salida: String) -> ResultadoEscaneo {
        var resultado = ResultadoEscaneo()
        var enResumen = false

        for linea in salida.split(separator: "\n").map(String.init) {
            if linea.hasPrefix("----------- SCAN SUMMARY") {
                enResumen = true
                continue
            }
            if enResumen {
                if linea.hasPrefix("Scanned files:") {
                    resultado.archivosAnalizados = Int(linea.dropFirst("Scanned files:".count)
                        .trimmingCharacters(in: .whitespaces))
                }
                continue
            }
            // Avisos internos del motor: no son de ningún archivo concreto.
            if linea.hasPrefix("LibClamAV") { continue }

            // Separamos por el ÚLTIMO ": ", porque el nombre del archivo
            // también podría contener ": ".
            guard let separador = linea.range(of: ": ", options: .backwards) else { continue }
            let ruta = String(linea[..<separador.lowerBound])
            let estado = String(linea[separador.upperBound...])

            let archivo = URL(filePath: ruta)
            if estado.hasSuffix(" FOUND") {
                let amenaza = String(estado.dropLast(" FOUND".count))
                if amenaza.hasPrefix("Heuristics.Limits.Exceeded") {
                    // No es un virus: el archivo supera los límites y no se analizó entero.
                    resultado.problemas.append(Problema(archivo: archivo, motivo: motivoLimite(amenaza)))
                } else {
                    resultado.detecciones.append(Deteccion(archivo: archivo, amenaza: amenaza))
                }
            } else if estado.contains("Virus(es) detected") {
                // Línea extra que clamscan añade tras un aviso de límites: ya contada.
                continue
            } else if !["OK", "Empty file", "Symbolic link", "Excluded"].contains(estado) {
                resultado.problemas.append(Problema(archivo: archivo, motivo: estado))
            }
        }
        return resultado
    }

    /// Traduce el aviso de límites de clamscan a algo legible.
    private static func motivoLimite(_ aviso: String) -> String {
        if aviso.hasSuffix("MaxFileSize") { return "no analizado: más de 2 GB" }
        if aviso.hasSuffix("MaxScanSize") { return "analizado solo en parte: más de 2 GB descomprimido" }
        return "analizado solo en parte: límite de ClamAV (\(aviso))"
    }
}
