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
    /// Cómo está codificado el contenido en la cuarentena (ver `Cuarentena.codificar`).
    /// Opcional para poder leer fichas antiguas, que no lo tenían (= sin codificar).
    var codificacion: String?
}

/// Aísla archivos infectados sin borrarlos.
///
/// Carpeta: ~/Library/Application Support/Garita/Cuarentena (permisos 700).
/// Por cada archivo aislado hay dos entradas:
///   <id>        el archivo, renombrado sin extensión, con permisos 000 y con su
///               contenido codificado con XOR (así otros antivirus no lo detectan
///               ni se lo llevan, y aunque alguien lo ejecutara no funcionaría)
///   <id>.json   su ficha (ElementoCuarentena)
///
/// Para recuperar un archivo a mano sin Garita, basta con aplicar de nuevo XOR
/// con la misma clave a cada byte, p. ej. en la Terminal:
///   chmod 600 <id> && python3 -c "import sys; d=open(sys.argv[1],'rb').read(); \
///     open(sys.argv[2],'wb').write(bytes(b ^ 0xA5 for b in d))" <id> recuperado
enum Cuarentena {

    /// Clave XOR: cada byte del archivo se combina con este valor.
    /// Aplicarla dos veces deja el byte como estaba (a ^ k ^ k == a).
    static let claveXOR: UInt8 = 0xA5
    static let nombreCodificacion = "XOR 0xA5"

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
            permisosOriginales: String(permisos, radix: 8),
            codificacion: nombreCodificacion)

        // Primero la ficha: si algo falla después, no queda un archivo "huérfano"
        // en la cuarentena sin saber de dónde vino.
        try codificador.encode(elemento).write(to: ficha(elemento.id))
        do {
            try fm.moveItem(at: original, to: archivo(elemento.id))
        } catch {
            try? fm.removeItem(at: ficha(elemento.id))
            throw error
        }
        // Ya dentro de la cuarentena: codificamos y quitamos todos los permisos.
        let aislado = archivo(elemento.id)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: aislado.path)
        try codificar(aislado)
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: aislado.path)
        return elemento
    }

    /// Lista lo que hay en cuarentena, lo más reciente primero.
    ///
    /// Si una ficha se ha quedado sin su archivo (porque alguien lo borró o se lo
    /// llevó otro antivirus), la ficha ya no sirve para nada y se borra.
    static func listar() -> [ElementoCuarentena] {
        let fm = FileManager.default
        let nombres = (try? fm.contentsOfDirectory(atPath: carpeta.path)) ?? []
        var elementos: [ElementoCuarentena] = []

        for nombre in nombres where nombre.hasSuffix(".json") {
            guard let datos = try? Data(contentsOf: carpeta.appending(path: nombre)),
                  let elemento = try? decodificador.decode(ElementoCuarentena.self, from: datos)
            else { continue }   // un .json que no es nuestro: lo dejamos en paz

            if fm.fileExists(atPath: archivo(elemento.id).path) {
                elementos.append(elemento)
            } else {
                try? fm.removeItem(at: ficha(elemento.id))
            }
        }
        return elementos.sorted { $0.fecha > $1.fecha }
    }

    /// Devuelve el archivo a su ubicación original (o a una cercana si ya
    /// existe otro con ese nombre) con sus permisos originales.
    /// Devuelve la ruta donde ha quedado.
    static func restaurar(_ elemento: ElementoCuarentena) throws -> URL {
        let fm = FileManager.default
        let aislado = archivo(elemento.id)

        // Primero lo descodificamos dentro de la cuarentena (si estaba codificado).
        if elemento.codificacion == nombreCodificacion {
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: aislado.path)
            try codificar(aislado)
        }

        let destino = rutaLibre(para: URL(filePath: elemento.rutaOriginal))
        try fm.createDirectory(at: destino.deletingLastPathComponent(), withIntermediateDirectories: true)

        try fm.moveItem(at: aislado, to: destino)
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

    /// Aplica XOR con `claveXOR` a cada byte del archivo, sobre el propio archivo.
    /// Sirve tanto para codificar como para descodificar (es la misma operación).
    /// Va por bloques de 1 MB para no cargar en memoria archivos grandes.
    static func codificar(_ url: URL) throws {
        let archivo = try FileHandle(forUpdating: url)
        defer { try? archivo.close() }

        var posicion: UInt64 = 0
        while let bloque = try archivo.read(upToCount: 1 << 20), !bloque.isEmpty {
            let codificado = Data(bloque.map { $0 ^ claveXOR })
            try archivo.seek(toOffset: posicion)
            try archivo.write(contentsOf: codificado)
            posicion += UInt64(bloque.count)
        }
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
