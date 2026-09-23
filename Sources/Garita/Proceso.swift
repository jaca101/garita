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
    static func ejecutar(_ programa: URL, argumentos: [String]) -> ResultadoProceso? {
        let proceso = Process()
        proceso.executableURL = programa
        proceso.arguments = argumentos

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
        let datos = tuberia.fileHandleForReading.readDataToEndOfFile()
        proceso.waitUntilExit()

        let texto = String(decoding: datos, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ResultadoProceso(codigo: proceso.terminationStatus, salida: texto)
    }
}
