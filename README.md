# Garita

Antivirus de barra de menú para macOS: una interfaz nativa (SwiftUI), gratuita y de código legible para [ClamAV](https://www.clamav.net).

Su función principal es el **vigilante de descargas**: escanea automáticamente cada archivo nuevo que llega a `~/Downloads` y `~/Documents/aMule Downloads`.

## Funciones

- **Vigilante de descargas.** Usa FSEvents, ignora los archivos a medio descargar (`.crdownload`, `.part`…) y escanea por lotes con un solo `clamscan`. Puede aislar automáticamente o solo avisar.
- **Escaneo a demanda.** Arrastra a la ventana, usa el botón, o haz clic derecho en el Finder → «Escanear con Garita».
- **ClamAV integrado.** Va dentro de la app, así que no hace falta Homebrew. Las firmas se descargan solas al abrir Garita por primera vez y se actualizan cada 12 horas; también hay un botón para forzarlo.
- **Cuarentena.** Mueve el archivo (no lo borra), le quita los permisos y lo codifica con XOR para que quede inerte. Cada archivo lleva una ficha JSON legible. Se puede restaurar o eliminar.
- **Escaneos programados «solo cambios».** Cada noche se analiza solo lo nuevo o modificado, y cada 7 días se repasa todo, porque ClamAV publica firmas nuevas a diario.
- **Escaneo rápido opcional (clamd).** Mantiene las firmas en memoria (~1,6 GB) y los avisos del vigilante llegan en ~9 s en vez de ~17 s. Viene desactivado; si `clamd` falla, se usa `clamscan`.
- **Marcar como seguro.** Para los falsos positivos: Garita guarda la huella SHA-256 del archivo y deja de avisar de él mientras no cambie.
- **Notificaciones nativas** e **historial de avisos**.
- **Límites amplios y análisis a fondo.** ClamAV revisa archivos de hasta 2 GB y comprimidos con hasta 100 000 archivos o 4 GB de contenido. Lo que aún supere esos límites se abre aparte: las DMG se montan solo lectura, y los ZIP, TAR y PKG se descomprimen en una carpeta temporal si hay espacio. Nada se salta en silencio.

## Instalar (desde el .dmg)

Consulta [`Recursos/LEEME.txt`](Recursos/LEEME.txt), que va dentro del `.dmg`. En resumen:

1. Arrastra `Garita.app` a Aplicaciones.
2. La primera vez, ve a **Ajustes del Sistema → Privacidad y seguridad → «Abrir igualmente»**. La app no está firmada con una cuenta de Apple Developer.
3. Garita descarga las firmas de virus la primera vez (~110 MB), sin que tengas que hacer nada.

## Compilar

Hace falta Xcode (o sus herramientas de línea de comandos) y macOS 15 o posterior.

```bash
./preparar-clamav.sh    # una vez: descarga el instalador oficial de ClamAV y prepara la versión integrada
./construir.sh abrir    # compila build/Garita.app para este Mac y la abre
./instalar.sh           # la instala o actualiza en /Applications
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

## ClamAV integrado

`preparar-clamav.sh` descarga el instalador oficial de Cisco para macOS (universal) y comprueba que lo firma Cisco. Después extrae solo `clamscan`, `freshclam`, sus librerías y el certificado de firmas, y los reubica para que funcionen dentro de la app, en `Contents/Helpers` y `Contents/Frameworks`. Garita ejecuta ClamAV como programa independiente, sin enlazar su librería.

ClamAV es © Cisco Systems, Inc., con licencia GNU GPLv2. Su licencia y el enlace a su código fuente van en `Contents/Resources/clamav/licencias`. Si no hay ClamAV integrado, por ejemplo en una compilación sin `preparar-clamav.sh`, Garita usa el de Homebrew.

## Dónde guarda cosas

- **Firmas y configuración de ClamAV:** `~/Library/Application Support/Garita/clamav/`
- **Cuarentena:** `~/Library/Application Support/Garita/Cuarentena/`
- **Historial de avisos:** `~/Library/Application Support/Garita/historial.json`
- **Ajustes:** `defaults read io.github.jaca101.garita`

## Planes

- Firma con Apple Developer ID y notarización, para que Gatekeeper no avise.
- Actualizaciones automáticas de la propia app (Sparkle).
