# Code audit (skill for Claude Code)

[Versión en español](README.md)

A Claude Code skill that audits every change in **TypeScript / Next.js / React** projects, with optional **Supabase** checks. It works like a demanding auditor: it assumes the code is broken until shown otherwise, thinks like an attacker, and doesn't soften or trim its findings. Reports are written in Spanish.

It has two parts:

- `revisar.sh`: ten automatic, read-only checks. It looks at types, dead code, tests (including tests that never run), secrets and sensitive files, injection, SQL and database rules (RLS, `security definer`, grants to `anon`, `using (true)`), accessibility, dependencies, and leftovers from manual testing. Every finding comes with a recommendation, and it ends with a verdict: if there is anything critical or high, the change is not approved and the script exits with code 1.
- `SKILL.md`: the auditor's stance, a reasoned review (correctness, security, database, performance, accessibility, quality) and the report format. The report gives the verdict, every finding with its fix, suggested improvements, and what could not be verified.

It puts weight on security (leaks, databases hardened against abuse) and on accessibility, including colour-blind users: nothing is communicated by colour alone.

See a real run on a small demo project in [EJEMPLO.md](EJEMPLO.md) (in Spanish).

## Install

As a plugin, from Claude Code:

```
/plugin marketplace add jhodz456/revision-de-codigo
/plugin install revision-de-codigo@revision-de-codigo
```

To update later: `claude plugin update revision-de-codigo@revision-de-codigo`.

Or clone it into your personal skills, for all your projects:

```
git clone https://github.com/jhodz456/revision-de-codigo.git ~/.claude/skills/revision-de-codigo
```

Or, for one project only, copy it to `.claude/skills/revision-de-codigo` inside that repository.

Claude Code uses it on its own when it finishes a code change. You can also ask for it: "review the code with the revision-de-codigo skill".

## Requirements

- git, bash (macOS's 3.2 works), Node.js and npm.
- `tsc` installed in the project for the type checks. Without `tsconfig.json` they are skipped.

## Per-project settings

Optional, at the repository root:

- `.revision/excluir.txt`: paths to skip, one per line. For example `ios` and `android` in a Capacitor app, which hold compiled copies of the web app.
- `.revision/restos.txt`: regular expressions that must not stay in the code, one per line. For example, a switch you only turn on for manual testing.

## Running it without Claude

```
bash ~/.claude/skills/revision-de-codigo/revisar.sh            # changes not yet committed
bash ~/.claude/skills/revision-de-codigo/revisar.sh <commit>   # everything changed since that commit
```

To audit a whole project, pass git's empty tree: `bash revisar.sh 4b825dc642cb6eb9a060e54bf8d69288fbee4904`.

The script changes nothing: each section prints OK or what it found, with its recommendation. It is the floor, not the ceiling: whatever it flags is confirmed by reading the code, and whatever it doesn't flag isn't approved because of that.

## License

MIT. See `LICENSE`.
