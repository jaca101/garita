import AppKit

/// Acceso total al disco: comprobar si Garita lo tiene y ayudar a concederlo.
///
/// macOS no deja que una app pida este permiso con un aviso de "Permitir": lo
/// tiene que activar el usuario en Ajustes del Sistema. Lo que sí podemos hacer
/// es saber si ya lo tenemos y llevarle directamente al sitio.
enum AccesoDisco {

    /// Un archivo que macOS solo deja leer a las apps con Acceso total al disco:
    /// la base de datos de permisos del usuario. Solo intentamos abrirlo y leer
    /// un byte; nunca lo modificamos.
    static var archivoProtegido: URL {
        URL.homeDirectory.appending(path: "Library/Application Support/com.apple.TCC/TCC.db")
    }

    /// ¿Tiene Garita Acceso total al disco?
    static func concedido() -> Bool {
        guard let archivo = try? FileHandle(forReadingFrom: archivoProtegido) else { return false }
        defer { try? archivo.close() }
        return (try? archivo.read(upToCount: 1)) != nil
    }

    /// Ajustes del Sistema → Privacidad y seguridad → Acceso total al disco.
    @MainActor
    static func abrirAjustes() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }

    /// Muestra Garita.app seleccionada en el Finder (para arrastrarla a la lista de Ajustes).
    @MainActor
    static func mostrarGaritaEnFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    /// Cierra Garita y la vuelve a abrir (a veces macOS no aplica el permiso
    /// hasta que la app se reinicia). Un pequeño proceso del sistema espera un
    /// segundo, cuando Garita ya se ha cerrado, y la abre de nuevo.
    @MainActor
    static func reiniciarGarita() {
        let reabrir = Process()
        reabrir.executableURL = URL(filePath: "/bin/sh")
        reabrir.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? reabrir.run()
        NSApplication.shared.terminate(nil)
    }
}
