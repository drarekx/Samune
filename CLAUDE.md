# Samune

Lanzador para buscar apps, archivos y contenido de tus servicios App nativa de macOS de barra de menús (sin icono en el Dock). Swift + AppKit/SwiftUI, sin dependencias en el código. Repo: https://github.com/drarekx/Samune (constante `AppInfo.repo` en `AppDelegate.swift`, también en `install.sh` y README).

Creada con la skill `crear-app-mac`: misma estructura, instalador, actualizador, temas, idiomas y menú que Wallpy, DemoImages y Droppy.

## Compilar y ejecutar

```sh
swift build                      # debug, comprobación rápida
./build-app.sh                   # release → build/Samune.app + build/Samune.zip (universal con Xcode; nativo con solo CLT)
VERSION=1.2.0 ./build-app.sh     # versión en Info.plist (por defecto 1.0.0)
open build/Samune.app
.build/debug/Samune -appLanguage ca   # probar otro idioma sin tocar los ajustes
```

- Requisitos: macOS 14+. `Package.swift` usa tools 5.10 (modo Swift 5).
- No hay tests. Verificar compilando y lanzando la app (y con capturas, ver «Pruebas manuales»).
- La copia instalada vive en `/Applications/Samune.app`; la de `build/` es de desarrollo y tiene versión 1.0.0, así que su actualizador siempre ve versiones nuevas.

## Publicar una versión

```sh
git tag v1.0.1 && git push origin v1.0.1
```

`.github/workflows/release.yml` (macos-15) compila con `VERSION` = tag y crea el release con `Samune.zip` y `Samune.zip.sha256`. `Updater.swift` consulta `releases/latest`, verifica el SHA-256 y el `Info.plist` y cambia el bundle. `build.yml` compila arm64 + x86_64 y verifica que `en` y `ca` tienen las mismas claves y que todo `tr()` está traducido. La app no está notarizada (firma ad-hoc). Commits con la skill `commit:commit`.

## Estructura (`Sources/Samune/`)

| Archivo | Qué hace |
|---|---|
| `main.swift`, `AppDelegate.swift` | Arranque, `AppInfo` (nombre, repo, Buy Me a Coffee, `menuBarApp`), icono y menú de la barra de menús, ventanas (principal y Ajustes), menú principal, gancho de depuración |
| `SettingsPane.swift` | Ajustes: colores, abrir al iniciar sesión, idioma, actualizaciones, invitar a un café |
| `Settings.swift` | `UserDefaults` (`com.egluu.samune`), `LoginItem` (`SMAppService`) |
| `Theme.swift` | Colores (sacados del tema elegido) y controles comunes: `AppButtonStyle`, `IconButton`, `SegmentedControl`, `SectionLabel`, `AppTextField`, `SwitchRow`, `appCard` |
| `Themes.swift` | `AppTheme` (Original, Solarized, Dracula, Nord, Gruvbox, Monokai, One Dark, Tokyo Night, Catppuccin, Rosé Pine, Everforest, Kanagawa, GitHub Dark), `ThemedRoot`, `ThemeSwatch` |
| `Updater.swift` | Autoactualización desde GitHub Releases con SHA-256 |
| `Localization.swift` | Idiomas (en, es, ca): `tr()`, `Localizer`, tablas |
| `Icon/AppIcon.html` | Fuente del icono. `scripts/make-icon.sh` lo renderiza con Chrome headless y genera `Resources/AppIcon.icns` (versionado) e `Icon/AppIcon-1024.png` |

## Convenciones

- Código, comentarios y commits en inglés. Interfaz en castellano, inglés y catalán.
- **Todo texto visible pasa por `tr("…")`** (o `tr("… %@ …", arg)`). La clave es el texto en castellano; añadir la traducción a `en` y `ca` en `Localization.swift` con los mismos `%@`/`%d`. Nunca interpolar dentro de un texto traducible. Los nombres propios (temas, formatos) no se traducen.
- Estilo: usar `Theme` y sus componentes, nunca colores sueltos. Toda ventana nueva va dentro de `ThemedRoot { … }` (sigue el tema y el idioma).
- Estado de UI en tipos `@MainActor`; trabajo pesado (archivos, procesos) fuera del hilo principal.
- Borrar archivos del usuario = papelera (`trashItem`/`recycle`), nunca `removeItem`.
- El menú de la barra (o el de la app) mantiene siempre: Ajustes…, Buscar actualizaciones…, Invítame a un café… (`cup.and.saucer`), versión y Salir.
- Mantener el README al día (con capturas en `docs/`) cuando cambian funciones visibles.

## Arquitectura de Samune

Lanzador estilo Raycast, estudiado en clean-room (solo qué hace; ni código ni recursos suyos).

| Carpeta | Qué hay |
|---|---|
| `Search/` | Contratos compartidos: `ResultItem`, `ResultAction`, `ItemIcon`, `SearchProvider`, `ProviderResponse`; `SearchEngine` (reparte la consulta, mezcla y ordena, ejecuta acciones), `Fuzzy`, `Frecency`, `AppPaths`, `CommandsProvider` |
| `Panel/` | `LauncherController` (panel flotante + atajo global configurable) y `HotkeySettingsCard` |
| `Providers/` | `AppsProvider` (apps y paneles de Ajustes), `FilesProvider` (Spotlight; prefijo `f `), `SearchSettingsCard` |
| `Integrations/` | `IntegrationStore`, `IntegrationsProvider`, `IntegrationsSettingsCard`: carpetas con `manifest.json` + script que imprime JSON |
| `Calculator/` | `CalculatorProvider` (prioridad −10, va primero), `MathParser` (parser propio; nunca `NSExpression`, que lanza excepciones), `Units`, `ExchangeRates` (BCE, caché `rates.json`) |
| `Notes/` | Notity integrado: `NoteStore` (`notes.json`), `ClipboardWatcher` (doble ⌘C), `KeyWatcher`, `SavedBubble`, `NotesProvider` (prefijo `n `), `NotesController`, `NotesSettingsCard` |
| `Strings/` | Una tabla de traducciones por área (`PanelStrings`, `SearchStrings`, `IntegrationsStrings`, `CalculatorStrings`, `NotesStrings`); las comunes siguen en `Localization.swift` |

- Un proveedor recibe el texto tal cual y devuelve `ProviderResponse`; con `exclusive = true` («f informe», «bm laravel») solo se ven sus resultados.
- Orden: `priority` del proveedor (apps 0, comandos 5, integraciones 10, ficheros 20) y dentro, `score` (`Fuzzy.score` + `Frecency.boost`).
- Acciones: `SearchEngine.actions(for:)` da la lista única (principal, Finder, copiar y las `ItemAction` de la fila) que usan el menú ⌘K, el pie y las teclas. Las propias de un área van con `ResultAction.invoke(handler:argument:)` y se registran en `SearchEngine.shared.handlers`; `keepsPanelOpen` deja el panel abierto y vuelve a buscar.
- Campo vacío: `SearchProvider.suggestions()` de cada proveedor.
- Cada área guarda sus ajustes en su propio `ObservableObject` sobre `UserDefaults`; no se toca `Settings.swift`.
- Traducciones: `python3 scripts/check-translations.py` (mismas claves en `en` y `ca`, sin repetir, todo `tr()` traducido).

## Cosas que ya costaron (no repetir)

- **`NSHostingController`/`NSHostingView` redimensionan la ventana**: `sizingOptions = []`, `setContentSize` y después `setFrameAutosaveName`. En paneles hechos a mano, el `NSHostingView` con autoresizing y **sin Auto Layout**: con restricciones, `_changeWindowFrameFromConstraintsIfNecessary` impone el tamaño mínimo de SwiftUI.
- Nunca `setFrame(…, animate: true)` con SwiftUI dentro: da saltos. Cambiar el marco de golpe y animar el contenido.
- **`@Published` avisa en `willSet`**: un sink que redimensiona o repinta ahí ve el valor viejo y la vista se queda desfasada. Hacerlo en `DispatchQueue.main.async` o con `.receive(on: RunLoop.main)`.
- **Sin menú principal no funcionan ⌘C/⌘V/⌘A** en campos de texto de una app de barra de menús: `setupMainMenu()` lo crea aunque no se vea.
- Los `NSPanel` se esconden al desactivarse la app (`hidesOnDeactivate = false` si deben quedarse); un panel `.nonactivatingPanel` necesita `canBecomeKey` para escribir en él y `makeKey()` antes de enfocar un campo.
- Monitores globales: `NSEvent.addGlobalMonitorForEvents` de ratón no pide permisos; de teclado pide Accesibilidad. Atajos globales sin permisos: Carbon `RegisterEventHotKey`. ⌥⌘D está cogido (Dock).
- **Instalador con `curl | bash`**: con `set -u` y locale C, `"$NAME…"` hace que bash lea los bytes de «…» como parte del nombre → `unbound variable`. Usar siempre `${NAME}` pegado a texto no ASCII.
- **Abrir al iniciar sesión**: solo desde la copia de Aplicaciones (`LoginItem.enableOnceFromApplications`); desde `build/` registraría la de desarrollo. `open build/Samune.app --args -unregisterLoginItem YES` lo quita.
- La app no está notarizada (firma ad-hoc): los permisos de privacidad (Descargas, Accesibilidad…) pueden volver a pedirse tras cada actualización.
- Builds universales (`--arch arm64 --arch x86_64`) necesitan Xcode completo; `build-app.sh` cae a la arquitectura nativa con solo CLT.
- **Runners de GitHub**: `macos-14` ya no existe. En `macos-15` el job puede quedarse en cola; relanzar con `gh run rerun <id>`.
- **Varias copias de debug a la vez** (workers en worktrees) comparten `~/Library/Application Support/Samune` y el dominio `Samune`: aislar cada una con `CFFIXED_USER_HOME=<carpeta>` y no usar `pkill -f .build/debug/Samune` (mata las de los demás).
- **Copia de debug y actualizador**: sin `-autoCheckUpdates NO` sale el aviso modal de «hay actualización» y la app deja de contestar al gancho. Una integración con secreto en el Llavero también la bloquea (diálogo de permiso): probar con `hola`.
- **Tablas de traducción por área**: una clave solo puede estar en una tabla; si dos áreas la usan («Cancelar»), va en la común de `Localization.swift` o en una sola.
- `main.swift` envuelve el arranque en `MainActor.assumeIsolated` porque `AppDelegate` es `@MainActor`.

## Pruebas manuales

- **Gancho de depuración** (solo debug): `.build/debug/Samune` y `DistributedNotificationCenter` `com.egluu.samune.debug` con objeto `panel`, `hide`, `query:<texto>` (abre el panel con ese texto), `settings`, `theme:<id>` `integrations:<texto>|<archivo>`, `calc:<texto>|<archivo>`, `notes:seed|list|pin:<i>|trash:<i>|…` o, del panel, `act.query:<texto>`, `act.actions`, `act.down`, `act.key:<esc|return|cmd+delete|text:abc>`, `act.shot:<png>`. Añadir ahí los comandos que haga falta para llevar la app a cada estado sin ratón.
- **Capturas sin permisos**: el comando `shot:<carpeta>` del gancho guarda un PNG de cada ventana visible de la app (`cacheDisplay`). Es lo primero a usar: `screencapture -l` falla con «could not create image from window» si Terminal no tiene grabación de pantalla.
- **El sandbox de Bash** aísla el portapapeles y otras apps (`pbcopy`, `screencapture`, Chrome headless): esas pruebas, fuera del sandbox.
- **Capturas** (con permiso de grabación de pantalla): `screencapture -x -l <id de ventana>` saca solo la ventana, sin el escritorio. Los ids, con `CGWindowListCopyWindowInfo` filtrando por propietario `Samune`.
- El binario de debug usa el dominio de `UserDefaults` `Samune`, no `com.egluu.samune`, pero comparte `~/Library/Application Support/Samune`: hacer copia antes de probar y restaurarla después.
