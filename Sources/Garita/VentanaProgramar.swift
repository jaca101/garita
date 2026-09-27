import AppKit
import SwiftUI

/// Editor de un escaneo programado: carpeta, frecuencia y hora.
///
/// `modelo.borradorTarea` dice QUÉ tarea editar; el formulario trabaja sobre su
/// propia copia (@State) y solo la devuelve al modelo al pulsar "Guardar".
/// (No enlazamos el formulario al borrador del modelo: al guardar, el borrador
/// pasa a nil mientras la ventana aún se está dibujando, y SwiftUI se caería.)
struct VentanaProgramar: View {
    @Environment(ModeloApp.self) private var modelo

    var body: some View {
        Group {
            if let borrador = modelo.borradorTarea {
                FormularioTarea(tarea: borrador)
                    .id(borrador.id)    // otra tarea → formulario nuevo, con su copia
            } else {
                Text("No hay ningún escaneo en edición.")
                    .foregroundStyle(.secondary)
                    .padding(40)
            }
        }
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// El formulario, con su propia copia de la tarea.
private struct FormularioTarea: View {
    @Environment(ModeloApp.self) private var modelo
    @Environment(\.dismissWindow) private var cerrarVentana
    @State var tarea: TareaProgramada

    var body: some View {
        let esNueva = !modelo.programados.contains { $0.id == tarea.id }

        Form {
            Section(esNueva ? "Nuevo escaneo programado" : "Editar escaneo programado") {
                LabeledContent("Carpeta") {
                    HStack {
                        Text(FileManager.default.displayName(atPath: tarea.carpeta))
                            .lineLimit(1).truncationMode(.middle)
                            .help(tarea.carpeta)
                        Button("Elegir…") { elegirCarpeta() }
                    }
                }

                Picker("Frecuencia", selection: $tarea.frecuencia) {
                    Text("Cada día").tag("diaria")
                    Text("Cada semana").tag("semanal")
                }

                if tarea.frecuencia == "semanal" {
                    Picker("Día", selection: $tarea.diaSemana) {
                        // Empezamos en lunes (2) y terminamos en domingo (1).
                        ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { dia in
                            Text(Calendar.current.weekdaySymbols[dia - 1].capitalized).tag(dia)
                        }
                    }
                }

                DatePicker("Hora", selection: hora, displayedComponents: .hourAndMinute)
            }

            Section {
                Toggle("Saltar archivos sin cambios", isOn: $tarea.incremental)
                if tarea.incremental {
                    Stepper("Repasar todo cada \(tarea.dias) días", value: $tarea.dias, in: 1...30)
                }
            } footer: {
                Text("Solo se analiza lo nuevo o modificado. Cada \(tarea.dias) días se repasa todo, porque ClamAV publica firmas nuevas a diario y algo que hoy parece limpio puede no serlo mañana.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    cerrarVentana(id: "programar")
                    modelo.guardar(tarea)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
    }

    /// Convierte hora y minuto de la tarea en una fecha para el DatePicker, y viceversa.
    private var hora: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: tarea.hora,
                                      minute: tarea.minuto, second: 0, of: Date()) ?? Date()
            },
            set: { fecha in
                let c = Calendar.current.dateComponents([.hour, .minute], from: fecha)
                tarea.hora = c.hour ?? 3
                tarea.minuto = c.minute ?? 0
            })
    }

    private func elegirCarpeta() {
        let selector = NSOpenPanel()
        selector.canChooseFiles = false
        selector.canChooseDirectories = true
        selector.allowsMultipleSelection = false
        selector.directoryURL = tarea.url
        selector.prompt = "Elegir"
        if selector.runModal() == .OK, let carpeta = selector.url {
            tarea.carpeta = carpeta.path
        }
    }

    private func cerrar() {
        cerrarVentana(id: "programar")
        modelo.borradorTarea = nil
    }
}
