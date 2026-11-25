# shellcheck shell=bash
# shellcheck disable=SC2016,SC2034
# shellcheck disable=SC2034
# Per-tool command names and the sdd-implement / sdd-review orchestration skills.

TOOL_CHOICES=(
  "claude|Claude Code   (subagents .claude/agents, skills .claude/skills)"
  "codex|Codex CLI     (custom agents .codex/agents, skills .agents/skills)"
  "gemini|Gemini CLI    (subagents .gemini/agents, commands .gemini/commands)"
  "copilot|GitHub Copilot (custom agents .github/agents, skills .github/skills)"
)

tool_label() {
  case "$1" in claude) printf 'Claude Code' ;; codex) printf 'Codex CLI' ;; gemini) printf 'Gemini CLI' ;; copilot) printf 'GitHub Copilot' ;; esac
}

# set_tool_vars TOOL — command spellings and delegation phrases for one tool.
set_tool_vars() {
  local t=$1 p s
  case "$t" in
    claude)  p='/speckit-'; s='/sdd-' ;;
    codex)   p='$speckit-'; s='$sdd-' ;;
    gemini)  p='/speckit.'; s='/sdd.' ;;
    copilot) p='/speckit-'; s='/sdd-' ;;
  esac
  CMD_CONSTITUTION="${p}constitution"; CMD_SPECIFY="${p}specify"; CMD_CLARIFY="${p}clarify"
  CMD_PLAN="${p}plan"; CMD_TASKS="${p}tasks"; CMD_ANALYZE="${p}analyze"; CMD_CHECKLIST="${p}checklist"
  CMD_IMPLEMENT="${p}implement"; CMD_CONVERGE="${p}converge"
  CMD_SDD_IMPLEMENT="${s}implement"; CMD_SDD_REVIEW="${s}review"
  case "$t" in
    claude)
      D_PLANNER='the `planner` subagent (Task tool, `subagent_type: "planner"`)'
      D_BUILDER='the `builder` subagent (Task tool, `subagent_type: "builder"`)'
      D_REVIEWER='the `reviewer` subagent (Task tool, `subagent_type: "reviewer"`)'
      D_COMMITTER='the `committer` subagent (Task tool, `subagent_type: "committer"`)'
      ARGS_BLOCK='```text
$ARGUMENTS
```' ;;
    codex)
      D_PLANNER='the `planner` custom agent (spawn it from `.codex/agents/planner.toml` and wait for its result)'
      D_BUILDER='the `builder` custom agent (spawn it from `.codex/agents/builder.toml` and wait for its result)'
      D_REVIEWER='the `reviewer` custom agent (spawn it from `.codex/agents/reviewer.toml` and wait for its result)'
      D_COMMITTER='the `committer` custom agent (spawn it from `.codex/agents/committer.toml` and wait for its result)'
      ARGS_BLOCK='Use the feature folder and phase the user gave together with this skill.' ;;
    gemini)
      D_PLANNER='the `planner` subagent (`@planner`)'
      D_BUILDER='the `builder` subagent (`@builder`)'
      D_REVIEWER='the `reviewer` subagent (`@reviewer`)'
      D_COMMITTER='the `committer` subagent (`@committer`)'
      ARGS_BLOCK='```text
{{args}}
```' ;;
    copilot)
      D_PLANNER='the `planner` custom agent (run it as a subagent)'
      D_BUILDER='the `builder` custom agent (run it as a subagent)'
      D_REVIEWER='the `reviewer` custom agent (run it as a subagent)'
      D_COMMITTER='the `committer` custom agent (run it as a subagent)'
      ARGS_BLOCK='Use the feature folder and phase the user gave together with this skill.' ;;
  esac
  register_vars CMD_CONSTITUTION CMD_SPECIFY CMD_CLARIFY CMD_PLAN CMD_TASKS CMD_ANALYZE CMD_CHECKLIST \
    CMD_IMPLEMENT CMD_CONVERGE CMD_SDD_IMPLEMENT CMD_SDD_REVIEW D_PLANNER D_BUILDER D_REVIEWER D_COMMITTER ARGS_BLOCK
}

body_sdd_implement() { cat <<'EOF'
## User Input

{{ARGS_BLOCK}}

You are the orchestrator. You do not write application code yourself: {{D_BUILDER}}
implements, {{D_REVIEWER}} reviews. You keep `tasks.md` honest.

## 1. Resolve the feature

- If the input names a `specs/NNN-*` folder, use it. Otherwise run
  `.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks` from
  the project root and use `FEATURE_DIR`.
- Required: `spec.md`, `plan.md`, `tasks.md`. If `tasks.md` is missing, stop and tell the user
  to run `{{CMD_TASKS}}`.
- Checklists gate: if `FEATURE_DIR/checklists/` has unchecked items, list them and ask whether
  to continue. Never edit checklist files.
- Recommend `{{CMD_ANALYZE}}` first if it has not been run for this tasks.md (ask, don't block).

## 2. Build the phase queue

Parse `tasks.md` into phases (`## Phase …`). Skip phases whose tasks are all `[X]`. If the input
names a phase or task IDs, start there.

## 3. Loop per phase

0. **Branch tasks** — a task starting with `BRANCH:` goes to {{D_COMMITTER}} with "create or
   switch the branch only, no commits"; tick it yourself when it confirms.
1. **Build** — delegate to {{D_BUILDER}} with: the feature dir, the phase title, the exact task
   IDs (excluding REVIEW GATE and BRANCH) and the instruction "Spec Kit mode: execute only these
   tasks, tick them in tasks.md, run the phase VERIFY tasks". Independent `[P]` tasks in
   different files MAY go to parallel builder runs; tasks touching the same file never do.
2. **Check** — re-read `tasks.md`. Any task the builder did not tick → report it and ask before
   going on. The verification commands must have passed:
{{VERIFY_BULLETS}}
3. **Review gate** — if the phase has a REVIEW GATE task, delegate to {{D_REVIEWER}} with the
   feature dir, the phase and the task IDs just built, in Spec Kit mode.
   - `APPROVE` / `APPROVE WITH NITS` → tick the REVIEW GATE task `[X]` yourself, list nits,
     continue.
   - `CHANGES REQUIRED` → send the BLOCKER/MAJOR findings back to the builder as a fix task
     (same phase), then review again. At most 2 fix rounds; then stop and hand the findings to
     the user.
4. **Checkpoint** — tell the user in 2–4 lines: phase done, tasks ticked, verify result, review
   verdict. If the user asked for one phase at a time, stop here.

Never skip a REVIEW GATE, never tick a task whose verification failed, and never let a subagent
change `spec.md` or `plan.md`. If the builder reports that the plan is wrong, stop and suggest
`{{CMD_PLAN}}` (or `{{CMD_CLARIFY}}`) instead of improvising.

## 4. Finish

When all phases are `[X]`: run `{{CMD_CONVERGE}}` (or tell the user to) to compare the code with
spec/plan and append remaining gaps as tasks; if it appends tasks, loop again from step 2.
Report phases completed, files changed, verification results, review verdicts, open nits, and
the next step: "commit and push" (committer).
EOF
}

body_sdd_review() { cat <<'EOF'
## User Input

{{ARGS_BLOCK}}

1. Resolve the feature dir from the input, or with
   `.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks`.
2. Delegate to {{D_REVIEWER}} in Spec Kit mode with the feature dir and the scope (one phase,
   or "full feature — final gate").
3. Show the user the verdict, the BLOCKER/MAJOR findings with principle numbers, and the Spec
   coverage table. Do not edit code.
4. If the verdict is APPROVE / APPROVE WITH NITS and the scope was a phase with a REVIEW GATE
   task, tick that task in `tasks.md`.
5. Suggest the next step: fixes via `{{CMD_SDD_IMPLEMENT}}`, `{{CMD_CONVERGE}}`, or "commit and push".
EOF
}

_skill_md() {
  # _skill_md name description body_fn
  printf -- '---\nname: "%s"\ndescription: "%s"\n' "$1" "$2"
  [ "$SKILL_FLAVOUR" = claude ] && printf 'argument-hint: "[feature dir, e.g. specs/001-name] [optional phase]"\nuser-invocable: true\ndisable-model-invocation: true\n'
  printf -- '---\n\n'
  "$3" | render
  printf '\n'
}

write_skills_for_tool() {
  local t=$1 dir
  set_tool_vars "$t"
  SKILL_FLAVOUR=$t
  local d_impl="Implement a Spec Kit feature with the builder and reviewer agents, phase by phase, using tasks.md as the source of truth (use instead of ${CMD_IMPLEMENT})."
  local d_rev="Run the reviewer agent on a Spec Kit feature (or one phase) against spec.md, plan.md, tasks.md and the constitution."
  case "$t" in
    claude)  dir=.claude/skills ;;
    codex)   dir=.agents/skills ;;
    copilot) dir=.github/skills ;;
    gemini)
      {
        printf 'description = "%s"\n' "$d_impl"
        printf "prompt = '''\n"; body_sdd_implement | render; printf "\n'''\n"
      } | write_file .gemini/commands/sdd.implement.toml
      {
        printf 'description = "%s"\n' "$d_rev"
        printf "prompt = '''\n"; body_sdd_review | render; printf "\n'''\n"
      } | write_file .gemini/commands/sdd.review.toml
      return 0 ;;
  esac
  _skill_md sdd-implement "$d_impl" body_sdd_implement | write_file "$dir/sdd-implement/SKILL.md"
  _skill_md sdd-review "$d_rev" body_sdd_review | write_file "$dir/sdd-review/SKILL.md"
}

# Delegation hint for the shared plan template (all selected tools).
build_delegate_hint() {
  local t h=''
  for t in $TOOLS; do
    case "$t" in
      claude)  h="${h:+$h; }Claude: Task tool subagent_type \"planner\"" ;;
      codex)   h="${h:+$h; }Codex: spawn custom agent \"planner\"" ;;
      gemini)  h="${h:+$h; }Gemini: @planner" ;;
      copilot) h="${h:+$h; }Copilot: run custom agent \"planner\" as a subagent" ;;
    esac
  done
  DELEGATE_HINT=$h
  register_vars DELEGATE_HINT
}
