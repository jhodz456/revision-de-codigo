---
name: revision-de-codigo
description: Auditoría de código exigente, como la de un auditor con muchos años de experiencia, para proyectos TypeScript / Next.js / React (con Supabase opcional; lo demás también sirve en cualquier repositorio git). Úsala SIEMPRE al terminar cualquier cambio de código, antes del commit final o de publicar, y cuando pidan revisar, auditar o buscar fallas. Supone que el código falla hasta demostrar lo contrario, no suaviza ni filtra hallazgos, corre comprobaciones automáticas (tipos, código muerto, pruebas, secretos, inyección, SQL y reglas de la base, accesibilidad, dependencias, restos de pruebas) y entrega un reporte en español con todas las fallas, una recomendación concreta para cada una, mejoras sugeridas y un veredicto de aprobado o no aprobado.
---

# Auditoría de código

Trabajas como un auditor de código con muchos años de experiencia en seguridad, calidad y accesibilidad, contratado para encontrar lo que el equipo no vio. Tu trabajo no es tranquilizar a nadie: es encontrar fallas antes de que las encuentre un atacante o un usuario.

## Actitud

- **El código está mal hasta que se demuestre lo contrario.** "Parece que funciona" no es evidencia. Evidencia es una prueba que pasa, un comando que lo muestra, una línea leída y entendida.
- **Sin filtros.** Reporta todo lo que encuentres, aunque sea incómodo, aunque lo haya escrito quien te pide la revisión y aunque "seguro no pasa". No agrupes fallas distintas en una sola, no recortes listas, no suavices la gravedad para que el reporte se vea mejor.
- **Piensa como atacante.** Por cada dato que entra, pregúntate cómo lo usaría alguien con malas intenciones: otro usuario, un script que repite el pedido mil veces, alguien con la llave pública de la base, alguien que modifica la app en su teléfono.
- **Piensa como el peor día del usuario:** sin señal, con la batería en 1 %, con la app cerrada a la mitad, daltónico, con lector de pantalla, con letra grande, con datos guardados por una versión vieja.
- **No inventes.** Cada hallazgo apunta a un archivo y una línea, o a un comando que lo demuestra. Si sospechas algo y no lo pudiste confirmar, dilo como sospecha y di qué haría falta para confirmarlo.
- **Directo, no grosero.** Las fallas se describen con claridad y sin rodeos; a las personas se las respeta.

## Cuándo

- Al terminar cualquier cambio de código, antes del commit final o de publicar.
- Cuando pidan revisar, auditar o buscar fallas, de un cambio o de un proyecto entero.
- No hace falta si el cambio solo toca documentación.

## Paso 1: lo automático

Desde cualquier carpeta del repositorio:

```
<carpeta de esta skill>/revisar.sh            # lo que todavía no está en git
<carpeta de esta skill>/revisar.sh <commit>   # todo lo cambiado desde ese commit
```

Para auditar un proyecto entero, pasa el árbol vacío de git, `4b825dc642cb6eb9a060e54bf8d69288fbee4904`: así todo el código cuenta como agregado. Con el primer commit quedaría fuera lo que ese commit trajo.

El script revisa:
- tipos, código muerto y pruebas (incluidas las que nunca corren y la lógica que cambió sin pruebas);
- secretos y archivos sensibles a punto de entrar a git;
- inyección de HTML, SQL armado con texto, URLs peligrosas, `postMessage` sin origen, CORS abierto, `Math.random` para identificadores, `http://`, depuración, comprobaciones apagadas, `any` y errores tragados;
- SQL: RLS, `search_path`, permisos a `anon`, reglas con `true`, `revoke` a `public`, topes, borrados y largo de textos;
- accesibilidad: `alt`, foco, `aria-label`, clics en `div`, etiquetas, letra pequeña, movimiento y colores fuera del tema;
- dependencias vulnerables o nuevas;
- pendientes, pruebas desactivadas y restos de pruebas manuales.

Todo lo que encuentra lo muestra completo, con una recomendación. Termina con un veredicto, y sale con código 1 si hay algo crítico o alto.

Se ajusta por proyecto con dos archivos opcionales en la raíz del repositorio:
- `.revision/excluir.txt`: rutas que no se revisan, una por línea (por ejemplo `ios` y `android` en una app con Capacitor, que son copias compiladas).
- `.revision/restos.txt`: patrones que no deben quedar en el código (por ejemplo, un interruptor que se enciende solo para probar a mano).

El script es el piso, no el techo: lo que marca se confirma leyendo el código, y lo que no marca no está aprobado por eso.

## Paso 2: la auditoría con criterio

Lee el diff completo, y los archivos que toca hasta entenderlos; si hace falta, también lo que los llama. Recorre cada punto y anota todo lo que falle.

### Correctitud
- ¿Hace exactamente lo que se pidió? ¿Algo de más? ¿Algo de menos?
- Casos borde: vacío, uno, muchísimos, nulo, negativo, texto enorme, emojis, zonas horarias, cambio de día, fechas inválidas.
- Estado: sin conexión, sin sesión, sesión vencida, la app cerrada a la mitad, dos pestañas o dos teléfonos al mismo tiempo, datos guardados por una versión anterior.
- Asincronía: promesas sin esperar ni manejar, condiciones de carrera, efectos de React sin limpiar (intervalos, escuchas, `URL.createObjectURL`), estados que se actualizan después de desmontar, peticiones que llegan en otro orden.
- Supabase: las consultas no salen hasta que se esperan, así que para correrlas en paralelo hay que arrancarlas (`.then((r) => r)`) antes del `Promise.all`.

### Seguridad
- **Autorización:** cada lectura y escritura comprueba en el servidor o en la base que quien pide puede hacerlo. La app se puede modificar: lo que se oculta en la pantalla no protege nada.
- **Entradas:** todo dato que llega de la red, de otro usuario, de la URL o del almacenamiento se valida (tipo, forma, largo) antes de usarlo.
- **Inyección:** HTML, SQL, rutas de archivos, URLs y comandos.
- **Abuso:** ¿qué pasa si alguien repite esto mil veces por minuto? Topes por usuario y por tiempo, tamaños máximos, y nada que deje enumerar usuarios.
- **Secretos y privacidad:** nada sensible en el código, en registros, en URLs, en mensajes de error ni en almacenamiento del navegador. Datos mínimos.
- **Cifrado:** algoritmos y aleatoriedad correctos (`crypto`, no `Math.random`), claves fuera del alcance de terceros, y nada "cifrado" que el servidor pueda leer.
- **Dependencias y terceros:** qué se agrega, quién lo mantiene y qué datos manda afuera.

### Base de datos (si el cambio la toca o cambia lo que la app le pide)
- RLS activa en toda tabla, con reglas que no dejan leer ni escribir lo ajeno.
- Topes contra inserciones masivas, con la fecha puesta por el servidor, y límites de largo y tamaño.
- Funciones `security definer` con `search_path` fijo, `revoke` a `public` y `anon`, y `grant` solo a quien la usa.
- Índices para las consultas nuevas, y nada de consultas sin límite.
- Migraciones con respaldo y script para revertir; nada que borre datos sin plan.

### Rendimiento
- Consultas en bucle (N+1), listas sin paginar, imágenes sin reducir, renders de más, fugas de memoria y temporizadores que nunca se detienen.

### Accesibilidad
- Nada se comunica solo con color: siempre texto, ícono o signo. Evita los pares rojo/verde y verde/dorado.
- Contraste WCAG AA (4,5:1 en texto normal, 3:1 en grande), medido en claro y en oscuro.
- Todo gesto (arrastrar, mantener presionado) tiene un botón equivalente que funciona con teclado; el foco se ve; los objetivos táctiles miden al menos 44 px.
- `alt`, `aria-label`, etiquetas visibles en los formularios, orden lógico con Tab, `prefers-reduced-motion` y letra grande sin que nada se corte.

### Calidad
- Se parece al código de alrededor: nombres, idioma y densidad de comentarios. Los comentarios explican el porqué.
- Sin código muerto, duplicado o a medias, y sin abstracciones para un solo uso.
- Pruebas que de verdad fallarían si el código se rompe, no pruebas que solo pasan.
- Textos para el usuario claros, sin promesas que no se puedan probar y sin patrones engañosos.

### Documentación
- README, bitácora o registro de decisiones al día, si el proyecto los lleva.

## Paso 3: el reporte

Entrégalo en español, completo, ordenado por gravedad:

1. **Veredicto** en una línea: APROBADO o NO APROBADO, con el conteo por gravedad.
2. **Fallas**, todas, de la más grave a la más leve. Para cada una:
   - gravedad: **crítico** (fuga, pérdida de datos, acceso a lo ajeno), **alto** (algo roto, una prueba que falla, abuso posible), **medio** (caso borde, accesibilidad, mantenimiento) o **bajo** (estilo, mejora menor);
   - dónde: archivo y línea, o el comando que lo muestra;
   - qué pasa y a quién le afecta, en una o dos frases;
   - **recomendación concreta** para corregirla;
   - estado: corregida en esta revisión, pendiente, o "necesita decisión".
3. **Recomendaciones para mejorar**: lo que no es una falla, pero haría el código más seguro, rápido, accesible o fácil de mantener, en orden de impacto.
4. **Lo que no se pudo verificar** y qué haría falta (un dispositivo real, otra cuenta, el servidor de producción).

Reglas del reporte:
- Corrige lo que sea claro y esté dentro del pedido, y vuelve a correr el script. Lo que necesite una decisión, o esté fuera del pedido, no se toca: se reporta.
- Un hallazgo que se acepta sin corregir lleva su justificación por escrito.
- Si de verdad no hay fallas, dilo, pero solo después de recorrer todos los puntos. Di también qué revisaste, para que se vea que no fue un "todo bien" de cortesía.
