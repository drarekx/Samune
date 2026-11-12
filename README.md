# Samune

Lanzador para buscar apps, archivos y contenido de tus servicios

## Instalar

Abre Terminal y pega:

```sh
curl -fsSL https://raw.githubusercontent.com/drarekx/Samune/main/install.sh | bash
```

El instalador descarga la última versión, la copia en `/Applications` y la abre. Samune vive en la barra de menús; no sale en el Dock.

Samune se actualiza sola: busca versiones nuevas al arrancar y una vez al día (o desde el menú → **Buscar actualizaciones…**), comprueba la descarga con su SHA-256 y se reinicia ya actualizada. Se puede desactivar en Ajustes. Volver a ejecutar el comando de instalación también actualiza.

**Instalación manual:** descarga `Samune.zip` de [Releases](https://github.com/drarekx/Samune/releases/latest), descomprímelo y mueve `Samune.app` a Aplicaciones. La app no está notarizada, así que la primera vez ábrela con clic derecho → **Abrir**.

Requisitos: macOS 14 (Sonoma) o posterior. Apple Silicon o Intel.

## Para qué sirve

<!-- El problema que resuelve, en dos o tres frases. -->

## Cómo funciona

<!-- Pasos numerados, cada uno con su captura:
<p align="center"><img src="docs/main.png" width="560" alt="…"></p>
-->

## Todo lo que hace

- **Colores**: temas clásicos con sus colores oficiales (Solarized, Dracula, Nord, Gruvbox, Monokai, One Dark, Tokyo Night, Catppuccin, Rosé Pine, Everforest, Kanagawa, GitHub Dark) además del original.
- **Idiomas**: castellano, inglés y catalán.
- **Abrir al iniciar sesión**: se activa la primera vez que se abre desde Aplicaciones; se puede quitar en Ajustes.

¿Te es útil? [Invítame a un café](https://buymeacoffee.com/drarek) ☕

## Dónde guarda las cosas

- Ajustes: `defaults read com.egluu.samune`

## Desinstalar

```sh
osascript -e 'quit app "Samune"'
rm -rf /Applications/Samune.app ~/Library/Application\ Support/Samune
defaults delete com.egluu.samune
```

## Compilar desde el código

```sh
git clone https://github.com/drarekx/Samune.git
cd Samune
./build-app.sh          # deja build/Samune.app y build/Samune.zip
open build/Samune.app
```

Con Xcode 16+ el binario es universal (arm64 + x86_64); solo con las Command Line Tools se compila para la arquitectura del Mac.

Para publicar una versión nueva, crea y sube una etiqueta; GitHub Actions compila la app y crea el release con el zip:

```sh
git tag v1.0.1 && git push origin v1.0.1
```
