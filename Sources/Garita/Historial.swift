import Foundation

/// Un aviso de Garita: lo que se muestra como notificación y queda en el historial.
struct Aviso: Codable, Identifiable {
    var id = UUID()
    var fecha = Date()
    var titulo: String
    var texto: String
    /// Amenazas: la notificación suena y, si no hay permiso para notificar,
    /// se abre la ventana para que no pase desapercibido.
    var importante: Bool
}

/// Guarda los avisos en ~/Library/Application Support/Garita/historial.json
/// (JSON legible, lo más reciente primero).
enum Historial {

    /// Cuántos avisos guardamos como mucho.
    static let maximo = 500

    static var archivo: URL {
        URL.applicationSupportDirectory.appending(path: "Garita/historial.json")
    }

    static func cargar() -> [Aviso] {
        guard let datos = try? Data(contentsOf: archivo) else { return [] }
        let decodificador = JSONDecoder()
        decodificador.dateDecodingStrategy = .iso8601
        return (try? decodificador.decode([Aviso].self, from: datos)) ?? []
    }

    static func guardar(_ avisos: [Aviso]) {
        let codificador = JSONEncoder()
        codificador.dateEncodingStrategy = .iso8601
        codificador.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let datos = try? codificador.encode(Array(avisos.prefix(maximo))) else { return }
        try? FileManager.default.createDirectory(at: archivo.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? datos.write(to: archivo, options: .atomic)
    }
}
