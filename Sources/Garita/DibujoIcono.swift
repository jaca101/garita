import AppKit

/// Dibuja el icono de la barra de menú: el escudo de Garita con una letra dentro.
///
/// Es una imagen "plantilla" (isTemplate): monocroma, y macOS la pinta en blanco
/// o negro según el fondo de la barra, el modo oscuro y si está seleccionada,
/// como el resto de iconos de la barra.
enum DibujoIcono {

    /// Escudo con "G" (todo bien) o con "!" (hay algo que resolver).
    static func barra(aviso: Bool) -> NSImage {
        let tamaño = NSSize(width: 18, height: 18)
        let imagen = NSImage(size: tamaño, flipped: false) { marco in
            // El contorno del escudo: símbolo de sistema "shield" (SF Symbols).
            let configuracion = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            if let escudo = NSImage(systemSymbolName: "shield", accessibilityDescription: nil)?
                .withSymbolConfiguration(configuracion) {
                let s = escudo.size
                escudo.draw(in: NSRect(x: (marco.width - s.width) / 2, y: (marco.height - s.height) / 2,
                                       width: s.width, height: s.height))
            }

            // La letra, centrada y algo por encima del centro (el escudo se estrecha abajo).
            let letra = NSAttributedString(string: aviso ? "!" : "G", attributes: [
                .font: NSFont.systemFont(ofSize: 8.5, weight: .black),
                .foregroundColor: NSColor.black,
            ])
            let t = letra.size()
            letra.draw(at: NSPoint(x: (marco.width - t.width) / 2, y: (marco.height - t.height) / 2 + 0.5))
            return true
        }
        imagen.isTemplate = true
        imagen.accessibilityDescription = aviso ? "Garita: hay algo que revisar" : "Garita"
        return imagen
    }
}
