# Auditoría de código (skill para Claude Code)

[English version](README.en.md)

Skill en español para que Claude Code audite cada cambio en proyectos **TypeScript / Next.js / React**, con **Supabase** opcional. Trabaja como un auditor exigente: supone que el código falla hasta demostrar lo contrario, piensa como atacante y no suaviza ni recorta los hallazgos.

Tiene dos partes:

- `revisar.sh`: diez comprobaciones automáticas que solo leen el repositorio. Revisa tipos, código muerto, pruebas (también las que nunca corren), secretos y archivos sensibles, inyección, SQL y reglas de la base, accesibilidad, dependencias y restos de pruebas manuales. Cada falla sale con su recomendación, y al final da un veredicto: si hay algo crítico o alto, no aprueba y sale con código 1.
- `SKILL.md`: la actitud del auditor, la lectura con criterio (correctitud, seguridad, base de datos, rendimiento, accesibilidad, calidad) y el reporte. El reporte trae el veredicto, todas las fallas con su recomendación, las mejoras sugeridas y lo que no se pudo verificar.

Pone el foco en la seguridad (fugas y bases de datos protegidas contra abuso) y en la accesibilidad. Esto incluye a las personas daltónicas: nada se comunica solo con color.

Hay un ejemplo real, corrido sobre un proyecto pequeño de demostración, en [EJEMPLO.md](EJEMPLO.md).

## Instalación

Como plugin, desde Claude Code:

```
/plugin marketplace add jhodz456/revision-de-codigo
/plugin install revision-de-codigo@revision-de-codigo
```

Para actualizarla después: `claude plugin update revision-de-codigo@revision-de-codigo`.

O copiando la carpeta en tus skills personales, para todos tus proyectos:

```
git clone https://github.com/jhodz456/revision-de-codigo.git ~/.claude/skills/revision-de-codigo
```

O, para un solo proyecto, cópiala en `.claude/skills/revision-de-codigo` dentro del repositorio.

Claude Code la usa sola al terminar cambios de código. También se le puede pedir: "revisa el código con la skill revision-de-codigo".

## Requisitos

- git, bash (sirve el 3.2 de macOS), Node.js y npm.
- `tsc` instalado en el proyecto, para las comprobaciones de tipos. Sin `tsconfig.json`, se omiten.

## Ajustes por proyecto

Son opcionales y van en la raíz del repositorio:

- `.revision/excluir.txt`: rutas que no se revisan, una por línea. Por ejemplo `ios` y `android` en una app con Capacitor, donde están las copias compiladas de la web.
- `.revision/restos.txt`: expresiones regulares que no deben quedar en el código, una por línea. Por ejemplo, un interruptor que se enciende solo para probar a mano.

## Uso directo, sin Claude

```
bash ~/.claude/skills/revision-de-codigo/revisar.sh            # lo que todavía no está en git
bash ~/.claude/skills/revision-de-codigo/revisar.sh <commit>   # todo lo cambiado desde ese commit
```

Para auditar un proyecto entero, pasa el árbol vacío de git: `bash revisar.sh 4b825dc642cb6eb9a060e54bf8d69288fbee4904`.

El script no cambia nada: cada sección dice OK o lo que encontró, con su recomendación. Es el piso, no el techo: lo que marca se confirma leyendo el código, y lo que no marca no queda aprobado por eso.

## Licencia

MIT. Ver `LICENSE`.
