import CryptoKit
import Foundation

/// Un archivo que el usuario ha marcado como seguro (falso positivo).
/// Se identifica por su huella SHA-256: si el archivo cambia, deja de coincidir.
struct ArchivoSeguro: Codable, Identifiable {
    var id = UUID()
    var sha256: String
    var nombre: String
    var ruta: String
    /// Lo que dijo ClamAV cuando se marcó (p. ej. "Win.Packed.Mikey-9859574-0").
    var amenaza: String
    var fecha = Date()
}

/// Lista de archivos seguros, en ~/Library/Application Support/Garita/seguros.json.
enum Seguros {

    static var archivo: URL {
        URL.applicationSupportDirectory.appending(path: "Garita/seguros.json")
    }

    static func cargar() -> [ArchivoSeguro] {
        guard let datos = try? Data(contentsOf: archivo) else { return [] }
        let decodificador = JSONDecoder()
        decodificador.dateDecodingStrategy = .iso8601
        return (try? decodificador.decode([ArchivoSeguro].self, from: datos)) ?? []
    }

    static func guardar(_ lista: [ArchivoSeguro]) {
        let codificador = JSONEncoder()
        codificador.dateEncodingStrategy = .iso8601
        codificador.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let datos = try? codificador.encode(lista) else { return }
        try? FileManager.default.createDirectory(at: archivo.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? datos.write(to: archivo, options: .atomic)
    }

    /// Huella SHA-256 de un archivo, leyéndolo por bloques de 1 MB (vale para
    /// archivos de varios GB sin cargarlos en memoria). nil si no se puede leer.
    static func sha256(_ url: URL) -> String? {
        guard let lector = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? lector.close() }
        var huella = SHA256()
        while let bloque = try? lector.read(upToCount: 1 << 20), !bloque.isEmpty {
            huella.update(data: bloque)
        }
        return huella.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Quita del resultado las detecciones de archivos marcados como seguros,
    /// y también sus avisos de "sin analizar" (p. ej. por tardar demasiado).
    /// Solo calcula la huella de los detectados (suelen ser muy pocos) y de los
    /// "sin analizar" cuya ruta coincide con la de algún seguro.
    static func filtrar(_ resultado: ResultadoEscaneo, huellas: Set<String>,
                        rutas: Set<String> = []) -> ResultadoEscaneo {
        guard !huellas.isEmpty else { return resultado }
        var filtrado = resultado
        filtrado.detecciones.removeAll { deteccion in
            guard let huella = sha256(deteccion.archivo) else { return false }
            return huellas.contains(huella)
        }
        filtrado.problemas.removeAll { problema in
            guard rutas.contains(problema.archivo.path), let huella = sha256(problema.archivo) else { return false }
            return huellas.contains(huella)
        }
        return filtrado
    }
}
