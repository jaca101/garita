import SwiftUI

/// Coloca las secciones de arriba abajo en columnas de ancho fijo. Cuando la
/// siguiente ya no cabe en la altura máxima, empieza otra columna a la derecha
/// (como el texto de un periódico). Así la ventana no necesita scroll.
///
/// Se recalcula cada vez que cambia el contenido (p. ej. llega una descarga
/// nueva al vigilante) y la ventana se ajusta sola al nuevo tamaño.
struct ColumnasFluidas: Layout {
    var anchoColumna: CGFloat
    var altoMaximo: CGFloat
    var hueco: CGFloat = 12

    /// Posición (origen) de cada sección y tamaño total que ocupan.
    private func repartir(_ secciones: Subviews) -> (origenes: [CGPoint], tamano: CGSize) {
        var origenes: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var altoTotal: CGFloat = 0

        for seccion in secciones {
            let alto = seccion.sizeThatFits(ProposedViewSize(width: anchoColumna, height: nil)).height
            // No cabe y la columna ya tiene algo: pasamos a la siguiente.
            // (Si una sola sección es más alta que el máximo, se queda en su columna.)
            if y > 0 && y + alto > altoMaximo {
                x += anchoColumna + hueco
                y = 0
            }
            origenes.append(CGPoint(x: x, y: y))
            altoTotal = max(altoTotal, y + alto)
            y += alto + hueco
        }
        let ancho = secciones.isEmpty ? 0 : x + anchoColumna
        return (origenes, CGSize(width: ancho, height: altoTotal))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        repartir(subviews).tamano
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let origenes = repartir(subviews).origenes
        for (seccion, origen) in zip(subviews, origenes) {
            seccion.place(at: CGPoint(x: bounds.minX + origen.x, y: bounds.minY + origen.y),
                          proposal: ProposedViewSize(width: anchoColumna, height: nil))
        }
    }
}

extension View {
    /// Cada sección de la ventana va en su propia tarjeta, para que se distingan
    /// bien al estar repartidas en columnas.
    func tarjeta() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
