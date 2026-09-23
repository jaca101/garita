import Foundation

/// Ficha de un archivo en cuarentena. Se guarda como JSON legible junto al archivo.
struct ElementoCuarentena: Codable, Identifiable {
    var id: UUID
    var nombreOriginal: String
    var rutaOriginal: String
    var amenaza: String
    var fecha: Date
    /// Permisos que tenía antes de aislarlo, en octal como en la Terminal
    /// (p. ej. "644"), para restaurarlos.
    var permisosOriginales: String
}

/// Aísla archivos infectados sin borrarlos.
///
/// Carpeta: ~/Library/Application Support/Garita/Cuarentena (permisos 700).
/// Por cada archivo aislado hay dos entradas:
///   <id>        el archivo, renombrado sin extensión y con permisos 000
///   <id>.json   su ficha (ElementoCuarentena)
enum Cuarentena {

    static var carpeta: URL {
        URL.applicationSupportDirectory.appending(path: "Garita/Cuarentena")
    }

    private static func archivo(_ id: UUID) -> URL { carpeta.appending(path: id.uuidString) }
    private static func ficha(_ id: UUID) -> URL { carpeta.appending(path: id.uuidString + ".json") }

    /// Mueve un archivo a la cuarentena y le quita todos los permisos.
    static func aislar(_ original: URL, amenaza: String) throws -> ElementoCuarentena {
        let fm = FileManager.default
        try fm.createDirectory(at: carpeta, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: carpeta.path)

        let permisos = try fm.attributesOfItem(atPath: original.path)[.posixPermissions] as? Int ?? 0o644
        let elemento = ElementoCuarentena(
            id: UUID(),
            nombreOriginal: original.lastPathComponent,
            rutaOriginal: original.path,
            amenaza: amenaza,
            fecha: Date(),
            permisosOriginales: String(permisos, radix: 8))

        // Primero la ficha: si algo falla después, no queda un archivo "huérfano"
        // en la cuarentena sin saber de dónde vino.
        try codificador.encode(elemento).write(to: ficha(elemento.id))
        do {
            try fm.moveItem(at: original, to: archivo(elemento.id))
        } catch {
            try? fm.removeItem(at: ficha(elemento.id))
            throw error
        }
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: archivo(elemento.id).path)
        return elemento
    }

    /// Lista lo que hay en cuarentena, lo más reciente primero.
    static func listar() -> [ElementoCuarentena] {
        let fm = FileManager.default
        let nombres = (try? fm.contentsOfDirectory(atPath: carpeta.path)) ?? []
        return nombres
            .filter { $0.hasSuffix(".json") }
            .compactMap { try? decodificador.decode(ElementoCuarentena.self, from: Data(contentsOf: carpeta.appending(path: $0))) }
            .filter { fm.fileExists(atPath: archivo($0.id).path) }
            .sorted { $0.fecha > $1.fecha }
    }

    /// Devuelve el archivo a su ubicación original (o a una cercana si ya
    /// existe otro con ese nombre) con sus permisos originales.
    /// Devuelve la ruta donde ha quedado.
    static func restaurar(_ elemento: ElementoCuarentena) throws -> URL {
        let fm = FileManager.default
        let destino = rutaLibre(para: URL(filePath: elemento.rutaOriginal))
        try fm.createDirectory(at: destino.deletingLastPathComponent(), withIntermediateDirectories: true)

        try fm.moveItem(at: archivo(elemento.id), to: destino)
        let permisos = Int(elemento.permisosOriginales, radix: 8) ?? 0o644
        try fm.setAttributes([.posixPermissions: permisos], ofItemAtPath: destino.path)
        try? fm.removeItem(at: ficha(elemento.id))
        return destino
    }

    /// Borra definitivamente el archivo y su ficha.
    static func eliminar(_ elemento: ElementoCuarentena) throws {
        try FileManager.default.removeItem(at: archivo(elemento.id))
        try? FileManager.default.removeItem(at: ficha(elemento.id))
    }

    /// Si `ruta` ya existe, busca "nombre (restaurado).ext", "nombre (restaurado 2).ext"…
    private static func rutaLibre(para ruta: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: ruta.path) else { return ruta }

        let carpeta = ruta.deletingLastPathComponent()
        let base = ruta.deletingPathExtension().lastPathComponent
        let ext = ruta.pathExtension.isEmpty ? "" : "." + ruta.pathExtension
        var n = 1
        while true {
            let sufijo = n == 1 ? " (restaurado)" : " (restaurado \(n))"
            let candidata = carpeta.appending(path: base + sufijo + ext)
            if !fm.fileExists(atPath: candidata.path) { return candidata }
            n += 1
        }
    }

    // JSON legible: fechas ISO 8601, con sangría y sin escapar las "/".
    private static var codificador: JSONEncoder {
        let c = JSONEncoder()
        c.dateEncodingStrategy = .iso8601
        c.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return c
    }
    private static var decodificador: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
