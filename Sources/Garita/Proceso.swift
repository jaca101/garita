import Foundation

/// Lo que devuelve un programa al terminar.
struct ResultadoProceso {
    /// Código de salida (0 suele significar "todo bien").
    var codigo: Int32
    /// Salida estándar y de errores, juntas y en el orden en que llegaron.
    var salida: String
}

enum Proceso {
    /// Ejecuta un programa, espera a que termine y devuelve su código y su salida.
    /// Bloquea hasta que acaba: llamarla siempre fuera del hilo principal.
    /// Devuelve nil si el programa ni siquiera pudo arrancar.
    ///
    /// `alArrancar`, si se indica, recibe el PID del proceso nada más arrancar,
    /// por si hay que detenerlo antes de tiempo (ver `detener`).
    ///
    /// `prioridadBaja`: macOS le da la CPU y el disco solo cuando nadie más los
    /// necesita (calidad de servicio "background"), para no ralentizar el Mac.
    ///
    /// `alRecibirLinea` recibe cada línea de salida en cuanto llega (para mostrar
    /// el progreso); se llama en este mismo hilo, mientras el programa trabaja.
    static func ejecutar(
        _ programa: URL,
        argumentos: [String],
        prioridadBaja: Bool = false,
        alArrancar: (@Sendable (Int32) -> Void)? = nil,
        alRecibirLinea: (String) -> Void = { _ in }
    ) -> ResultadoProceso? {
        let proceso = Process()
        proceso.executableURL = programa
        proceso.arguments = argumentos
        if prioridadBaja {
            proceso.qualityOfService = .background
        }

        // Una sola tubería para stdout y stderr: así no se pierde ningún mensaje
        // y no hay riesgo de que el programa se atasque con una tubería llena.
        let tuberia = Pipe()
        proceso.standardOutput = tuberia
        proceso.standardError = tuberia

        do {
            try proceso.run()
        } catch {
            return nil
        }
        alArrancar?(proceso.processIdentifier)

        // Leemos a trozos según va llegando (availableData espera hasta que hay
        // algo, y devuelve vacío cuando el programa cierra su salida).
        var datos = Data()
        var pendiente = Data()       // trozo de línea aún sin "\n"
        while true {
            let trozo = tuberia.fileHandleForReading.availableData
            if trozo.isEmpty { break }
            datos.append(trozo)
            pendiente.append(trozo)
            while let salto = pendiente.firstIndex(of: UInt8(ascii: "\n")) {
                alRecibirLinea(String(decoding: pendiente[..<salto], as: UTF8.self))
                pendiente.removeSubrange(...salto)
            }
        }
        proceso.waitUntilExit()

        let texto = String(decoding: datos, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ResultadoProceso(codigo: proceso.terminationStatus, salida: texto)
    }

    /// Pide a un proceso que termine (señal SIGTERM, como `kill` en la Terminal).
    static func detener(pid: Int32) {
        kill(pid, SIGTERM)
    }
}
