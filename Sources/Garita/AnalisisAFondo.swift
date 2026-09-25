import Foundation

/// Análisis a fondo de lo que clamscan no pudo analizar entero por sus límites
/// (archivos de más de 2 GB, comprimidos enormes…).
///
/// ClamAV ya abre por dentro zip, tar.gz, dmg, pkg… Este paso solo actúa cuando
/// se ha topado con un límite. Entonces Garita abre el archivo por su cuenta y
/// escanea su contenido como una carpeta normal:
///   - DMG / ISO:   se monta solo lectura y oculta (hdiutil), se escanea y se
///                  desmonta. No ocupa espacio en disco.
///   - ZIP, TAR…:   se descomprime (bsdtar) en una carpeta temporal, si hay
///                  espacio suficiente con margen; se escanea y se borra.
///   - PKG:         se expande (pkgutil) en la carpeta temporal; igual.
/// Las amenazas encontradas dentro se atribuyen al archivo original (que es el
/// que se aísla).
enum AnalisisAFondo {

    /// Carpeta temporal: ~/Library/Caches/Garita/a-fondo (se vacía al terminar
    /// cada archivo y al arrancar Garita, por si quedó algo de una ejecución cortada).
    static var carpetaTemporal: URL {
        URL.cachesDirectory.appending(path: "Garita/a-fondo")
    }

    /// Espacio libre que dejamos siempre, además de lo que ocupe lo descomprimido.
    static let margenDisco: Int64 = 5 * 1_000_000_000

    /// Borra lo que haya quedado de análisis anteriores.
    static func limpiarRestos() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: carpetaTemporal.path) else { return }
        // Primero desmontamos imágenes que se quedaran montadas ahí.
        for punto in (try? fm.contentsOfDirectory(atPath: carpetaTemporal.path)) ?? [] {
            _ = Proceso.ejecutar(URL(filePath: "/usr/bin/hdiutil"),
                                 argumentos: ["detach", carpetaTemporal.appending(path: punto).path, "-force"])
        }
        borrar(carpetaTemporal)
    }

    // MARK: - Qué se puede abrir y cómo

    enum Tipo { case imagenDisco, comprimido, paquete }

    static func tipo(de archivo: URL) -> Tipo? {
        let nombre = archivo.lastPathComponent.lowercased()
        let ext = archivo.pathExtension.lowercased()
        if ["dmg", "iso", "sparseimage", "cdr"].contains(ext) { return .imagenDisco }
        if ["pkg", "mpkg"].contains(ext) { return .paquete }
        if ["zip", "tar", "tgz", "tbz", "tbz2", "txz", "7z", "rar", "xar", "cpio", "jar"].contains(ext)
            || [".tar.gz", ".tar.bz2", ".tar.xz"].contains(where: nombre.hasSuffix) {
            return .comprimido
        }
        return nil
    }

    // MARK: - Completar un escaneo

    /// Revisa los problemas por límite de un resultado, analiza a fondo los que
    /// se pueda y devuelve el resultado completado. Bloquea: fuera del hilo principal.
    static func completar(
        _ resultado: ResultadoEscaneo,
        programa: Programa,
        alternativa: Programa?,
        prioridadBaja: Bool,
        alArrancar: @escaping @Sendable (Int32) -> Void,
        alAvanzar: @escaping @Sendable (Int, String) -> Void
    ) -> ResultadoEscaneo {
        var completado = resultado
        let candidatos = resultado.problemas.filter { $0.porLimite && tipo(de: $0.archivo) != nil }
        guard !resultado.cancelado, resultado.fallo == nil, !candidatos.isEmpty else { return resultado }

        for problema in candidatos {
            alAvanzar(resultado.archivosAnalizados ?? 0, "A fondo: \(problema.archivo.lastPathComponent)")
            let salida = analizar(problema.archivo, programa: programa, alternativa: alternativa,
                                  prioridadBaja: prioridadBaja, alArrancar: alArrancar)
            completado.problemas.removeAll { $0 == problema }
            switch salida {
            case .limpio:
                break   // resuelto: ya no es un problema
            case .amenazas(let encontradas):
                // Una sola detección por archivo original (es el que se aísla entero).
                var texto = encontradas.prefix(3).map { "\($0.firma) dentro de \($0.interna)" }
                    .joined(separator: "; ")
                if encontradas.count > 3 { texto += " y \(encontradas.count - 3) más" }
                completado.detecciones.append(Deteccion(archivo: problema.archivo, amenaza: texto))
            case .noSePudo(let motivo):
                completado.problemas.append(Problema(archivo: problema.archivo, motivo: motivo))
            case .cancelado:
                completado.cancelado = true
                return completado
            }
        }
        return completado
    }

    // MARK: - Un archivo

    enum Salida {
        case limpio
        case amenazas([(firma: String, interna: String)])
        case noSePudo(String)
        case cancelado
    }

    static func analizar(
        _ archivo: URL, programa: Programa, alternativa: Programa?, prioridadBaja: Bool,
        alArrancar: @escaping @Sendable (Int32) -> Void
    ) -> Salida {
        guard let tipo = tipo(de: archivo) else { return .noSePudo("formato que Garita no sabe abrir") }
        let destino = carpetaTemporal.appending(path: UUID().uuidString)
        try? FileManager.default.createDirectory(at: destino, withIntermediateDirectories: true)
        defer { borrar(destino) }

        switch tipo {
        case .imagenDisco:
            // ¿Cifrada? Entonces no se puede montar sin contraseña.
            if let r = Proceso.ejecutar(URL(filePath: "/usr/bin/hdiutil"), argumentos: ["isencrypted", archivo.path]),
               r.salida.contains("encrypted: YES") {
                return .noSePudo("imagen de disco cifrada: no se puede analizar sin contraseña")
            }
            guard let montaje = Proceso.ejecutar(
                URL(filePath: "/usr/bin/hdiutil"),
                argumentos: ["attach", "-readonly", "-nobrowse", "-noautoopen", "-noverify",
                             "-mountpoint", destino.path, archivo.path],
                prioridadBaja: prioridadBaja), montaje.codigo == 0
            else { return .noSePudo("no se pudo montar la imagen de disco") }
            // Pase lo que pase, la desmontamos.
            defer {
                _ = Proceso.ejecutar(URL(filePath: "/usr/bin/hdiutil"), argumentos: ["detach", destino.path, "-force"])
            }
            return escanear(destino, original: archivo, programa: programa, alternativa: alternativa,
                            prioridadBaja: prioridadBaja, alArrancar: alArrancar)

        case .comprimido:
            guard let necesario = tamañoDescomprimido(archivo) else {
                return .noSePudo("no se pudo leer el contenido del comprimido (¿protegido con contraseña o dañado?)")
            }
            if let motivo = faltaEspacio(necesario) { return .noSePudo(motivo) }
            guard let r = Proceso.ejecutar(URL(filePath: "/usr/bin/bsdtar"),
                                           argumentos: ["-xf", archivo.path, "-C", destino.path],
                                           prioridadBaja: prioridadBaja), r.codigo == 0
            else { return .noSePudo("no se pudo descomprimir (¿protegido con contraseña o dañado?)") }
            return escanear(destino, original: archivo, programa: programa, alternativa: alternativa,
                            prioridadBaja: prioridadBaja, alArrancar: alArrancar)

        case .paquete:
            // No sabemos cuánto ocupa expandido sin expandirlo: calculamos 5 veces su tamaño.
            let tamaño = (try? FileManager.default.attributesOfItem(atPath: archivo.path)[.size] as? Int64) ?? 0
            if let motivo = faltaEspacio(tamaño * 5) { return .noSePudo(motivo) }
            let expandido = destino.appending(path: "pkg")
            guard let r = Proceso.ejecutar(URL(filePath: "/usr/sbin/pkgutil"),
                                           argumentos: ["--expand-full", archivo.path, expandido.path],
                                           prioridadBaja: prioridadBaja), r.codigo == 0
            else { return .noSePudo("no se pudo expandir el paquete") }
            return escanear(expandido, original: archivo, programa: programa, alternativa: alternativa,
                            prioridadBaja: prioridadBaja, alArrancar: alArrancar)
        }
    }

    /// Escanea la carpeta con el contenido y traduce el resultado.
    private static func escanear(
        _ carpeta: URL, original: URL, programa: Programa, alternativa: Programa?, prioridadBaja: Bool,
        alArrancar: @escaping @Sendable (Int32) -> Void
    ) -> Salida {
        let r = Escaner.escanear([carpeta], con: programa, alternativa: alternativa,
                                 prioridadBaja: prioridadBaja, alArrancar: alArrancar)
        if r.fallo != nil && r.archivosAnalizados == nil { return .cancelado }
        if r.detecciones.isEmpty {
            // Lo que siga sin poder analizarse dentro se indica, pero no bloquea.
            return r.problemas.isEmpty ? .limpio
                : .noSePudo("analizado a fondo, salvo \(r.problemas.count) archivo(s) interno(s)")
        }
        let prefijo = carpeta.path + "/"
        return .amenazas(r.detecciones.map { d in
            (firma: d.amenaza, interna: d.archivo.path.replacingOccurrences(of: prefijo, with: ""))
        })
    }

    // MARK: - Espacio

    /// Suma de los tamaños que lista bsdtar (no descomprime a disco; solo lee).
    /// Formato de cada línea, como "ls -l": permisos, enlaces, dueño, grupo, TAMAÑO, fecha, nombre.
    private static func tamañoDescomprimido(_ archivo: URL) -> Int64? {
        guard let r = Proceso.ejecutar(URL(filePath: "/usr/bin/bsdtar"), argumentos: ["-tvf", archivo.path]),
              r.codigo == 0 else { return nil }
        return r.salida.split(separator: "\n").reduce(Int64(0)) { total, linea in
            let campos = linea.split(separator: " ", omittingEmptySubsequences: true)
            return total + (campos.count > 4 ? Int64(campos[4]) ?? 0 : 0)
        }
    }

    /// nil si hay espacio suficiente (lo necesario + el margen); si no, el motivo.
    private static func faltaEspacio(_ necesario: Int64) -> String? {
        let valores = try? URL.homeDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let libre = valores?.volumeAvailableCapacityForImportantUsage ?? 0
        guard libre < necesario + margenDisco else { return nil }
        let gb = { (b: Int64) in String(format: "%.1f GB", Double(b) / 1_000_000_000) }
        return "sin espacio para analizar a fondo: necesita \(gb(necesario)) + 5 GB de margen y hay \(gb(libre)) libres"
    }

    /// Borra una carpeta temporal (aunque lo extraído venga sin permiso de escritura).
    private static func borrar(_ carpeta: URL) {
        _ = Proceso.ejecutar(URL(filePath: "/bin/chmod"), argumentos: ["-R", "u+rwx", carpeta.path])
        try? FileManager.default.removeItem(at: carpeta)
    }
}
