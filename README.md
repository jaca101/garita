# Garita

Antivirus de barra de menú para macOS: una interfaz nativa (SwiftUI), gratuita y de código legible para [ClamAV](https://www.clamav.net).

Su función principal es el **vigilante de descargas**: escanea automáticamente cada archivo nuevo que llega a `~/Downloads` y `~/Documents/aMule Downloads`.

## Funciones

- **Vigilante de descargas.** Usa FSEvents, ignora los archivos a medio descargar (`.crdownload`, `.part`…) y escanea por lotes con un solo `clamscan`. Puede aislar automáticamente o solo avisar.
- **Escaneo a demanda.** Arrastra a la ventana, usa el botón, o haz clic derecho en el Finder → «Escanear con Garita».
- **Firmas.** Botón para ejecutar `freshclam`, con la versión y la fecha de publicación de las firmas.
- **Cuarentena.** Mueve el archivo (no lo borra), le quita los permisos y lo codifica con XOR para que quede inerte. Cada archivo lleva una ficha JSON legible. Se puede restaurar o eliminar.
- **Notificaciones nativas** e **historial de avisos**.
- **Límite de 2 GB por archivo.** Lo que supera ese tamaño se marca como «no analizado», nunca se salta en silencio.

## Instalar (desde el .dmg)

Consulta [`Recursos/LEEME.txt`](Recursos/LEEME.txt), que va dentro del `.dmg`. En resumen:

1. Arrastra `Garita.app` a Aplicaciones.
2. La primera vez, ve a **Ajustes del Sistema → Privacidad y seguridad → «Abrir igualmente»**. La app tiene firma ad-hoc, no de Apple Developer.
3. Instala ClamAV con Homebrew: `brew install clamav`. Garita te guía si falta.
4. En Garita, pulsa **«Actualizar firmas»**.

## Compilar

Hace falta Xcode (o sus herramientas de línea de comandos) y macOS 15 o posterior.

```bash
./construir.sh abrir    # compila build/Garita.app para este Mac y la abre
./empaquetar.sh         # binario universal + build/Garita-<versión>.dmg
```

El proyecto usa Swift Package Manager, sin proyecto de Xcode: todo es texto legible.

| Archivo | Qué hace |
|---|---|
| `Sources/Garita/GaritaApp.swift` | Punto de entrada: icono de barra, ventanas y menú |
| `Sources/Garita/ModeloApp.swift` | Estado compartido de la app |
| `Sources/Garita/MotorClamAV.swift` | Detecta `clamscan`, `freshclam`, la configuración y las firmas |
| `Sources/Garita/Escaner.swift` | Ejecuta `clamscan` e interpreta su salida |
| `Sources/Garita/Vigilante.swift` | FSEvents: detecta descargas nuevas y terminadas |
| `Sources/Garita/Cuarentena.swift` | Aislar, restaurar y eliminar |
| `Sources/Garita/Notificaciones.swift` · `Historial.swift` | Avisos |
| `Sources/Garita/Seccion*.swift` · `Ventana*.swift` | Interfaz |

## Dónde guarda cosas

- **Cuarentena:** `~/Library/Application Support/Garita/Cuarentena/`
- **Historial de avisos:** `~/Library/Application Support/Garita/historial.json`
- **Ajustes:** `defaults read local.garita`

## Planes

- **v2:** escaneos programados y carpetas vigiladas configurables.
- Incluir ClamAV dentro de la app, para instalar sin Homebrew.
