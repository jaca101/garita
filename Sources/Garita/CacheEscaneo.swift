import Foundation

/// Lo que Garita recuerda de un archivo que analizó y salió limpio.
struct EntradaCache: Codable {
    var tamaño: Int64
    var modificado: Date
    var analizado: Date
}

/// Escaneo "solo cambios" de las tareas programadas.
///
/// Garita recuerda, por tarea, cada archivo que analizó y salió limpio (ruta,
/// tamaño, fecha de modificación y cuándo se analizó). En la siguiente ejecución
/// se salta los que no han cambiado y se analizaron hace menos de N días.
///
/// Que un archivo no cambie no significa que siga siendo seguro: ClamAV publica
/// firmas nuevas a diario y puede identificar hoy como virus algo que ayer no
/// conocía. Por eso, cada N días (7 por defecto) se repasa todo.
///
/// Lo que dio amenaza o no se pudo analizar no se recuerda: se mira siempre.
/// Archivo: ~/Library/Application Support/Garita/cache/<id de la tarea>.json
enum CacheEscaneo {

    typealias Registro = [String: EntradaCache]   // ruta → entrada

    static func archivo(_ tarea: UUID) -> URL {
        URL.applicationSupportDirectory.appending(path: "Garita/cache/\(tarea.uuidString).json")
    }

    static func cargar(_ tarea: UUID) -> Registro {
        guard let datos = try? Data(contentsOf: archivo(tarea)) else { return [:] }
        let decodificador = JSONDecoder()
        decodificador.dateDecodingStrategy = .secondsSince1970
        return (try? decodificador.decode(Registro.self, from: datos)) ?? [:]
    }

    static func guardar(_ registro: Registro, tarea: UUID) {
        let codificador = JSONEncoder()
        codificador.dateEncodingStrategy = .secondsSince1970   // compacto: puede haber miles
        guard let datos = try? codificador.encode(registro) else { return }
        try? FileManager.default.createDirectory(at: archivo(tarea).deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? datos.write(to: archivo(tarea), options: .atomic)
    }

    static func borrar(_ tarea: UUID) {
        try? FileManager.default.removeItem(at: archivo(tarea))
    }

    // MARK: - Planificar

    /// Un archivo encontrado en la carpeta, con lo necesario para compararlo.
    struct Encontrado {
        let url: URL
        let tamaño: Int64
        let modificado: Date
    }

    /// Qué hay que analizar esta vez.
    struct Plan {
        /// Nuevos, modificados o que llevan más de N días sin repasarse.
        var aEscanear: [Encontrado] = []
        /// Sin cambios y analizados hace poco: se saltan.
        var saltados = 0
        /// Todas las rutas encontradas (para olvidar las que ya no existen).
        var vistas: Set<String> = []
    }

    /// Recorre la carpeta (y subcarpetas, también dentro de las .app) y decide.
    static func planificar(_ carpeta: URL, registro: Registro, dias: Int, ahora: Date = Date()) -> Plan {
        var plan = Plan()
        let claves: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let recorrido = FileManager.default.enumerator(at: carpeta, includingPropertiesForKeys: claves)
        else { return plan }

        let limite = ahora.addingTimeInterval(-Double(dias) * 86_400)
        for case let url as URL in recorrido {
            guard let v = try? url.resourceValues(forKeys: Set(claves)), v.isRegularFile == true else { continue }
            let encontrado = Encontrado(url: url, tamaño: Int64(v.fileSize ?? 0),
                                        modificado: v.contentModificationDate ?? .distantPast)
            plan.vistas.insert(url.path)
            if let entrada = registro[url.path],
               entrada.tamaño == encontrado.tamaño,
               abs(entrada.modificado.timeIntervalSince(encontrado.modificado)) < 1,
               entrada.analizado > limite {
                plan.saltados += 1
            } else {
                plan.aEscanear.append(encontrado)
            }
        }
        return plan
    }

    // MARK: - Actualizar

    /// Tras el escaneo: recuerda los analizados limpios, olvida los que dieron
    /// amenaza o problema, y los que ya no existen.
    static func actualizar(_ registro: Registro, plan: Plan, resultado: ResultadoEscaneo,
                           ahora: Date = Date()) -> Registro {
        let conAviso = Set(resultado.detecciones.map(\.archivo.path) + resultado.problemas.map(\.archivo.path))
        var nuevo = registro
        for archivo in plan.aEscanear {
            let ruta = archivo.url.path
            if conAviso.contains(ruta) {
                nuevo[ruta] = nil
            } else {
                nuevo[ruta] = EntradaCache(tamaño: archivo.tamaño, modificado: archivo.modificado, analizado: ahora)
            }
        }
        // Olvidamos los que ya no están (borrados, movidos o aislados).
        return nuevo.filter { plan.vistas.contains($0.key) }
    }
}
