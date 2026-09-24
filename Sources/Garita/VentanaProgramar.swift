import AppKit
import SwiftUI

/// Editor de un escaneo programado: carpeta, frecuencia y hora.
/// Trabaja sobre `modelo.borradorTarea` (una copia): nada cambia hasta "Guardar".
struct VentanaProgramar: View {
    @Environment(ModeloApp.self) private var modelo
    @Environment(\.dismissWindow) private var cerrarVentana

    var body: some View {
        @Bindable var modelo = modelo

        Group {
            if let borrador = Binding($modelo.borradorTarea) {
                formulario(borrador)
            } else {
                Text("No hay ningún escaneo en edición.")
                    .foregroundStyle(.secondary)
                    .padding(40)
            }
        }
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func formulario(_ tarea: Binding<TareaProgramada>) -> some View {
        let esNueva = !modelo.programados.contains { $0.id == tarea.wrappedValue.id }

        return Form {
            Section(esNueva ? "Nuevo escaneo programado" : "Editar escaneo programado") {
                LabeledContent("Carpeta") {
                    HStack {
                        Text(FileManager.default.displayName(atPath: tarea.wrappedValue.carpeta))
                            .lineLimit(1).truncationMode(.middle)
                            .help(tarea.wrappedValue.carpeta)
                        Button("Elegir…") { elegirCarpeta(tarea) }
                    }
                }

                Picker("Frecuencia", selection: tarea.frecuencia) {
                    Text("Cada día").tag("diaria")
                    Text("Cada semana").tag("semanal")
                }

                if tarea.wrappedValue.frecuencia == "semanal" {
                    Picker("Día", selection: tarea.diaSemana) {
                        // Empezamos en lunes (2) y terminamos en domingo (1).
                        ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { dia in
                            Text(Calendar.current.weekdaySymbols[dia - 1].capitalized).tag(dia)
                        }
                    }
                }

                DatePicker("Hora", selection: hora(tarea), displayedComponents: .hourAndMinute)
            }

            Section {
                Text("Si a esa hora el Mac está dormido o con batería, se hará en cuanto esté despierto y enchufado. Se ejecuta con prioridad baja para no ralentizar el Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Cancelar") { cerrar() }
                    .keyboardShortcut(.cancelAction)
                Button("Guardar") {
                    modelo.guardarBorrador()
                    cerrarVentana(id: "programar")
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
    }

    /// Convierte hora y minuto de la tarea en una fecha para el DatePicker, y viceversa.
    private func hora(_ tarea: Binding<TareaProgramada>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: tarea.wrappedValue.hora,
                                      minute: tarea.wrappedValue.minuto, second: 0, of: Date()) ?? Date()
            },
            set: { fecha in
                let c = Calendar.current.dateComponents([.hour, .minute], from: fecha)
                tarea.wrappedValue.hora = c.hour ?? 3
                tarea.wrappedValue.minuto = c.minute ?? 0
            })
    }

    private func elegirCarpeta(_ tarea: Binding<TareaProgramada>) {
        let selector = NSOpenPanel()
        selector.canChooseFiles = false
        selector.canChooseDirectories = true
        selector.allowsMultipleSelection = false
        selector.directoryURL = tarea.wrappedValue.url
        selector.prompt = "Elegir"
        if selector.runModal() == .OK, let carpeta = selector.url {
            tarea.wrappedValue.carpeta = carpeta.path
        }
    }

    private func cerrar() {
        modelo.borradorTarea = nil
        cerrarVentana(id: "programar")
    }
}
