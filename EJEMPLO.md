# Ejemplo de auditoría

Este ejemplo es real. Se armó un proyecto pequeño de demostración, una tienda con un archivo de pedidos y una migración SQL, con fallas puestas a propósito, y se corrió la skill sobre él. Abajo está la salida del script tal cual y, después, el reporte que entrega Claude al leer el cambio con criterio.

## El cambio auditado

- `src/pedidos.js`: busca pedidos por correo, muestra la nota del cliente, genera un código de recuperación, guarda la sesión y dibuja un botón de cerrar.
- `src/precio.mjs`: agrega `precioConDescuento(valor, pct)`.
- `db/pedidos.sql`: crea la tabla `pedidos`, una función `total_de` y una regla de lectura.

## Paso 1: salida de `revisar.sh`

```
== Cambios sin guardar en git
   db/pedidos.sql
   src/pedidos.js
   src/precio.mjs

== 1. Tipos (tsc)
   Sin tsconfig.json: se omite

== 2. Código sin usar en lo cambiado (tsc --noUnusedLocals --noUnusedParameters)
   Se omite

== 3. Pruebas (npm test)
   OK
   ℹ tests 1
   ℹ pass 1
   ℹ fail 0
   [MEDIO] cambió lógica y no se tocó ninguna prueba:
      → Recomendación: Escribe pruebas para el caso normal, los casos borde y el error de la lógica que cambió.
      src/pedidos.js
      src/precio.mjs

== 4. Archivos de prueba que el script de pruebas no nombra
   OK

== 5. Secretos y archivos que no deben subirse
   OK

== 6. Patrones peligrosos
   [ALTO] HTML inyectado o código dinámico (confirmar que nada venga de una persona):
      → Recomendación: Muestra el texto como texto (React ya lo escapa). Si de verdad hace falta HTML, límpialo con una librería probada (DOMPurify) y nunca ejecutes texto como código.
      22:+  return <div dangerouslySetInnerHTML={{ __html: texto }} />;
   [ALTO] SQL armado con texto (inyección):
      → Recomendación: Usa parámetros del cliente de la base o funciones con argumentos; en PL/pgSQL, format() con %I y %L. Nunca concatenes lo que escribe una persona.
      17:+  return db.query(`select * from pedidos where correo = '${correo}'`);
   [ALTO] datos sensibles en almacenamiento del navegador:
      → Recomendación: Guarda sesiones y claves en el almacenamiento seguro del sistema (Keychain o Keystore) o en cookies httpOnly; el almacenamiento del navegador lo lee cualquier script de la página.
      29:+  localStorage.setItem('token', token);
   [ALTO] Math.random para identificadores, claves o tokens (es predecible):
      → Recomendación: Usa crypto.randomUUID() o crypto.getRandomValues().
      26:+export const codigoDeRecuperacion = () => Math.random().toString(36).slice(2, 8);
   [MEDIO] salidas de depuración:
      → Recomendación: Quítalas. Si hace falta registrar algo, que sea sin datos personales y con un registrador que se apague en producción.
      30:+  console.log('sesión guardada', token);

== 7. Base de datos (SQL cambiado)
   db/pedidos.sql
   [CRITICO] db/pedidos.sql crea tablas sin RLS en ningún archivo del repositorio: pedidos 
      → Recomendación: alter table ... enable row level security, y reglas que solo dejen ver y cambiar lo propio.
   [ALTO] db/pedidos.sql: funciones security definer sin search_path fijo (1 definer, 0 search_path)
      → Recomendación: Agrega set search_path a cada función security definer (vacío, calificando las tablas con su esquema).
   [ALTO] db/pedidos.sql tiene reglas con true: dejan leer o escribir todas las filas
      → Recomendación: Cambia true por una condición sobre el usuario, como auth.uid() = dueño.
   [ALTO] db/pedidos.sql crea funciones security definer sin revocar el permiso por omisión a public
      → Recomendación: revoke all on function ... from public, anon; y luego grant execute solo a quien la use.
   [MEDIO] db/pedidos.sql: tabla nueva sin disparadores ni checks en el mismo archivo: confirmar topes contra inserciones masivas y límites de largo
      → Recomendación: Agrega un disparador con tope por usuario y por hora, con la fecha puesta por el servidor, y checks de largo.
   [MEDIO] db/pedidos.sql tiene columnas text sin límite de largo
      → Recomendación: Agrega check (char_length(columna) <= N) con un N razonable.

== 8. Accesibilidad
   [ALTO] botón con solo ícono y sin aria-label:
      → Recomendación: Agrega aria-label con lo que hace el botón, y aria-hidden al ícono.
      34:+  return <button onClick={alCerrar}><svg viewBox="0 0 10 10"><path d="M1 1l8 8" /></svg></button>;

== 9. Dependencias
   Sin package-lock.json: se omite

== 10. Pendientes y restos de pruebas manuales
   [ALTO] pendientes, pruebas desactivadas o restos de pruebas manuales:
      → Recomendación: Termina el pendiente o anótalo como tarea. Reactiva la prueba y quita los interruptores de prueba manual antes de publicar.
      36:+// TODO: validar el correo

== VEREDICTO
   críticos: 1 · altos: 9 · medios: 4 · bajos: 0
   NO APROBADO: hay hallazgos críticos o altos. No se publica hasta corregirlos o justificar cada uno por escrito.
```

## Pasos 2 y 3: el reporte de Claude

**Veredicto: NO APROBADO.** Hay 3 críticos, 7 altos, 4 medios y 1 bajo.

| Gravedad | Dónde | Qué pasa | Recomendación |
|---|---|---|---|
| Crítico | `src/pedidos.js:3` | La consulta se arma con el correo que escribe la persona: `' or '1'='1` devuelve los pedidos de todos. | Consulta con parámetros (`where correo = $1`). |
| Crítico | `db/pedidos.sql:1` | La tabla `pedidos` no tiene RLS: cualquiera con la llave pública lee todos los pedidos. | `enable row level security` y una regla por dueño. |
| Crítico | `db/pedidos.sql:13` | La regla `using (true)` deja ver todos los pedidos a cualquiera; aunque se active RLS, no protege nada. | `using (correo = auth.email())` o, mejor, por id del dueño. |
| Alto | `src/pedidos.js:8` | La nota del cliente se pinta como HTML: un cliente puede meter un script que corre en la pantalla del administrador. | Mostrarla como texto. |
| Alto | `src/pedidos.js:12` | El código de recuperación usa `Math.random` y tiene 6 caracteres: se puede adivinar. | `crypto.getRandomValues`, más largo, con vencimiento y tope de intentos. |
| Alto | `src/pedidos.js:15` | El token de sesión queda en `localStorage`, al alcance de cualquier script de la página (y del de la nota de arriba). | Cookie `httpOnly` o almacenamiento seguro del sistema. |
| Alto | `db/pedidos.sql:8` | `total_de` corre con privilegios elevados, sin `search_path` fijo y abierta a `public`: cualquiera suma los pedidos de cualquier correo. | `set search_path = ''`, `revoke ... from public, anon` y comprobar que el correo sea el de quien pide. |
| Alto | `src/pedidos.js:20` | El botón de cerrar solo tiene un ícono: un lector de pantalla dice "botón" y nada más. | `aria-label="Cerrar"` y `aria-hidden` en el ícono. |
| Alto | `src/pedidos.js:22` | Queda un pendiente: el correo no se valida. | Validarlo antes de consultar, o anotar la tarea. |
| Alto | `src/precio.mjs:2` | `precioConDescuento` acepta porcentajes negativos o mayores que 100 (el precio sube o queda negativo) y no redondea, cuando `precioConIva` sí. | Validar 0 ≤ pct ≤ 100 y redondear igual que el IVA. |
| Medio | `src/pedidos.js:16` | El `console.log` imprime el token de sesión. | Quitarlo. |
| Medio | `src/precio.mjs` | La lógica nueva no tiene pruebas. | Probar 0 %, 100 %, valores con decimales y porcentajes inválidos. |
| Medio | `db/pedidos.sql` | `correo` y `nota` no tienen largo máximo, y la tabla no tiene tope de inserciones. | `check (char_length(nota) <= 500)` y un tope por usuario y por hora. |
| Medio | `db/pedidos.sql:5` | `total numeric` acepta negativos. | `check (total >= 0)`. |
| Bajo | `db/pedidos.sql` | No hay índice por `correo`, que es justo por donde se busca. | `create index on public.pedidos (correo)`. |

**Recomendaciones para mejorar:** validar las entradas con un esquema en un solo lugar; buscar pedidos por el id del usuario con sesión y no por un correo que llega del navegador; agregar al proyecto `tsconfig.json` para que el script pueda revisar tipos y código muerto.

**Lo que no se pudo verificar:** cómo se crea la sesión en el servidor y si las páginas tienen CSP; eso no está en el cambio.

Dos fallas que el script no ve salieron en la lectura: el redondeo y los porcentajes de `precioConDescuento`, y que la función `total_de` deja consultar los pedidos de otro correo. Por eso el script es el piso y no el techo.
