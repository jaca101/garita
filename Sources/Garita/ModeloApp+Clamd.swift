import Foundation

/// Escaneo rápido (clamd), opcional. Desactivado, todo va con clamscan como siempre.
extension ModeloApp {

    /// Arranca o para clamd según el ajuste y el estado del motor.
    /// Se llama al cambiar el ajuste y cada vez que se detecta el motor.
    func aplicarEscaneoRapido() {
        guard escaneoRapido, let motor, motor.listo, ServicioClamd.disponible(motor) else {
            if estadoClamd != .desactivado {
                clamd.detener()
                estadoClamd = .desactivado
            }
            return
        }
        switch estadoClamd {
        case .activo, .arrancando: return
        case .desactivado, .error: break
        }
        estadoClamd = .arrancando
        clamd.alCerrarseSolo = { [weak self] in
            self?.estadoClamd = .error("clamd se ha cerrado; se usa clamscan. Desactívalo y actívalo para reintentar.")
        }
        Task {
            let estado = await clamd.arrancar(motor)
            // Por si mientras arrancaba el usuario lo desactivó.
            if escaneoRapido { estadoClamd = estado } else { clamd.detener() }
        }
    }

    /// Con qué escanear. `rapido`: usar clamd si está activo (el vigilante y el
    /// escaneo manual; los programados van con clamscan y prioridad baja).
    /// Devuelve también la alternativa (clamscan) por si clamd no responde.
    func programas(rapido: Bool) -> (programa: Programa, alternativa: Programa?)? {
        guard let motor, let clamscan = motor.clamscan, motor.listo else { return nil }
        let normal = Programa(ejecutable: clamscan, opciones: motor.opcionesClamscan)
        if rapido, case .activo = estadoClamd, let conClamd = ServicioClamd.programa(motor) {
            return (conClamd, normal)
        }
        return (normal, nil)
    }

    /// Actualiza la memoria que muestra el panel (se llama cada minuto).
    func actualizarMemoriaClamd() {
        guard case .activo = estadoClamd else { return }
        Task {
            let mb = await clamd.memoriaMB()
            if case .activo = estadoClamd { estadoClamd = .activo(memoriaMB: mb) }
        }
    }

    /// Tras actualizar las firmas, que clamd las recargue.
    func recargarClamdSiActivo() {
        guard case .activo = estadoClamd, let motor else { return }
        Task { await clamd.recargar(motor) }
    }
}
