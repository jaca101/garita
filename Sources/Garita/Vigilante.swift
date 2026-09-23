import CoreServices
import Foundation

/// Observa carpetas y avisa de los archivos nuevos, ya terminados de escribir.
///
/// Usa FSEvents, el sistema de macOS que notifica cambios en el disco. Solo
/// entrega archivos que:
///   - han aparecido (creados, renombrados o modificados) después de arrancar,
///   - no son ocultos ni temporales de descarga (.crdownload, .part…),
///   - llevan un rato sin cambiar de tamaño (la descarga ha terminado).
/// Varios archivos que llegan seguidos se entregan juntos, en un solo lote,
/// para escanearlos con una sola ejecución de clamscan.
@MainActor
final class Vigilante {

    /// Espera tras el último cambio antes de revisar los archivos pendientes.
    static let espera: Duration = .seconds(5)
    /// Intervalo para comprobar que el tamaño ya no cambia.
    static let pausaEstabilidad: Duration = .seconds(2)

    /// Extensiones de archivos a medio descargar (navegadores y gestores de descargas).
    static let extensionesTemporales: Set<String> = [
        "crdownload",   // Chrome, Edge, Brave
        "download",     // Safari (en realidad es una carpeta)
        "part",         // Firefox, aMule, otros
        "partial",      // varios
        "opdownload",   // Opera
        "tmp", "temp",
    ]

    /// Recibe cada lote de archivos nuevos y estables.
    private let alLlegar: ([URL]) -> Void
    private var flujo: FSEventStreamRef?
    /// Archivos vistos, a la espera de que se estabilicen.
    private var pendientes: Set<URL> = []
    private var temporizador: Task<Void, Never>?
    /// Rutas que no hay que escanear la próxima vez que aparezcan
    /// (p. ej. un archivo que el usuario acaba de restaurar de la cuarentena).
    private var ignorar: Set<String> = []

    init(alLlegar: @escaping ([URL]) -> Void) {
        self.alLlegar = alLlegar
    }

    var activo: Bool { flujo != nil }

    /// Empieza a vigilar esas carpetas (y sus subcarpetas).
    func empezar(carpetas: [URL]) {
        detener()
        guard !carpetas.isEmpty else { return }

        // FSEvents llama a una función de C; le pasamos este objeto como "info"
        // para poder volver a él desde la función.
        var contexto = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)

        let opciones = UInt32(
            kFSEventStreamCreateFlagFileEvents      // un evento por archivo, no por carpeta
            | kFSEventStreamCreateFlagUseCFTypes    // rutas como CFArray de CFString
        )

        let funcion: FSEventStreamCallback = { _, info, numero, rutas, banderas, _ in
            guard let info else { return }
            let vigilante = Unmanaged<Vigilante>.fromOpaque(info).takeUnretainedValue()
            let listaRutas = unsafeBitCast(rutas, to: NSArray.self) as? [String] ?? []
            let listaBanderas = Array(UnsafeBufferPointer(start: banderas, count: numero))
            // Programamos el flujo en la cola principal (abajo), así que ya estamos en ella.
            MainActor.assumeIsolated {
                vigilante.recibir(rutas: listaRutas, banderas: listaBanderas)
            }
        }

        guard let flujo = FSEventStreamCreate(
            nil, funcion, &contexto,
            carpetas.map(\.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),   // solo lo que pase a partir de ahora
            1.0,                                                   // agrupar eventos de 1 s
            opciones)
        else { return }

        FSEventStreamSetDispatchQueue(flujo, DispatchQueue.main)
        FSEventStreamStart(flujo)
        self.flujo = flujo
    }

    func detener() {
        if let flujo {
            FSEventStreamStop(flujo)
            FSEventStreamInvalidate(flujo)
            FSEventStreamRelease(flujo)
        }
        flujo = nil
        temporizador?.cancel()
        temporizador = nil
        pendientes = []
    }

    /// No escanear este archivo la próxima vez que aparezca.
    func ignorarUnaVez(_ archivo: URL) {
        ignorar.insert(archivo.path)
    }

    // MARK: - Eventos

    private func recibir(rutas: [String], banderas: [FSEventStreamEventFlags]) {
        let interesantes = FSEventStreamEventFlags(
            kFSEventStreamEventFlagItemCreated
            | kFSEventStreamEventFlagItemRenamed
            | kFSEventStreamEventFlagItemModified)
        let esArchivo = FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile)

        for (ruta, bandera) in zip(rutas, banderas)
        where bandera & esArchivo != 0 && bandera & interesantes != 0 {
            if ignorar.remove(ruta) != nil { continue }
            let archivo = URL(filePath: ruta)
            if merece(archivo) {
                pendientes.insert(archivo)
            }
        }

        if !pendientes.isEmpty {
            programarRevision()
        }
    }

    /// ¿Es un archivo terminado que merece la pena escanear?
    private func merece(_ archivo: URL) -> Bool {
        // Al renombrar llega un evento también para el nombre antiguo, que ya no existe.
        guard FileManager.default.fileExists(atPath: archivo.path) else { return false }
        // Ocultos (.DS_Store y similares).
        if archivo.lastPathComponent.hasPrefix(".") { return false }
        // Temporales de descarga, o archivos dentro de una descarga de Safari (X.download/).
        for componente in archivo.pathComponents {
            let ext = (componente as NSString).pathExtension.lowercased()
            if Self.extensionesTemporales.contains(ext) { return false }
        }
        return true
    }

    /// Espera a que dejen de llegar cambios y revisa los pendientes.
    /// Cada evento nuevo reinicia la espera.
    private func programarRevision() {
        temporizador?.cancel()
        temporizador = Task {
            try? await Task.sleep(for: Self.espera)
            guard !Task.isCancelled else { return }
            await revisarPendientes()
        }
    }

    /// Entrega los pendientes cuyo tamaño no cambia; los demás siguen esperando.
    private func revisarPendientes() async {
        let antes = tamaños(de: pendientes)
        try? await Task.sleep(for: Self.pausaEstabilidad)
        guard !Task.isCancelled else { return }
        let despues = tamaños(de: pendientes)

        var estables: [URL] = []
        for archivo in pendientes {
            guard let tamaño = despues[archivo] else {
                pendientes.remove(archivo)          // ya no existe: lo olvidamos
                continue
            }
            if antes[archivo] == tamaño {
                estables.append(archivo)
                pendientes.remove(archivo)
            }
        }

        if !estables.isEmpty {
            alLlegar(estables.sorted { $0.path < $1.path })
        }
        if !pendientes.isEmpty {
            programarRevision()                     // alguno sigue creciendo
        }
    }

    private func tamaños(de archivos: Set<URL>) -> [URL: Int] {
        var resultado: [URL: Int] = [:]
        for archivo in archivos {
            if let tamaño = try? FileManager.default.attributesOfItem(atPath: archivo.path)[.size] as? Int {
                resultado[archivo] = tamaño
            }
        }
        return resultado
    }
}
