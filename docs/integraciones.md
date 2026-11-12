# Integraciones de Samune

Una integración lleva el contenido de un servicio tuyo al lanzador: escribes su palabra clave y un espacio (`bm laravel`) y Samune solo enseña lo que devuelve. Es una carpeta con un `manifest.json` y un script en el lenguaje que quieras (bash, node, python, php…) que imprime JSON. No hace falta recompilar nada.

Las integraciones viven en:

```
~/Library/Application Support/Samune/Integrations/<id>/
├── manifest.json
├── run.sh
└── icon.png        (opcional)
```

El nombre de la carpeta es el identificador de la integración. Para abrirla: **Ajustes → Integraciones → Abrir carpeta de integraciones**, o escribe «carpeta de integraciones» en el lanzador.

## Crear una

1. **Ajustes → Integraciones → Nueva integración…**, escribe un nombre y pulsa **Crear**.
2. Samune crea la carpeta a partir de la plantilla «Hola» (con una palabra clave sacada del nombre) y la abre en el Finder.
3. Edita `manifest.json` y `run.sh`.
4. Pulsa **Recargar** (o escribe «recargar integraciones» en el lanzador) y luego **Probar**: verás «N elementos» o el error.

También puedes copiar a mano cualquier carpeta de ejemplo con otro nombre.

## manifest.json

```json
{
  "name": "Bookmarks",
  "keyword": "bm",
  "icon": "bookmark",
  "command": "./run.sh",
  "passQuery": true,
  "cacheSeconds": 300,
  "description": "Busca en tu servidor de marcadores.",
  "variables": [
    { "key": "BOOKMARKS_URL", "label": "URL del servidor", "placeholder": "https://…", "secret": false },
    { "key": "BOOKMARKS_TOKEN", "label": "API key", "secret": true }
  ]
}
```

| Campo | Obligatorio | Qué hace |
|---|---|---|
| `name` | sí | Nombre en el lanzador y en Ajustes. |
| `keyword` | sí | Lo que se escribe antes de un espacio para entrar. Sin espacios; no distingue mayúsculas. Si dos integraciones usan la misma, la segunda (por orden alfabético de nombre) queda desactivada con un aviso. |
| `command` | sí | Se ejecuta con `/bin/zsh -lc` desde la carpeta de la integración. El texto de la búsqueda se añade al final, entre comillas, como `$1`. |
| `icon` | no | Nombre de un [SF Symbol](https://developer.apple.com/sf-symbols/) o de un archivo de imagen de la carpeta (`icon.png`). Por defecto, `puzzlepiece.extension`. |
| `passQuery` | no | `true`: el script recibe el texto y busca él (en un servidor, por ejemplo). `false` (por defecto): el script se ejecuta sin texto, Samune guarda la lista y la filtra mientras escribes. |
| `cacheSeconds` | no | Cuánto tiempo se reutiliza la salida, en segundos (300 por defecto). Con `passQuery`, cada texto tiene su propia caché. `0` la desactiva. |
| `description` | no | Se muestra en Ajustes. |
| `variables` | no | Valores que se rellenan en Ajustes y llegan al script como variables de entorno. `secret: true` los guarda en el Llavero. |

Si el manifiesto no es JSON válido o le falta un campo obligatorio, la integración aparece en Ajustes con el error en amarillo y no se usa.

## Lo que recibe el script

| Qué | Valor |
|---|---|
| `$1` | Texto escrito tras la palabra clave (vacío si no hay, o siempre vacío con `"passQuery": false`). |
| `SAMUNE_QUERY` | El mismo texto. |
| `SAMUNE_INTEGRATION_DIR` | Ruta de la carpeta de la integración (también es el directorio actual). |
| Cada `key` de `variables` | El valor guardado en Ajustes (no se define si está vacío). |
| El resto | El entorno de Samune y el de un shell de inicio de sesión de zsh (`~/.zprofile`), así que el `PATH` de Homebrew suele estar disponible. |

Con `passQuery: true`, Samune espera 250 ms desde la última tecla antes de ejecutar y, si sigues escribiendo, termina el proceso anterior. Con texto vacío también se ejecuta, por si quieres enseñar los elementos recientes.

## Lo que imprime el script

Un objeto JSON por la salida estándar:

```json
{
  "items": [
    {
      "title": "Eloquent ORM",
      "subtitle": "laravel.com · #laravel, #php",
      "icon": "sf:bookmark",
      "action": { "type": "open", "value": "https://laravel.com/docs/eloquent" },
      "copy": "https://laravel.com/docs/eloquent"
    }
  ]
}
```

- `title` es obligatorio; los elementos sin título se saltan. También vale imprimir directamente la lista (`[ … ]`).
- `subtitle`: segunda línea, opcional.
- `icon`: `sf:<símbolo>`, una ruta a una imagen (absoluta, con `~` o relativa a la carpeta) o una URL `http(s)`. Sin icono se usa el de la integración.
- `action.type`:
  - `open`: abre una URL (`https://…`, `mailto:…`, `obsidian://…`) o un archivo (ruta absoluta, con `~` o relativa a la carpeta). Con un archivo, ⌘↩ lo muestra en el Finder.
  - `copy`: copia `value` al portapapeles.
  - `run`: ejecuta `value` con `/bin/zsh -lc` desde la carpeta de la integración.
  - Sin acción, ↩ copia `copy` o, si no hay, el título.
- `copy`: texto que copia ⌘C (por defecto, la URL o la ruta de la acción).

Con `passQuery: true` los elementos se enseñan en el orden en que los imprimes; con `false`, ordenados por cómo encajan con lo escrito y por lo que más usas. Como mucho se muestran 50.

### Errores

Si algo va mal, imprime:

```json
{ "error": "API key no válida" }
```

Samune lo muestra como una sola fila «Nombre: mensaje»; ↩ copia el mensaje completo. También se convierten en esa fila: un código de salida distinto de 0 (con la primera línea de lo que el script escribió en stderr), una salida que no es JSON, una salida vacía, pasar del tiempo límite o del tamaño máximo.

## Límites

- **10 segundos** por ejecución. Después Samune termina el proceso (y lo mata si no responde).
- **5 MB** de salida. Por encima se corta y se muestra un error.
- Los resultados se guardan en memoria; **Recargar** los borra, y cambiar una variable borra los de esa integración.

## Secretos

- Las variables normales se guardan en las preferencias de Samune.
- Las de `"secret": true` se guardan en el **Llavero de macOS** (contraseña genérica, servicio `com.egluu.samune.integrations`, cuenta `<id>.<KEY>`). Ajustes nunca vuelve a enseñarlas: solo indica «••••» si hay una guardada. Para cambiarla, escribe la nueva y pulsa ↩ o **Guardar**; la papelera la borra.
- Samune no las escribe en ningún archivo ni en el registro: solo las pasa como variable de entorno al script.
- Como Samune no está notarizada, macOS puede volver a pedir permiso para leer el Llavero después de una actualización.
- Dentro del script, evita pasar el secreto como argumento de otro programa (se vería en la lista de procesos). El ejemplo de marcadores se lo da a `curl` por la entrada estándar.

## Ejemplos incluidos

Samune los instala la primera vez que se abre (si borras la carpeta, no vuelven a aparecer). Puedes desactivarlos en Ajustes.

### Hola (`hola`)

La plantilla: un script de bash comentado que imprime tres elementos, uno por acción.

```json
{
  "name": "Hola",
  "keyword": "hola",
  "icon": "hand.wave",
  "command": "./run.sh",
  "passQuery": false,
  "cacheSeconds": 300,
  "description": "Ejemplo y plantilla: abre una web, copia un texto y abre la Calculadora."
}
```

```bash
#!/bin/bash
cat <<'JSON'
{
  "items": [
    { "title": "Abrir la web de Samune", "icon": "sf:safari",
      "action": { "type": "open", "value": "https://github.com/drarekx/Samune" } },
    { "title": "Copiar un saludo", "icon": "sf:doc.on.doc",
      "action": { "type": "copy", "value": "¡Hola desde Samune!" } },
    { "title": "Abrir la Calculadora", "icon": "sf:plus.forwardslash.minus",
      "action": { "type": "run", "value": "open -a Calculator" } }
  ]
}
JSON
```

Escribe `hola calc` y verás solo «Abrir la Calculadora».

### Bookmarks (`bm`)

Busca en un servidor de marcadores hecho con Laravel. `passQuery: true`, `cacheSeconds: 60`.

1. En **Ajustes → Integraciones → Bookmarks → Variables**, rellena la **URL del servidor** (`BOOKMARKS_URL`) y la **API key** (`BOOKMARKS_TOKEN`, va al Llavero).
2. Escribe `bm` y un espacio: salen los últimos marcadores. Escribe `bm laravel` para buscar.

Qué hace el script:

- Con texto: `GET $BOOKMARKS_URL/api/bookmarks/search?q=<texto>&per_page=20`. Sin texto: `GET $BOOKMARKS_URL/api/bookmarks`.
- Cabeceras `Authorization: Bearer $BOOKMARKS_TOKEN` y `Accept: application/json`; máximo 8 segundos.
- Lee la respuesta paginada de Laravel (`{ "data": [ { "url", "title", "tags": [ { "name" } ], … } ] }`) y crea un elemento por marcador: el título (o la URL si no tiene), el dominio y las etiquetas como `#etiqueta`, ↩ abre la URL y ⌘C la copia.
- Errores: sin URL o sin API key, «Configura la URL y la API key en Ajustes → Integraciones»; HTTP 401, «API key no válida»; sin conexión, el error de `curl`.
- Solo usa lo que trae cualquier Mac, sin Xcode ni Homebrew: `curl` para la petición y JavaScript para Automatización (`osascript -l JavaScript`) para leer el JSON. (`/usr/bin/python3` no sirve: sin las herramientas de desarrollo es solo un instalador.)

## Un ejemplo en otro lenguaje

Una integración en node que lista los proyectos de una carpeta y los abre en VS Code (`passQuery: false`, así que Samune filtra):

```json
{ "name": "Proyectos", "keyword": "p", "icon": "folder", "command": "node list.js", "cacheSeconds": 600 }
```

```js
// list.js
const fs = require('fs'), path = require('path'), os = require('os')
const root = path.join(os.homedir(), 'dev')
const items = fs.readdirSync(root, { withFileTypes: true })
  .filter(d => d.isDirectory())
  .map(d => ({
    title: d.name,
    subtitle: path.join('~/dev', d.name),
    icon: 'sf:folder',
    action: { type: 'run', value: `code "${path.join(root, d.name)}"` },
    copy: path.join(root, d.name)
  }))
console.log(JSON.stringify({ items }))
```

`node` se encuentra si está en el `PATH` de tu `~/.zprofile`; si no, pon la ruta completa en `command` (`/opt/homebrew/bin/node list.js`).
