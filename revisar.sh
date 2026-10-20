#!/usr/bin/env bash
# Auditoría automática de un proyecto TypeScript / Next.js / React (con Supabase opcional): la parte mecánica de la
# skill revision-de-codigo. Solo lee y reporta; no cambia nada.
#
# Modo auditor: todo lo que encuentra se muestra completo, sin recortar ni suavizar. Al final da un veredicto:
# NO APROBADO si hay algo crítico o alto (y sale con código 1, para poder usarlo en un hook o en CI).
#
# Uso, desde cualquier carpeta del repositorio:
#   bash revisar.sh            revisa lo que todavía no está guardado en git
#   bash revisar.sh <commit>   revisa todo lo cambiado desde ese commit
#
# Ajustes por proyecto (opcionales), en la raíz del repositorio:
#   .revision/excluir.txt   rutas que no se revisan, una por línea (por ejemplo ios, android, vendor)
#   .revision/restos.txt    patrones (expresiones regulares) que no deben quedar en el código, uno por línea
set -uo pipefail
RAIZ="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "No es un repositorio git."; exit 2; }
cd "$RAIZ" || exit 2
TEMPORAL="$(mktemp -d)"
trap 'rm -rf "$TEMPORAL"' EXIT
ESTA_CARPETA="$(cd "$(dirname "$0")" && pwd)"
ESTA_CARPETA="${ESTA_CARPETA#"$RAIZ"/}"

DESDE="${1:-}"
if [ -n "$DESDE" ]; then RANGO="$DESDE"; echo "== Cambios desde $DESDE"; else RANGO="HEAD"; echo "== Cambios sin guardar en git"; fi

# Lo que no se revisa: la carpeta .revision (sus patrones se marcarían a sí mismos), lo que diga
# .revision/excluir.txt y esta misma skill si vive dentro del repositorio. Si vive afuera (~/.claude/skills), no hace falta.
EXCLUIR=(.revision)
case "$ESTA_CARPETA" in /*) ;; *) EXCLUIR+=("$ESTA_CARPETA");; esac
if [ -f .revision/excluir.txt ]; then
  while IFS= read -r ruta; do [ -n "$ruta" ] && [ "${ruta:0:1}" != "#" ] && EXCLUIR+=("$ruta"); done < .revision/excluir.txt
fi
ESPECIFICACION=(.)
# (Bash 3.2, el de macOS, falla al expandir un arreglo vacío con set -u: por eso el ${EXCLUIR[@]+...}.)
for ruta in ${EXCLUIR[@]+"${EXCLUIR[@]}"}; do ESPECIFICACION+=(":(exclude)$ruta"); done
fuera() { local f="$1" ruta; for ruta in ${EXCLUIR[@]+"${EXCLUIR[@]}"}; do case "$f" in "$ruta"|"$ruta"/*) return 0;; esac; done; return 1; }

ARCHIVOS=""
while IFS= read -r f; do [ -n "$f" ] && ! fuera "$f" && ARCHIVOS+="$f"$'\n'; done < <( { git diff --name-only "$RANGO"; git ls-files --others --exclude-standard; } | sort -u )
CODIGO=$(printf '%s' "$ARCHIVOS" | grep -E '\.(ts|tsx|mts|cts|js|jsx|mjs|css|sql)$' || true)
printf '%s' "$ARCHIVOS" | sed 's/^/   /'

# Solo las líneas agregadas (más los archivos nuevos completos).
AGREGADO=$(git diff -U0 "$RANGO" -- "${ESPECIFICACION[@]}" | grep '^+' | grep -v '^+++' || true)
while IFS= read -r nuevo; do
  [ -n "$nuevo" ] && ! fuera "$nuevo" && [ -f "$nuevo" ] && AGREGADO+=$'\n'"$(sed 's/^/+/' "$nuevo")"
done < <(git ls-files --others --exclude-standard | grep -E '\.(ts|tsx|mts|cts|js|jsx|mjs|css|sql|sh|html)$' || true)
# Lo mismo, pero solo de archivos de código: los patrones de código no se buscan en la documentación (que los nombra).
# Los secretos sí se buscan en todo.
EXT_CODIGO='\.(ts|tsx|mts|cts|js|jsx|mjs|cjs|css|scss|sql|sh|html|vue|svelte|astro)$'
# La carpeta docs/ tampoco: guarda informes (por ejemplo HTML de escáneres) que nombran los patrones.
AGREGADO_CODIGO=$(git diff -U0 "$RANGO" --name-only -- "${ESPECIFICACION[@]}" | grep -E "$EXT_CODIGO" | grep -v '^docs/' | while IFS= read -r f; do git diff -U0 "$RANGO" -- "$f"; done | grep '^+' | grep -v '^+++' || true)
while IFS= read -r nuevo; do
  [ -n "$nuevo" ] && ! fuera "$nuevo" && [ -f "$nuevo" ] && AGREGADO_CODIGO+=$'\n'"$(sed 's/^/+/' "$nuevo")"
done < <(git ls-files --others --exclude-standard | grep -E "$EXT_CODIGO" | grep -v '^docs/' || true)

CRITICOS=0; ALTOS=0; MEDIOS=0; BAJOS=0
# Cada sección que termina sin hallazgos ni otra salida dice OK, para que se vea que sí se revisó.
EN_SECCION=0; SALIDA_ANTES=0
cerrar_seccion() { [ "$EN_SECCION" = 1 ] && [ $((CRITICOS + ALTOS + MEDIOS + BAJOS)) -eq "$SALIDA_ANTES" ] && [ "$IMPRESO" = 0 ] && decir "OK"; return 0; }
titulo() { cerrar_seccion; printf '\n== %s\n' "$1"; EN_SECCION=1; SALIDA_ANTES=$((CRITICOS + ALTOS + MEDIOS + BAJOS)); IMPRESO=0; }
IMPRESO=0
# Las secciones que imprimen algo propio (OK, se omite) lo marcan con decir.
decir() { echo "   $1"; IMPRESO=1; }
# hallazgo GRAVEDAD "qué pasa" ["recomendación"]: cada falla sale con cómo corregirla.
hallazgo() {
  case "$1" in CRITICO) CRITICOS=$((CRITICOS + 1));; ALTO) ALTOS=$((ALTOS + 1));; MEDIO) MEDIOS=$((MEDIOS + 1));; BAJO) BAJOS=$((BAJOS + 1));; esac
  printf '   [%s] %s\n' "$1" "$2"
  if [ -n "${3:-}" ]; then printf '      → Recomendación: %s\n' "$3"; fi
  return 0
}
mostrar() { sed 's/^/      /'; }
# Dónde busca regla: en el código agregado, salvo que antes se pida todo (EN_TODO=1, para los secretos).
EN_TODO=0
buscar() { if [ "$EN_TODO" = 1 ]; then printf '%s\n' "$AGREGADO"; else printf '%s\n' "$AGREGADO_CODIGO"; fi | grep -nE "$1" || true; }
# Un patrón en lo agregado: si aparece, un hallazgo con todas sus líneas y la recomendación que se haya dejado en
# RECOMENDACION justo antes de llamar.
RECOMENDACION=""
regla() {
  local gravedad="$1" texto="$2" patron="$3" excepto="${4:-}" encontrado
  encontrado=$(buscar "$patron")
  [ -n "$excepto" ] && encontrado=$(printf '%s\n' "$encontrado" | grep -vE "$excepto" || true)
  encontrado=$(printf '%s\n' "$encontrado" | grep -v '^$' || true)
  if [ -n "$encontrado" ]; then hallazgo "$gravedad" "$texto" "$RECOMENDACION"; printf '%s\n' "$encontrado" | mostrar; fi
  RECOMENDACION=""; EN_TODO=0
}
tiene_ts() { [ -f tsconfig.json ]; }

titulo "1. Tipos (tsc)"
if ! tiene_ts; then decir "Sin tsconfig.json: se omite"
elif npx --no-install tsc --noEmit -p . >"$TEMPORAL/tsc.txt" 2>&1; then decir "OK"
else hallazgo ALTO "el proyecto no compila:" "Corrige cada error de tipos; no lo silencies con any ni @ts-ignore."; mostrar < "$TEMPORAL/tsc.txt"; fi

titulo "2. Código sin usar en lo cambiado (tsc --noUnusedLocals --noUnusedParameters)"
if ! tiene_ts || [ -z "$CODIGO" ]; then decir "Se omite"
else
  npx --no-install tsc --noEmit --noUnusedLocals --noUnusedParameters -p . >"$TEMPORAL/sobra.txt" 2>&1
  SOBRA=$(grep -F -f <(printf '%s\n' "$CODIGO") "$TEMPORAL/sobra.txt" || true)
  if [ -z "$SOBRA" ]; then decir "OK"; else hallazgo MEDIO "código muerto: variables, importaciones o parámetros sin usar" "Bórralo. Si un parámetro es obligatorio por la firma, nómbralo con guion bajo al inicio."; printf '%s\n' "$SOBRA" | mostrar; fi
fi

titulo "3. Pruebas (npm test)"
if ! grep -q '"test"[[:space:]]*:' package.json 2>/dev/null; then hallazgo ALTO "el proyecto no tiene script de pruebas: nada demuestra que el cambio funcione" "Agrega un corredor de pruebas (node --test con tsx, o vitest) y pruebas para la lógica nueva."
elif npm test >"$TEMPORAL/pruebas.txt" 2>&1; then decir "OK"; grep -E '^(ℹ )?(tests|pass|fail|Tests:)' "$TEMPORAL/pruebas.txt" | sed 's/^/   /'
else hallazgo ALTO "las pruebas fallan:" "Corrige el código, no la prueba, salvo que la prueba esté mal y se explique por qué."; mostrar < "$TEMPORAL/pruebas.txt"; fi
LOGICA=$(printf '%s' "$CODIGO" | grep -E '\.(ts|mts|js|mjs)$' | grep -vE '\.test\.|\.d\.ts$|\.config\.' || true)
PRUEBAS_CAMBIADAS=$(printf '%s' "$ARCHIVOS" | grep -E '\.test\.' || true)
if [ -n "$LOGICA" ] && [ -z "$PRUEBAS_CAMBIADAS" ]; then hallazgo MEDIO "cambió lógica y no se tocó ninguna prueba:" "Escribe pruebas para el caso normal, los casos borde y el error de la lógica que cambió."; printf '%s\n' "$LOGICA" | mostrar; fi

titulo "4. Archivos de prueba que el script de pruebas no nombra"
# Solo aplica cuando el script "test" enumera los archivos uno por uno (por ejemplo "tsx --test a.test.ts b.test.ts").
# Con comodines (test/*.test.ts) o carpetas, el corredor las encuentra solas: no aplica.
SCRIPT_TEST=$(grep -oE '"test"[[:space:]]*:[[:space:]]*"[^"]*"' package.json 2>/dev/null || true)
if printf '%s' "$SCRIPT_TEST" | grep -qE '\.test\.' && ! printf '%s' "$SCRIPT_TEST" | grep -qE '\*'; then
  FALTAN=""
  while IFS= read -r prueba; do
    [ -n "$prueba" ] && ! fuera "$prueba" && ! grep -qF "$prueba" package.json && FALTAN+="$prueba "
  done < <( { git ls-files; git ls-files --others --exclude-standard; } | grep -E '\.test\.(ts|tsx|mts|js|mjs)$' | grep -v node_modules | sort -u )
  if [ -z "$FALTAN" ]; then decir "OK"; else hallazgo ALTO "estas pruebas nunca corren: $FALTAN" "Agrégalas al script test de package.json."; fi
else decir "El script de pruebas no enumera archivos: se omite"; fi

titulo "5. Secretos y archivos que no deben subirse"
RECOMENDACION="Sácalo del código y léelo de una variable de entorno o del gestor de secretos del servidor. Si ya llegó a git o a un servidor, revócalo y genera uno nuevo: borrarlo del archivo no basta."
EN_TODO=1
regla CRITICO "posible secreto en el código (no lo subas; si ya salió, cámbialo):" \
  'sb_secret_|service_role|SERVICE_ROLE_KEY=|eyJhbGciOi[A-Za-z0-9_-]{20,}|BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY|xkeysib-|xi-api-key|AIza[0-9A-Za-z_-]{30}|sk_live_|sk_test_|sk-[A-Za-z0-9_-]{20}|ghp_[A-Za-z0-9]{30}|github_pat_|xox[baprs]-|AKIA[0-9A-Z]{16}|(password|passwd|secret|api_?key|token)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']{8,}' \
  'process\.env|Deno\.env\.get|import\.meta\.env|placeholder|ejemplo|example'
SENSIBLES=$(printf '%s' "$ARCHIVOS" | grep -E '(^|/)\.env($|\.)|\.pem$|\.p8$|\.p12$|\.key$|\.jks$|\.keystore$|id_rsa|id_ed25519|\.sqlite$|\.db$|\.dump$' | grep -v '\.env\.example$' || true)
if [ -n "$SENSIBLES" ]; then hallazgo CRITICO "archivos sensibles a punto de entrar a git:" "Agrégalos a .gitignore y sácalos del índice. Si ya se subieron, cambia las claves que tengan."; printf '%s\n' "$SENSIBLES" | mostrar; fi
GRANDES=$(printf '%s' "$ARCHIVOS" | while IFS= read -r f; do [ -f "$f" ] && [ "$(wc -c < "$f")" -gt 1000000 ] && echo "$f ($(( $(wc -c < "$f") / 1024 )) KB)"; done)
if [ -n "$GRANDES" ]; then hallazgo MEDIO "archivos de más de 1 MB en el cambio:" "Comprime las imágenes (WebP o AVIF), sirve los videos desde un almacenamiento aparte y no subas compilados."; printf '%s\n' "$GRANDES" | mostrar; fi

titulo "6. Patrones peligrosos"
RECOMENDACION="Muestra el texto como texto (React ya lo escapa). Si de verdad hace falta HTML, límpialo con una librería probada (DOMPurify) y nunca ejecutes texto como código."
regla ALTO "HTML inyectado o código dinámico (confirmar que nada venga de una persona):" 'dangerouslySetInnerHTML|\.innerHTML[[:space:]]*\+?=|outerHTML[[:space:]]*=|insertAdjacentHTML|eval\(|new Function\(|document\.write|setTimeout\([[:space:]]*["'"'"'`]'
RECOMENDACION="Valida que la URL empiece con https:// (o sea una ruta propia) antes de abrirla, y nunca armes enlaces con datos que escribe una persona."
regla ALTO "URL javascript: o window.open/location con datos variables:" 'href=["'"'"'{`]*javascript:|window\.open\([^)]*\$\{|location(\.href)?[[:space:]]*=[^=][^;]*\$\{'
RECOMENDACION="Usa parámetros del cliente de la base o funciones con argumentos; en PL/pgSQL, format() con %I y %L. Nunca concatenes lo que escribe una persona."
regla ALTO "SQL armado con texto (inyección):" '([Ss][Ee][Ll][Ee][Cc][Tt][[:space:]][^;]*[[:space:]][Ff][Rr][Oo][Mm][[:space:]]|[Ii][Nn][Ss][Ee][Rr][Tt][[:space:]]+[Ii][Nn][Tt][Oo][[:space:]]|[Uu][Pp][Dd][Aa][Tt][Ee][[:space:]]+[A-Za-z_."]+[[:space:]]+[Ss][Ee][Tt][[:space:]]|[Dd][Ee][Ll][Ee][Tt][Ee][[:space:]]+[Ff][Rr][Oo][Mm][[:space:]])[^;]*\$\{|\.(rpc|query|raw|prepare|exec)\([^)]*\+[[:space:]]*[a-zA-Z_]|execute[[:space:]]+[^;]*\|\|' 'format\(.*%I|quote_ident|quote_literal|\$(queryRaw|executeRaw)(<[^`]*>)?`|[^A-Za-z_]sql`|Prisma\.sql'
RECOMENDACION="Guarda sesiones y claves en el almacenamiento seguro del sistema (Keychain o Keystore) o en cookies httpOnly; el almacenamiento del navegador lo lee cualquier script de la página."
regla ALTO "datos sensibles en almacenamiento del navegador:" '(localStorage|sessionStorage)\.setItem\([^)]*(clave|password|contrase|token|secret|session)'
RECOMENDACION="Compara event.origin con una lista de orígenes permitidos antes de usar el mensaje."
regla ALTO "postMessage sin comprobar el origen:" 'addEventListener\([[:space:]]*["'"'"']message["'"'"']' 'origin|[Ss]ocket|ws\.|[Ww]orker'
RECOMENDACION="Devuelve solo los orígenes propios, comparados contra una lista, y agrega Vary: Origin."
regla ALTO "CORS abierto a cualquiera:" 'Access-Control-Allow-Origin["'"'"']?[[:space:]]*[:,][[:space:]]*["'"'"']\*'
RECOMENDACION="Usa crypto.randomUUID() o crypto.getRandomValues()."
regla ALTO "Math.random para identificadores, claves o tokens (es predecible):" 'Math\.random\(\)' '(anim|jitter|retras|espera|delay|color|demo|shuffle|baraj)'
RECOMENDACION="Cambia a https://. Si el sitio no tiene https, no lo enlaces."
regla MEDIO "enlaces a http:// sin cifrar:" 'http://[^l1[:space:]"'"'"']' 'localhost|127\.0\.0\.1|www\.w3\.org|xmlns'
RECOMENDACION="Agrega rel=noopener noreferrer."
regla MEDIO "target=_blank sin rel=noopener en la misma línea (confirmar si está en la siguiente):" 'target=["'"'"'{]*_blank' 'noopener|noreferrer'
RECOMENDACION="Quítalas. Si hace falta registrar algo, que sea sin datos personales y con un registrador que se apague en producción."
regla MEDIO "salidas de depuración:" 'console\.(log|debug|trace)\(|debugger'
RECOMENDACION="Corrige el tipo o la regla en vez de apagarla. Si es inevitable, deja un comentario con el porqué y la fecha."
regla MEDIO "se apagan las comprobaciones del compilador o del linter:" '@ts-ignore|@ts-nocheck|@ts-expect-error|eslint-disable'
RECOMENDACION="Declara el tipo real o valida el dato al entrar (por ejemplo con un esquema) y deja que el compilador avise."
regla MEDIO "tipos que esconden errores (any, conversiones forzadas):" ':[[:space:]]*any\b|as any\b|<any>|as unknown as'
RECOMENDACION="Avisa a la persona, reintenta o registra el error. Si ignorarlo es correcto, comenta por qué."
regla MEDIO "errores tragados sin hacer nada:" 'catch[[:space:]]*(\([^)]*\))?[[:space:]]*\{[[:space:]]*\}|\.catch\(\(\)[[:space:]]*=>[[:space:]]*(\{\}|undefined|null)\)'
RECOMENDACION="Agrega .catch() con un aviso o espera la promesa: un rechazo sin manejar se pierde en silencio."
regla BAJO "promesas lanzadas sin esperar (void): confirmar que un fallo no se pierde:" '^\+[[:space:]]*void [a-zA-Z_.]+\('

titulo "7. Base de datos (SQL cambiado)"
SQL=$(printf '%s' "$ARCHIVOS" | grep '\.sql$' || true)
if [ -z "$SQL" ]; then decir "Sin cambios de SQL"; else
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    # Un archivo para deshacer un cambio devuelve a propósito el estado anterior: no se juzga con estas reglas.
    case "$f" in *revertir*|*revert*|*rollback*|*/down.sql|*.down.sql) decir "$f (archivo para deshacer: se omite)"; continue;; esac
    decir "$f"
    # RLS puede activarse en otro archivo (por ejemplo db/rls.sql), tabla por tabla o recorriendo una lista de nombres:
    # cuenta como activada si la tabla aparece en algún archivo SQL del repositorio que active RLS.
    SIN_RLS=""
    ARCHIVOS_RLS=$(git grep -liE 'enable row level security' -- '*.sql' 2>/dev/null | grep -vE 'revertir|revert|rollback|down\.sql' || true)
    for tabla in $(grep -oiE 'create table[[:space:]]+(if not exists[[:space:]]+)?[A-Za-z0-9_."]+' "$f" | awk '{print $NF}' | tr -d '"' | sed 's/.*\.//'); do
      con_rls=0
      while IFS= read -r a; do
        [ -n "$a" ] && grep -qiE "(^|[^a-z0-9_])$tabla([^a-z0-9_]|$)" "$a" && con_rls=1 && break
      done <<< "$ARCHIVOS_RLS"
      [ "$con_rls" = 1 ] || SIN_RLS+="$tabla "
    done
    if [ -n "$SIN_RLS" ]; then hallazgo CRITICO "$f crea tablas sin RLS en ningún archivo del repositorio: $SIN_RLS" "alter table ... enable row level security, y reglas que solo dejen ver y cambiar lo propio."; fi
    if grep -qiE 'disable row level security|no force row level security' "$f"; then hallazgo CRITICO "$f apaga RLS" "No la apagues. Si un proceso necesita saltarla, usa una función security definer acotada."; fi
    definer=$(grep -ci 'security definer' "$f"); fijo=$(grep -ci 'set search_path' "$f")
    if [ "$definer" -gt "$fijo" ]; then hallazgo ALTO "$f: funciones security definer sin search_path fijo ($definer definer, $fijo search_path)" "Agrega set search_path a cada función security definer (vacío, calificando las tablas con su esquema)."; fi
    if grep -qiE 'grant[^;]*to[^;]*\banon\b' "$f"; then hallazgo ALTO "$f da permisos a anon (visitantes sin sesión): justificar cada uno" "Quita los que no hagan falta antes de iniciar sesión."; fi
    if grep -qiE 'using[[:space:]]*\([[:space:]]*true[[:space:]]*\)|with check[[:space:]]*\([[:space:]]*true[[:space:]]*\)' "$f"; then hallazgo ALTO "$f tiene reglas con true: dejan leer o escribir todas las filas" "Cambia true por una condición sobre el usuario, como auth.uid() = dueño."; fi
    if grep -qi 'security definer' "$f" && ! grep -qiE 'revoke[^;]*from[^;]*public' "$f"; then hallazgo ALTO "$f crea funciones security definer sin revocar el permiso por omisión a public" "revoke all on function ... from public, anon; y luego grant execute solo a quien la use."; fi
    if grep -qi 'create table' "$f" && ! grep -qiE 'trigger|check[[:space:]]*\(' "$f"; then hallazgo MEDIO "$f: tabla nueva sin disparadores ni checks en el mismo archivo: confirmar topes contra inserciones masivas y límites de largo" "Agrega un disparador con tope por usuario y por hora, con la fecha puesta por el servidor, y checks de largo."; fi
    if grep -qiE 'drop (table|column)|truncate|delete from [a-z_.]+[[:space:]]*;' "$f"; then hallazgo ALTO "$f borra datos o estructura: exige respaldo y plan para revertir" "Respalda la base antes, prueba en un entorno de prueba y deja listo el script para deshacerlo."; fi
    if grep -qiE '\btext\b' "$f" && ! grep -qiE 'char_length|length\(|octet_length' "$f"; then hallazgo MEDIO "$f tiene columnas text sin límite de largo" "Agrega check (char_length(columna) <= N) con un N razonable."; fi
  done <<< "$SQL"
fi

titulo "8. Accesibilidad"
RECOMENDACION="Agrega alt con lo que muestra la imagen, o alt vacío si es decorativa."
regla ALTO "imágenes sin texto alternativo:" '<img([[:space:]]|$)' 'alt='
RECOMENDACION="Usa :focus-visible con un contorno de al menos 2 px y buen contraste."
regla ALTO "foco oculto (quien usa teclado no ve dónde está):" 'outline:[[:space:]]*(none|0)' 'focus-visible'
RECOMENDACION="Agrega aria-label con lo que hace el botón, y aria-hidden al ícono."
regla ALTO "botón con solo ícono y sin aria-label:" '<button[^>]*>[[:space:]]*<svg' 'aria-label'
RECOMENDACION="Usa un button. Si no se puede, agrega role, tabIndex y manejo de Enter y Espacio."
regla MEDIO "clic en un div o span (no funciona con teclado ni lector de pantalla):" '<(div|span)[^>]*onClick' 'role="(presentation|dialog|button)"'
RECOMENDACION="Pon un label visible unido al campo (htmlFor e id). El placeholder no sirve como etiqueta."
regla MEDIO "campos sin etiqueta visible o aria-label:" '<input[^>]*type="(text|email|password|number|tel|search)"' 'aria-label|id='
RECOMENDACION="Usa al menos 12 px (0,75 rem) en textos secundarios y 16 px en campos de formulario, para que el iPhone no haga zoom."
regla MEDIO "letra de menos de 12 px:" 'font-size:[[:space:]]*(([0-9]|1[01])px|0\.[0-6][0-9]*rem)'
RECOMENDACION="Envuelve la animación en @media (prefers-reduced-motion: no-preference) o quítala dentro de reduce."
regla BAJO "movimiento: confirmar que respeta prefers-reduced-motion:" '(animation|transition):' 'none'
RECOMENDACION="Usa las variables del tema y mide el contraste (4,5:1 en texto normal) en claro y en oscuro."
regla BAJO "colores escritos a mano (fuera de las variables del tema): confirmar contraste en claro y oscuro:" '#[0-9a-fA-F]{3,8}\b|rgb\(' 'var\(--|^\+[[:space:]]*--'

titulo "9. Dependencias"
if [ ! -f package-lock.json ]; then decir "Sin package-lock.json: se omite"
elif npm audit --omit=dev >"$TEMPORAL/audit.txt" 2>&1; then decir "OK"
else hallazgo ALTO "vulnerabilidades en dependencias de producción:" "Actualiza a la versión corregida. Si exige un cambio grande, evalúa si la falla te alcanza y anota la decisión con fecha."; mostrar < "$TEMPORAL/audit.txt"; fi
if printf '%s' "$ARCHIVOS" | grep -qx 'package.json'; then
  NUEVAS=$(git diff "$RANGO" -- package.json | grep -E '^\+[[:space:]]*"[^"]+":[[:space:]]*"[~^]?[0-9]' | grep -v '"version"' || true)
  if [ -n "$NUEVAS" ]; then hallazgo MEDIO "dependencias nuevas o cambiadas: revisar quién las mantiene, licencia y qué permisos o red usan:" "Prefiere librerías mantenidas y con licencia compatible. Fija la versión y revisa que no envíe datos a terceros."; printf '%s\n' "$NUEVAS" | mostrar; fi
fi

titulo "10. Pendientes y restos de pruebas manuales"
PATRONES='(^|[^[:alnum:]_])(TODO|FIXME|XXX|HACK)([^[:alnum:]_]|$)|\.only\(|\.skip\('
if [ -f .revision/restos.txt ]; then
  while IFS= read -r p; do [ -n "$p" ] && [ "${p:0:1}" != "#" ] && PATRONES+="|$p"; done < .revision/restos.txt
fi
RECOMENDACION="Termina el pendiente o anótalo como tarea. Reactiva la prueba y quita los interruptores de prueba manual antes de publicar."
regla ALTO "pendientes, pruebas desactivadas o restos de pruebas manuales:" "$PATRONES"

cerrar_seccion
printf '\n== VEREDICTO\n   críticos: %s · altos: %s · medios: %s · bajos: %s\n' "$CRITICOS" "$ALTOS" "$MEDIOS" "$BAJOS"
if [ $((CRITICOS + ALTOS)) -gt 0 ]; then
  decir "NO APROBADO: hay hallazgos críticos o altos. No se publica hasta corregirlos o justificar cada uno por escrito."
  exit 1
fi
decir "APROBADO por la parte automática. Falta la lectura con criterio (SKILL.md, paso 2): el script no ve la lógica."
