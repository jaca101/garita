import Foundation

/// Una entrada del registro de actividad del vigilante.
struct EventoVigilante: Identifiable {
    enum Resultado {
        case limpio
        case aislado(amenaza: String)      // amenaza movida a la cuarentena
        case amenaza(String)               // amenaza sin aislar (modo "solo avisar" o fallo al aislar)
        case noAnalizado(String)           // p. ej. demasiado grande o sin permiso
        case error(String)                 // clamscan no pudo ejecutarse
    }

    let id = UUID()
    let archivo: URL
    let fecha = Date()
    var resultado: Resultado

    /// Amenaza que sigue en su sitio: hay que hacer algo.
    var pendienteDeResolver: Bool {
        if case .amenaza = resultado { return true }
        return false
    }
}

/// Todo lo del vigilante de descargas: carpetas, escaneo por lotes y registro.
extension ModeloApp {

    /// Carpetas que vigila Garita.
    static var carpetasPorDefecto: [URL] {
        let casa = URL.homeDirectory
        return [
            casa.appending(path: "Downloads"),
            casa.appending(path: "Documents/aMule Downloads"),
        ]
    }

    /// Las carpetas guardadas o, la primera vez, las predeterminadas que existan.
    static func cargarCarpetasVigiladas() -> [URL] {
        if let rutas = UserDefaults.standard.stringArray(forKey: "carpetasVigiladas") {
            return rutas.map { URL(filePath: $0) }
        }
        return carpetasPorDefecto.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Añade carpetas a vigilar (sin repetir las que ya están).
    func añadirCarpetasVigiladas(_ carpetas: [URL]) {
        let nuevas = carpetas.filter { nueva in !carpetasVigiladas.contains { $0.path == nueva.path } }
        carpetasVigiladas += nuevas
    }

    func quitarCarpetaVigilada(_ carpeta: URL) {
        carpetasVigiladas.removeAll { $0.path == carpeta.path }
    }

    func restablecerCarpetasVigiladas() {
        carpetasVigiladas = Self.carpetasPorDefecto.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Cuántas entradas guardamos en el registro de actividad.
    static let maxActividad = 50

    /// Arranca o detiene el vigilante según `vigilanteActivo`.
    func aplicarVigilante() {
        guard let vigilante else { return }
        if vigilanteActivo {
            // Solo las que existen ahora (un disco externo puede no estar conectado).
            let existentes = carpetasVigiladas.filter { FileManager.default.fileExists(atPath: $0.path) }
            // Descargas y Documentos son carpetas protegidas: leerlas ahora hace que
            // macOS pida permiso al arrancar, y no más tarde, en mitad de un escaneo.
            for carpeta in existentes {
                _ = try? FileManager.default.contentsOfDirectory(atPath: carpeta.path)
            }
            vigilante.empezar(carpetas: existentes)
        } else {
            vigilante.detener()
            colaVigilante = []
        }
    }

    /// El vigilante entrega un lote de archivos nuevos y ya terminados.
    func recibirDelVigilante(_ archivos: [URL]) {
        colaVigilante += archivos
        escanearColaVigilante()
    }

    /// Escanea de una vez todo lo que haya en la cola (un solo clamscan por lote).
    /// Si ya hay un lote en marcha, o el motor no está listo, espera.
    func escanearColaVigilante() {
        guard vigilanteEscaneando.isEmpty, !colaVigilante.isEmpty,
              let (programa, alternativa) = programas(rapido: true) else { return }
        let huellas = huellasSeguras, rutasSeg = rutasSeguras

        let lote = colaVigilante
        colaVigilante = []
        vigilanteEscaneando = lote

        Task {
            let resultado = await Task.detached {
                let primero = Escaner.escanear(lote, con: programa, alternativa: alternativa) { _ in }
                let completo = AnalisisAFondo.completar(primero, programa: programa, alternativa: alternativa,
                                                        prioridadBaja: true, alArrancar: { _ in }, alAvanzar: { _, _ in })
                return Seguros.filtrar(completo, huellas: huellas, rutas: rutasSeg)
            }.value
            vigilanteEscaneando = []
            registrar(lote, resultado)
            escanearColaVigilante()     // por si llegaron más mientras tanto
        }
    }

    /// Apunta en el registro qué ha pasado con cada archivo del lote y, si toca,
    /// aísla las amenazas.
    private func registrar(_ lote: [URL], _ resultado: ResultadoEscaneo) {
        var nuevos: [EventoVigilante] = []

        for archivo in lote {
            if let fallo = resultado.fallo {
                nuevos.append(EventoVigilante(archivo: archivo, resultado: .error(fallo)))
            } else if let deteccion = resultado.detecciones.first(where: { $0.archivo.path == archivo.path }) {
                var evento = EventoVigilante(archivo: archivo, resultado: .amenaza(deteccion.amenaza))
                if aislarAutomaticamente {
                    aislar(&evento)
                }
                nuevos.append(evento)
            } else if let problema = resultado.problemas.first(where: { $0.archivo.path == archivo.path }) {
                nuevos.append(EventoVigilante(archivo: archivo, resultado: .noAnalizado(problema.motivo)))
            } else {
                nuevos.append(EventoVigilante(archivo: archivo, resultado: .limpio))
            }
        }

        actividad.insert(contentsOf: nuevos, at: 0)
        if actividad.count > Self.maxActividad {
            actividad.removeLast(actividad.count - Self.maxActividad)
        }

        avisar(Notificaciones.avisos(para: nuevos))
    }

    /// Aísla una amenaza del registro (botón "Aislar" en modo "solo avisar").
    func aislar(_ evento: EventoVigilante) {
        guard let i = actividad.firstIndex(where: { $0.id == evento.id }) else { return }
        aislar(&actividad[i])
    }

    /// Mueve a la cuarentena el archivo de un evento y actualiza su resultado.
    private func aislar(_ evento: inout EventoVigilante) {
        guard case .amenaza(let amenaza) = evento.resultado else { return }
        do {
            let elemento = try Cuarentena.aislar(evento.archivo, amenaza: amenaza)
            cuarentena.insert(elemento, at: 0)
            evento.resultado = .aislado(amenaza: amenaza)
        } catch {
            errorCuarentena = "No se pudo aislar \(evento.archivo.lastPathComponent): \(error.localizedDescription)"
        }
    }
}
