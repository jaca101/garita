import Foundation
import UserNotifications

/// Notificaciones nativas de macOS (las del Centro de notificaciones).
///
/// Aquí se decide QUÉ se avisa y con qué texto; ModeloApp.avisar(_:) se encarga
/// de enviarlo y de apuntarlo en el historial.
///
/// Qué avisa Garita:
///   - el vigilante aísla o encuentra una amenaza  → importante (con sonido)
///   - el vigilante no pudo analizar un archivo    → normal
///   - termina un escaneo manual y Garita no está delante → normal (o importante si hay amenazas)
/// Las descargas limpias no se notifican, para no avisar de cada descarga.
enum Notificaciones {

    /// Pide permiso para notificar (macOS solo lo pregunta la primera vez).
    /// Devuelve si están permitidas.
    static func pedirPermiso() async -> Bool {
        let centro = UNUserNotificationCenter.current()
        let permitidas = (try? await centro.requestAuthorization(options: [.alert, .sound])) ?? false
        return permitidas
    }

    /// Retira del Centro de notificaciones las que quedaron de ejecuciones anteriores
    /// (siguen en el historial de Garita).
    static func retirarAntiguas() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    /// Muestra un aviso como notificación inmediata.
    static func enviar(_ aviso: Aviso) {
        let contenido = UNMutableNotificationContent()
        contenido.title = aviso.titulo
        contenido.body = aviso.texto
        if aviso.importante {
            contenido.sound = .default
        }
        let peticion = UNNotificationRequest(identifier: aviso.id.uuidString, content: contenido, trigger: nil)
        UNUserNotificationCenter.current().add(peticion)
    }

    // MARK: - Mensajes

    /// Resume lo que ha encontrado el vigilante en un lote (un aviso por tipo).
    static func avisos(para eventos: [EventoVigilante]) -> [Aviso] {
        var aislados: [String] = []
        var sinAislar: [String] = []
        var sinAnalizar: [String] = []

        for evento in eventos {
            let nombre = evento.archivo.lastPathComponent
            switch evento.resultado {
            case .aislado(let amenaza):      aislados.append("\(nombre) (\(amenaza))")
            case .amenaza(let amenaza):      sinAislar.append("\(nombre) (\(amenaza))")
            case .noAnalizado(let motivo):   sinAnalizar.append("\(nombre): \(motivo)")
            case .error(let fallo):          sinAnalizar.append("\(nombre): \(fallo)")
            case .limpio:                    break
            }
        }

        var avisos: [Aviso] = []
        if !aislados.isEmpty {
            avisos.append(Aviso(
                titulo: aislados.count == 1 ? "Amenaza aislada" : "\(aislados.count) amenazas aisladas",
                texto: lista(aislados) + "\nMovido a la cuarentena de Garita.",
                importante: true))
        }
        if !sinAislar.isEmpty {
            avisos.append(Aviso(
                titulo: sinAislar.count == 1 ? "⚠️ Amenaza en tus descargas" : "⚠️ \(sinAislar.count) amenazas en tus descargas",
                texto: lista(sinAislar) + "\nNo se ha aislado: abre Garita para decidir.",
                importante: true))
        }
        if !sinAnalizar.isEmpty {
            avisos.append(Aviso(
                titulo: sinAnalizar.count == 1 ? "Descarga sin analizar" : "\(sinAnalizar.count) descargas sin analizar",
                texto: lista(sinAnalizar),
                importante: false))
        }
        return avisos
    }

    /// Resultado de un escaneo manual (nil si se canceló).
    static func aviso(para resultado: ResultadoEscaneo) -> Aviso? {
        if resultado.cancelado { return nil }
        if let fallo = resultado.fallo {
            return Aviso(titulo: "El escaneo ha fallado", texto: fallo, importante: false)
        }
        if resultado.detecciones.isEmpty {
            let n = resultado.archivosAnalizados ?? 0
            return Aviso(titulo: "Escaneo terminado: limpio",
                         texto: n == 1 ? "1 archivo analizado." : "\(n) archivos analizados.",
                         importante: false)
        }
        let n = resultado.detecciones.count
        return Aviso(titulo: n == 1 ? "Escaneo terminado: 1 amenaza" : "Escaneo terminado: \(n) amenazas",
                     texto: lista(resultado.detecciones.map { "\($0.archivo.lastPathComponent) (\($0.amenaza))" }),
                     importante: true)
    }

    /// Hasta 3 líneas y "y N más".
    private static func lista(_ lineas: [String]) -> String {
        var texto = lineas.prefix(3).joined(separator: "\n")
        if lineas.count > 3 {
            texto += "\ny \(lineas.count - 3) más"
        }
        return texto
    }
}
