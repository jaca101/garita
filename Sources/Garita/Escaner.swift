import Foundation

/// Un archivo en el que clamscan ha encontrado una amenaza.
struct Deteccion: Identifiable {
    let id = UUID()
    let archivo: URL
    let amenaza: String   // p. ej. "Eicar-Test-Signature"
    /// true cuando ya se ha movido a la cuarentena.
    var aislada = false
}

/// Resultado completo de un escaneo.
struct ResultadoEscaneo {
    var detecciones: [Deteccion] = []
    /// Archivos que clamscan no pudo leer (p. ej. "Access denied"), con el motivo.
    var problemas: [String] = []
    /// Número de archivos analizados, según el resumen de clamscan.
    var archivosAnalizados: Int?
    var duracion: TimeInterval = 0
    var cancelado = false
    /// Si clamscan ni siquiera pudo ejecutarse, el motivo.
    var fallo: String?
}

/// Escanea archivos y carpetas con `clamscan`.
enum Escaner {

    /// Escanea las rutas dadas (archivos o carpetas, recursivamente).
    /// Bloquea hasta que termina: llamarla fuera del hilo principal.
    /// `alArrancar` recibe el PID de clamscan, para poder cancelarlo.
    static func escanear(
        _ rutas: [URL],
        con clamscan: URL,
        alArrancar: @escaping @Sendable (Int32) -> Void
    ) -> ResultadoEscaneo {
        let inicio = Date()

        // -r: entrar en subcarpetas. No usamos --infected porque entonces clamscan
        // no dice qué archivos no pudo leer; filtramos nosotros las líneas "OK".
        let argumentos = ["-r"] + rutas.map(\.path)

        guard let proceso = Proceso.ejecutar(clamscan, argumentos: argumentos, alArrancar: alArrancar) else {
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

            if estado.hasSuffix(" FOUND") {
                let amenaza = String(estado.dropLast(" FOUND".count))
                resultado.detecciones.append(Deteccion(archivo: URL(filePath: ruta), amenaza: amenaza))
            } else if !["OK", "Empty file", "Symbolic link", "Excluded"].contains(estado) {
                resultado.problemas.append("\(URL(filePath: ruta).lastPathComponent): \(estado)")
            }
        }
        return resultado
    }
}
