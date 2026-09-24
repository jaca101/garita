import Foundation
import IOKit.ps

/// Un escaneo programado: qué carpeta, cada cuánto y a qué hora.
/// Se guardan en ~/Library/Application Support/Garita/programados.json.
struct TareaProgramada: Codable, Identifiable, Equatable {
    var id = UUID()
    var carpeta: String
    /// "diaria" o "semanal".
    var frecuencia = "diaria"
    /// Solo para "semanal": 1 = domingo, 2 = lunes … 7 = sábado (como Calendar).
    var diaSemana = 2
    var hora = 3
    var minuto = 0
    var activa = true
    /// Cuándo se creó o se ejecutó por última vez: las citas anteriores ya no cuentan.
    var ultimaEjecucion = Date()
    /// Resumen del último resultado, p. ej. "limpio · 120 archivos".
    var ultimoResultado: String?

    var url: URL { URL(filePath: carpeta) }

    /// La hora prevista más reciente que ya ha pasado (p. ej. hoy a las 3:00,
    /// o ayer si aún no son las 3:00).
    func ultimaCita(antesDe fecha: Date = Date()) -> Date? {
        var componentes = DateComponents()
        componentes.hour = hora
        componentes.minute = minuto
        if frecuencia == "semanal" {
            componentes.weekday = diaSemana
        }
        return Calendar.current.nextDate(after: fecha, matching: componentes,
                                         matchingPolicy: .nextTime, direction: .backward)
    }

    /// ¿Tiene una cita que ya pasó y aún no se ha hecho?
    /// (Si el Mac estaba dormido a esa hora, sigue pendiente hasta que se haga.)
    var pendiente: Bool {
        guard activa, let cita = ultimaCita() else { return false }
        return cita > ultimaEjecucion
    }

    /// "Cada día a las 03:00" o "Cada lunes a las 03:00".
    var descripcion: String {
        let horaTexto = String(format: "%02d:%02d", hora, minuto)
        if frecuencia == "semanal" {
            let dia = Calendar.current.weekdaySymbols[(diaSemana - 1) % 7]
            return "Cada \(dia) a las \(horaTexto)"
        }
        return "Cada día a las \(horaTexto)"
    }
}

/// Guardar y cargar la lista, y comprobaciones de energía.
enum Programados {

    static var archivo: URL {
        URL.applicationSupportDirectory.appending(path: "Garita/programados.json")
    }

    /// La primera vez (sin archivo), una tarea por defecto: Descargas cada noche.
    static func cargar() -> [TareaProgramada] {
        guard let datos = try? Data(contentsOf: archivo) else {
            return [TareaProgramada(carpeta: URL.homeDirectory.appending(path: "Downloads").path)]
        }
        let decodificador = JSONDecoder()
        decodificador.dateDecodingStrategy = .iso8601
        return (try? decodificador.decode([TareaProgramada].self, from: datos)) ?? []
    }

    static func guardar(_ tareas: [TareaProgramada]) {
        let codificador = JSONEncoder()
        codificador.dateEncodingStrategy = .iso8601
        codificador.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let datos = try? codificador.encode(tareas) else { return }
        try? FileManager.default.createDirectory(at: archivo.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? datos.write(to: archivo, options: .atomic)
    }

    /// ¿Está el Mac conectado a la corriente? (Los Mac de sobremesa, siempre.)
    static func conCorriente() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let tipo = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        else { return true }
        return tipo == kIOPMACPowerKey
    }
}
