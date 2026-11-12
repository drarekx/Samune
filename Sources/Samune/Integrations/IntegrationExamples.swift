import Foundation

/// Integrations bundled with the app, written to `AppPaths.integrations` the first time it runs.
/// `hola` is also the template for "Nueva integración…".
enum IntegrationExamples {
    struct Example {
        let id: String
        let manifest: String
        let script: String
    }

    static let all = [hola, bookmarks]

    static let hola = Example(id: "hola", manifest: holaManifest, script: holaScript)
    static let bookmarks = Example(id: "bookmarks", manifest: bookmarksManifest, script: bookmarksScript)

    static let scriptName = "run.sh"

    private static let holaManifest = #"""
{
  "name": "Hola",
  "keyword": "hola",
  "icon": "hand.wave",
  "command": "./run.sh",
  "passQuery": false,
  "cacheSeconds": 300,
  "description": "Ejemplo y plantilla: abre una web, copia un texto y abre la Calculadora."
}
"""#

    static let holaScript = #"""
#!/bin/bash
# Integración de ejemplo de Samune: la plantilla para hacer las tuyas.
#
# Samune ejecuta este script desde su carpeta (con /bin/zsh -lc) y lee lo que
# imprime: un JSON con una lista de elementos. Puede estar escrito en cualquier
# lenguaje (bash, node, python, php…) mientras imprima ese JSON.
#
# Lo que recibe:
#   $1 / $SAMUNE_QUERY       el texto escrito tras la palabra clave. Con
#                            "passQuery": false en manifest.json siempre llega
#                            vacío: Samune guarda la lista y la filtra él solo.
#   $SAMUNE_INTEGRATION_DIR  la carpeta de esta integración.
#   Las variables declaradas en "variables" del manifest.json, con el valor
#   que les des en Ajustes → Integraciones.
#
# Lo que imprime:
#   { "items": [ { "title": "…", "subtitle": "…", "icon": "sf:star",
#                  "action": { "type": "open", "value": "https://…" },
#                  "copy": "texto para ⌘C" } ] }
#
#   icon: "sf:<símbolo>" (SF Symbols), una ruta a una imagen (absoluta o
#         relativa a esta carpeta) o una URL http(s). Sin icono se usa el de
#         la integración.
#   action.type: "open" abre una URL o un archivo, "copy" copia el texto y
#         "run" ejecuta un comando de shell desde esta carpeta.
#
# Si algo va mal, imprime { "error": "mensaje corto" } y Samune lo mostrará.
# Tiene 10 segundos para terminar y la salida no puede pasar de 5 MB.

cat <<'JSON'
{
  "items": [
    {
      "title": "Abrir la web de Samune",
      "subtitle": "Acción open: abre una URL o un archivo",
      "icon": "sf:safari",
      "action": { "type": "open", "value": "https://github.com/drarekx/Samune" }
    },
    {
      "title": "Copiar un saludo",
      "subtitle": "Acción copy: copia el texto al portapapeles",
      "icon": "sf:doc.on.doc",
      "action": { "type": "copy", "value": "¡Hola desde Samune!" }
    },
    {
      "title": "Abrir la Calculadora",
      "subtitle": "Acción run: ejecuta un comando de shell",
      "icon": "sf:plus.forwardslash.minus",
      "action": { "type": "run", "value": "open -a Calculator" }
    }
  ]
}
JSON
"""#

    private static let bookmarksManifest = #"""
{
  "name": "Bookmarks",
  "keyword": "bm",
  "icon": "bookmark",
  "command": "./run.sh",
  "passQuery": true,
  "cacheSeconds": 60,
  "description": "Busca en tu servidor de marcadores (Laravel).",
  "variables": [
    { "key": "BOOKMARKS_URL", "label": "URL del servidor", "placeholder": "https://…", "secret": false },
    { "key": "BOOKMARKS_TOKEN", "label": "API key", "secret": true }
  ]
}
"""#

    private static let bookmarksScript = #"""
#!/bin/bash
# Busca en tu servidor de marcadores (Laravel) desde Samune: escribe «bm texto».
#
# Variables (Ajustes → Integraciones → Bookmarks):
#   BOOKMARKS_URL    dirección del servidor, por ejemplo https://marcadores.ejemplo.com
#   BOOKMARKS_TOKEN  API key (se guarda en el Llavero, nunca en un archivo)
#
# Con texto llama a  GET $BOOKMARKS_URL/api/bookmarks/search?q=<texto>&per_page=20
# sin texto, a       GET $BOOKMARKS_URL/api/bookmarks  (los últimos)
# y convierte la respuesta paginada de Laravel ({ "data": [ … ] }) en elementos.
#
# Solo usa lo que trae cualquier macOS: curl y JavaScript para Automatización
# (osascript -l JavaScript) para leer el JSON.

query="$1"

fail() {
  # Escapa comillas y barras para que el mensaje sea JSON válido.
  local message=${1//\\/\\\\}
  message=${message//\"/\\\"}
  printf '{ "error": "%s" }\n' "${message}"
  exit 0
}

if [ -z "${BOOKMARKS_URL}" ] || [ -z "${BOOKMARKS_TOKEN}" ]; then
  fail "Configura la URL y la API key en Ajustes → Integraciones"
fi

base="${BOOKMARKS_URL%/}"
body="$(mktemp -t samune-bookmarks)"
trap 'rm -f "${body}"' EXIT

# La API key va por la entrada estándar (curl -K -), no como argumento,
# para que no se vea en la lista de procesos.
token=${BOOKMARKS_TOKEN//\\/\\\\}
token=${token//\"/\\\"}
headers="header = \"Authorization: Bearer ${token}\""

if [ -n "${query}" ]; then
  status=$(printf '%s\n' "${headers}" | /usr/bin/curl -sS -K - --max-time 8 -G \
    -H "Accept: application/json" \
    --data-urlencode "q=${query}" --data "per_page=20" \
    -o "${body}" -w '%{http_code}' "${base}/api/bookmarks/search" 2>"${body}.err")
else
  status=$(printf '%s\n' "${headers}" | /usr/bin/curl -sS -K - --max-time 8 \
    -H "Accept: application/json" \
    -o "${body}" -w '%{http_code}' "${base}/api/bookmarks" 2>"${body}.err")
fi
curl_status=$?
curl_error="$(head -n 1 "${body}.err" 2>/dev/null)"
rm -f "${body}.err"

if [ "${curl_status}" -ne 0 ] || [ "${status}" = "000" ]; then
  fail "Sin conexión con el servidor: ${curl_error:-error de red}"
fi
case "${status}" in
  401) fail "API key no válida" ;;
  2??) ;;
  *) fail "El servidor respondió HTTP ${status}" ;;
esac

/usr/bin/osascript -l JavaScript - "${body}" <<'JS'
ObjC.import('Foundation')

function run(argv) {
  const text = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null)
  let page
  try {
    page = JSON.parse(ObjC.unwrap(text) || '')
  } catch (e) {
    return JSON.stringify({ error: 'El servidor no devolvió JSON' })
  }
  const list = Array.isArray(page) ? page : (page && Array.isArray(page.data) ? page.data : [])
  const items = list.filter(b => b && b.url).map(b => {
    const match = /^[a-z][a-z0-9+.-]*:\/\/(?:[^@\/?#]*@)?([^\/?#:]+)/i.exec(b.url)
    const host = match ? match[1].replace(/^www\./, '') : ''
    const tags = (Array.isArray(b.tags) ? b.tags : [])
      .map(t => (typeof t === 'string' ? t : (t && t.name)))
      .filter(Boolean)
      .map(t => '#' + t)
      .join(', ')
    return {
      title: b.title || b.url,
      subtitle: [host, tags].filter(Boolean).join(' · '),
      icon: 'sf:bookmark',
      action: { type: 'open', value: b.url },
      copy: b.url
    }
  })
  return JSON.stringify({ items: items })
}
JS
"""#
}
