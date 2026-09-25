import AppKit

/// Escaneos programados: el reloj que los revisa, su ejecución y la edición de la lista.
extension ModeloApp {

    /// Cuántos archivos sin analizar guardamos por tarea.
    static let maxProblemasGuardados = 500

    /// Margen tras arrancar o despertar el Mac antes de lanzar un escaneo programado.
    static let margenTrasDespertar: TimeInterval = 5 * 60

    /// Arranca el reloj: cada minuto mira si hay alguna tarea pendiente.
    /// Si el Mac duerme, el reloj se para con él y sigue al despertar.
    func arrancarProgramador() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.despertoEn = Date() }
        }

        Task {
            while true {
                try? await Task.sleep(for: .seconds(60))
                revisarActualizacionAutomatica()
                revisarProgramados()
            }
        }
    }

    /// ¿Por qué no se lanza ahora una tarea pendiente? (nil = nada lo impide)
    var motivoEspera: String? {
        if tareaEnCurso != nil { return nil }
        if motor?.listo != true { return "Esperando a que el motor esté listo" }
        if !Programados.conCorriente() { return "Esperando a que conectes el cargador" }
        if Date().timeIntervalSince(despertoEn) < Self.margenTrasDespertar {
            return "Empezará en unos minutos (margen tras encender el Mac)"
        }
        return nil
    }

    /// Lanza la primera tarea pendiente, si se dan las condiciones.
    func revisarProgramados() {
        guard tareaEnCurso == nil, motivoEspera == nil,
              let tarea = programados.first(where: \.pendiente) else { return }
        ejecutar(tarea)
    }

    /// Ejecuta una tarea ya (también desde "Ejecutar ahora", sin esperar a la corriente).
    func ejecutar(_ tarea: TareaProgramada) {
        guard tareaEnCurso == nil, let motor, let clamscan = motor.clamscan, motor.listo else { return }
        let opciones = motor.opcionesClamscan
        let huellas = huellasSeguras
        tareaEnCurso = tarea.id
        programadoCancelado = false
        progresoProgramado = ProgresoEscaneo()

        Task {
            var resultado = await Task.detached {
                let alArrancar: @Sendable (Int32) -> Void = { pid in
                    Task { @MainActor in self.pidProgramado = pid }
                }
                let alAvanzar: @Sendable (Int, String) -> Void = { archivos, ultimo in
                    Task { @MainActor in self.progresoProgramado?.avanzar(archivos, ultimo) }
                }
                let primero = Escaner.escanear([tarea.url], con: clamscan, opciones: opciones, prioridadBaja: true,
                                               alArrancar: alArrancar, alAvanzar: alAvanzar)
                let completo = AnalisisAFondo.completar(primero, clamscan: clamscan, opciones: opciones,
                                                        prioridadBaja: true, alArrancar: alArrancar, alAvanzar: alAvanzar)
                return Seguros.filtrar(completo, huellas: huellas)
            }.value
            progresoProgramado = nil
            resultado.cancelado = programadoCancelado
            pidProgramado = nil
            terminar(tarea, con: resultado)
            tareaEnCurso = nil
            revisarProgramados()    // por si había otra pendiente
        }
    }

    /// Detiene el escaneo programado en curso.
    func detenerProgramado() {
        guard let pidProgramado else { return }
        programadoCancelado = true
        Proceso.detener(pid: pidProgramado)
    }

    /// Anota el resultado en la tarea, aísla las amenazas (según el ajuste) y avisa.
    private func terminar(_ tarea: TareaProgramada, con resultado: ResultadoEscaneo) {
        var aisladas = 0
        if !resultado.cancelado && aislarAutomaticamente {
            for deteccion in resultado.detecciones {
                if let elemento = try? Cuarentena.aislar(deteccion.archivo, amenaza: deteccion.amenaza) {
                    cuarentena.insert(elemento, at: 0)
                    aisladas += 1
                }
            }
        }

        let resumen = Self.resumen(resultado, aisladas: aisladas)
        if let i = programados.firstIndex(where: { $0.id == tarea.id }) {
            // Aunque se cancele, cuenta como hecha: si no, volvería a empezar al minuto.
            programados[i].ultimaEjecucion = Date()
            programados[i].ultimoResultado = resumen
            programados[i].ultimosProblemas = resultado.problemas.prefix(Self.maxProblemasGuardados)
                .map { "\($0.archivo.path): \($0.motivo)" }
            Programados.guardar(programados)
        }

        if resultado.cancelado { return }
        let nombre = FileManager.default.displayName(atPath: tarea.carpeta)
        let hayAmenazas = !resultado.detecciones.isEmpty
        var texto = resumen
        if hayAmenazas {
            texto += "\n" + resultado.detecciones.prefix(3)
                .map { "\($0.archivo.lastPathComponent) (\($0.amenaza))" }.joined(separator: "\n")
        }
        if !resultado.problemas.isEmpty {
            // En el historial, también qué no se pudo analizar (hasta 30).
            texto += "\n\nSin analizar del todo:\n" + resultado.problemas.prefix(30)
                .map { "• \($0.archivo.path): \($0.motivo)" }.joined(separator: "\n")
            if resultado.problemas.count > 30 { texto += "\ny \(resultado.problemas.count - 30) más" }
        }
        let aviso = Aviso(
            titulo: hayAmenazas ? "Escaneo programado de \(nombre): amenazas" : "Escaneo programado de \(nombre)",
            texto: texto,
            importante: hayAmenazas)
        // Siempre al historial; notificación solo si hay algo que contar
        // (no queremos un aviso de "limpio" cada noche a las 3:00).
        avisar([aviso], notificar: hayAmenazas || resultado.fallo != nil)
    }

    /// "limpio · 120 archivos", "2 amenazas (2 aisladas) · 120 archivos · 3 sin analizar"…
    private static func resumen(_ r: ResultadoEscaneo, aisladas: Int) -> String {
        if r.cancelado { return "detenido" }
        if let fallo = r.fallo { return "error: \(fallo)" }
        var partes: [String] = []
        let n = r.detecciones.count
        if n == 0 {
            partes.append("limpio")
        } else {
            var texto = n == 1 ? "1 amenaza" : "\(n) amenazas"
            if aisladas > 0 {
                texto += aisladas == n ? (n == 1 ? " (aislada)" : " (aisladas)") : " (\(aisladas) aisladas)"
            }
            partes.append(texto)
        }
        if let analizados = r.archivosAnalizados {
            partes.append(analizados == 1 ? "1 archivo" : "\(analizados) archivos")
        }
        if !r.problemas.isEmpty {
            partes.append("\(r.problemas.count) sin analizar")
        }
        return partes.joined(separator: " · ")
    }

    // MARK: - Editar la lista

    /// Abre el editor con una tarea nueva (o una copia de una existente).
    func editar(_ tarea: TareaProgramada?) {
        borradorTarea = tarea ?? TareaProgramada(carpeta: URL.homeDirectory.appending(path: "Downloads").path)
    }

    /// Guarda la tarea editada: la sustituye si ya existía, o la añade.
    func guardar(_ tarea: TareaProgramada) {
        var tarea = tarea
        if let i = programados.firstIndex(where: { $0.id == tarea.id }) {
            // Al cambiar la hora no queremos que se dispare al instante por una cita pasada.
            tarea.ultimaEjecucion = max(programados[i].ultimaEjecucion, Date())
            programados[i] = tarea
        } else {
            tarea.ultimaEjecucion = Date()
            programados.append(tarea)
        }
        Programados.guardar(programados)
        borradorTarea = nil
    }

    func cambiarActiva(_ tarea: TareaProgramada, _ activa: Bool) {
        guard let i = programados.firstIndex(where: { $0.id == tarea.id }) else { return }
        programados[i].activa = activa
        if activa {
            // Al reactivarla, empezamos a contar desde ahora.
            programados[i].ultimaEjecucion = Date()
        }
        Programados.guardar(programados)
    }

    func eliminar(_ tarea: TareaProgramada) {
        programados.removeAll { $0.id == tarea.id }
        Programados.guardar(programados)
    }
}
