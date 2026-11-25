# sdd-init

One command that sets up **GitHub Spec Kit** plus four agents (**planner, builder, reviewer,
committer**) for a project, for **Claude Code, Codex CLI, Gemini CLI and GitHub Copilot**.

It asks a few questions (tools, backend/frontend, language/framework, data access, rules),
runs `specify init` in the current folder, and generates everything the Spec Kit + agents
workflow needs.

## Install

```bash
tar xzf sdd-init-1.0.0.tar.gz          # creates ./sdd-init/
cd sdd-init && ./install.sh             # symlinks ~/.local/bin/sdd-init
```

Requirements: bash (macOS's built-in 3.2 is fine), git, and either the `specify` CLI or `uv`
(the script then runs Spec Kit through `uvx`). Install uv with `brew install uv`.

## Use

```bash
cd ~/projects/my-service
sdd-init                 # interactive
```

Questions:

1. Project name
2. AI tools — any of Claude Code, Codex CLI, Gemini CLI, GitHub Copilot (the first is Spec Kit's default integration)
3. Backend or frontend
4. Language / framework
   - backend: Go, PHP·Laravel, Node·NestJS, Node·Express/Fastify, Python·FastAPI, Python·Django, C#·ASP.NET Core, other
   - frontend: React+Vite, Next.js, Vue+Vite, Nuxt, Angular, Svelte/SvelteKit, other
5. Data access (backend) — e.g. Go: sqlc / native pgx / both / GORM / ent; Laravel: Eloquent / Eloquent + repositories; Node: Prisma / TypeORM / Drizzle / Knex; Python: SQLAlchemy / SQLModel / Django ORM; C#: EF Core / Dapper / both
6. Package manager (JS) or Python runner (uv / poetry / pip); Laravel Sail yes/no
7. Multi-tenant? Handles money? Several languages? — each adds non-negotiable rules
8. One git repo, or a folder of several repos (workspace)
9. Default branch, branches agents must never push to, ticket key prefix
10. Spec Kit's git extension (automatic `NNN-name` branches) yes/no

Every question has a flag, so it also runs non-interactively:

```bash
sdd-init -y --tools claude,codex --kind backend --stack go --data both \
  --tenant y --money y --i18n y --branch main --ticket CR
sdd-init --help
```

## What it generates

| Path | What |
|---|---|
| `.specify/` | Spec Kit (via `specify init` + `specify integration install` for each extra tool) |
| `.specify/memory/constitution.md` | constitution built from your answers (12-ish principles, stack rules, verify commands) |
| `.specify/templates/overrides/{spec,plan,tasks}-template.md` | project templates: Constitution Check table, stack sections, VERIFY + REVIEW GATE phases, BRANCH task |
| Claude Code | `.claude/agents/*.md`, `.claude/skills/sdd-{implement,review}`, `CLAUDE.md` |
| Codex CLI | `.codex/agents/*.toml`, `.agents/skills/sdd-{implement,review}`, `AGENTS.md` |
| Gemini CLI | `.gemini/agents/*.md`, `.gemini/commands/sdd.{implement,review}.toml`, `GEMINI.md` |
| GitHub Copilot | `.github/agents/*.agent.md`, `.github/skills/sdd-{implement,review}`, `.github/copilot-instructions.md` |
| `SPEC-KIT-GUIDE.md` | the end-to-end flow with each tool's command spelling |
| `.specify/sdd-init.env` | your answers, for `sdd-init --reuse` |

`sdd-implement` replaces Spec Kit's implement: the builder works one phase at a time, the
reviewer gates every phase (max two fix rounds), BRANCH tasks go to the committer.

## Safe to re-run

- Files are compared first; only changed files are written. Previous versions go to
  `.sdd-init-backup/<timestamp>/`.
- Instruction files (`CLAUDE.md`, `AGENTS.md`, …) only get a managed block between
  `<!-- sdd-init:start -->` and `<!-- sdd-init:end -->`; the rest of the file is kept.
- The constitution is replaced only while it is Spec Kit's placeholder or sdd-init's untouched
  v1.0.0. Once you refine it (version bump), a new run writes `constitution.sdd-init.md`
  next to it instead; `--force` replaces it (with a backup).
- `specify init` is skipped when `.specify/` exists; missing integrations are added.
- `--dry-run` shows what would be written.

## After running

1. Open the project in your tool (restart it if it was running).
2. Refine the constitution against the real code, e.g. in Claude Code:
   `/speckit-constitution Refine this generated constitution against the actual repository…`
3. Start a feature: `/speckit-specify …` and follow `SPEC-KIT-GUIDE.md`.

## Notes per tool

- **Codex**: custom agents in `.codex/agents/*.toml` are project-scoped; Codex loads project
  config only for trusted projects. Skills are invoked as `$speckit-…` / `$sdd-…`.
- **Gemini**: subagents live in `.gemini/agents/`; commands are `/speckit.…` and `/sdd.…`.
  If `/agents list` doesn't show them, enable subagents in your Gemini CLI settings.
- **Copilot**: Spec Kit marks Copilot as not "multi-install safe", so other tools are added
  with `--force` and `specify integration status` reports a warning; that is expected.
- Spec Kit version defaults to v1.4.4 (`--speckit-version vX.Y.Z` to change).

## Layout of this tool

```
sdd-init            entry point (questions, Spec Kit, generation)
lib/ui.sh           prompts (bash 3.2 compatible)
lib/fs.sh           {{VAR}} rendering, safe writes, backups, managed blocks
lib/stacks.sh       stack profiles + data-access rules + verify commands
lib/constitution.sh principles and the constitution template
lib/templates.sh    spec/plan/tasks overrides
lib/agents.sh       planner/builder/reviewer/committer bodies + per-tool writers
lib/skills.sh       command spellings per tool + sdd-implement / sdd-review
lib/instructions.sh CLAUDE.md / AGENTS.md / GEMINI.md / copilot-instructions + guide
```

To add a stack: write `stack_<id>()` in `lib/stacks.sh` and add `"<id>|Label"` to
`BACKEND_STACKS` or `FRONTEND_STACKS`.
