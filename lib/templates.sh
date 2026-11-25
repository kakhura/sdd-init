# shellcheck shell=bash
# shellcheck disable=SC2016,SC2034
# shellcheck disable=SC2034
# Spec Kit template overrides (.specify/templates/overrides/*.md).

build_template_vars() {
  SPEC_EXTRA=''
  local tenant_hint=''
  [ "$TENANT" = y ] && tenant_hint=', in which tenant, and what one tenant must never see of another'
  if [ "$TENANT" = y ] || [ "$KIND" = backend ]; then
    SPEC_EXTRA="${SPEC_EXTRA}### Access & Scope *(mandatory)*

<!-- Business level: who may do what${tenant_hint}. -->

- **AC-001**: [Which roles may perform which actions]
- **AC-002**: [What must stay invisible / unchangeable for others]

"
  fi
  if [ "$MONEY" = y ]; then
    SPEC_EXTRA="${SPEC_EXTRA}### Money & Consistency *(include if amounts, balances, payments or limits change)*

- **MC-001**: [Which amounts change, currency, rounding rule]
- **MC-002**: [What happens when the same operation is submitted twice]
- **MC-003**: [What happens when a provider's outcome is unknown]

"
  fi
  if [ "$I18N" = y ]; then
    SPEC_EXTRA="${SPEC_EXTRA}### Languages *(include if user-facing content or text changes)*

- **LG-001**: [Which content is per language, which is shared]
- **LG-002**: [What users see when a translation is missing]

"
  fi
  if [ "$KIND" = frontend ]; then
    SPEC_EXTRA="${SPEC_EXTRA}### Screens & States *(mandatory)*

<!-- Reference design files/links. For each screen: purpose, main actions, and what the user sees while loading, when empty, and on error. -->

- **UI-001**: [Screen] — [purpose]; loading: […]; empty: […]; error: […]
- **UI-002**: [Accessibility or responsive expectation]

"
  fi
  SPEC_EXTRA="${SPEC_EXTRA}### Compatibility *(include if existing behaviour, APIs or screens change)*

- **CP-001**: [Which existing clients/users depend on today's behaviour, and what must not break]
"

  if [ "$KIND" = backend ]; then
    heredoc PLAN_STACK_SECTIONS <<'EOF'
## Data Access Plan

<!-- One row per new/changed query or repository method. Style must match the constitution's Data Access principle. -->

| Module | Method | Query location | Tx? | Lock / idempotency | Index |
|--------|--------|----------------|-----|--------------------|-------|

## Database Migrations

| File | Up | Down | Data / lock risk |
|------|----|------|------------------|

## Contracts & Events

- **HTTP**: [routes, method, auth/permission, request/response, errors] → `contracts/http-*.md`
- **Events/messages**: [name, payload, producer, consumers, idempotency] → `contracts/events-*.md`
- **Backward compatibility**: [who consumes this today and why nothing breaks]

## Security & Concurrency Notes

[authz per route, validation, locks, idempotency, failure states]
EOF
  else
    heredoc PLAN_STACK_SECTIONS <<'EOF'
## Routes & Screens

| Route | Screen / component tree | Data needed | Auth / guard | Loading / empty / error |
|-------|-------------------------|-------------|--------------|--------------------------|

## API Contracts Consumed

| Endpoint | Request | Response type | Errors handled | Mock (MSW) |
|----------|---------|---------------|----------------|------------|

## State & Caching

[server-state keys, invalidation, client state, optimistic updates]

## Accessibility & i18n

[keyboard flow, focus, labels, new translation keys]

## Performance

[new dependencies + size, lazy loading, images]
EOF
  fi

  if [ "$LAYOUT" = multi ]; then
    REPO_TAG_FMT=' [repo]'
    REPO_TAG_HELP='- **[repo]**: the git repo the task changes (multi-repo workspace)'
    AFFECTED_SECTION='## Affected Repositories

| Repo | Change | Verification | Branch |
|------|--------|--------------|--------|

**Order of delivery**: [shared libraries first, then owners, then consumers]
'
  else
    REPO_TAG_FMT=''
    REPO_TAG_HELP=''
    AFFECTED_SECTION=''
  fi

  VERIFY_BLOCK=''
  local c
  for c in "$CMD_FORMAT" "$CMD_LINT" "$CMD_TYPECHECK" "$CMD_GENERATE" "$CMD_TEST" "$CMD_BUILD"; do
    [ -n "$c" ] && VERIFY_BLOCK="${VERIFY_BLOCK}${c}
"
  done
  [ -n "${CMD_E2E:-}" ] && VERIFY_BLOCK="${VERIFY_BLOCK}${CMD_E2E}   # journeys touched by the feature
"
  VERIFY_BULLETS=''
  while IFS= read -r c; do [ -n "$c" ] && VERIFY_BULLETS="${VERIFY_BULLETS}  - \`${c}\`
"; done <<EOF
$VERIFY_BLOCK
EOF
  VERIFY_BULLETS=${VERIFY_BULLETS%$'\n'}
  VERIFY_INLINE=$(printf '%s' "$VERIFY_BLOCK" | awk 'NF{printf "%s`%s`", (n++?", ":""), $0}')
  register_vars SPEC_EXTRA PLAN_STACK_SECTIONS REPO_TAG_FMT REPO_TAG_HELP AFFECTED_SECTION VERIFY_BLOCK VERIFY_BULLETS VERIFY_INLINE
}

tpl_spec() { cat <<'EOF'
# Feature Specification: [FEATURE NAME]

**Feature Branch**: `[###-feature-name]`

**Ticket**: [ticket key or "none"]

**Created**: [DATE]

**Status**: Draft

**Input**: User description: "$ARGUMENTS"

<!--
  {{PROJECT_NAME}} RULES FOR THIS FILE
  - Describe WHAT users need and WHY. No frameworks, tables, endpoints, components or file paths:
    those belong in plan.md.
  - Read .specify/memory/constitution.md first. Questions about access, data safety and
    compatibility that the input does not answer become [NEEDS CLARIFICATION: ...] markers.
  - Reference design files or screenshots by path when the input mentions them.
-->

## User Scenarios & Testing *(mandatory)*

<!-- Prioritised journeys (P1 = most critical). Each must be independently testable. -->

### User Story 1 - [Brief Title] (Priority: P1)

[Journey in plain language, naming the actor]

**Why this priority**: [Value]

**Independent Test**: [How this story is verified on its own]

**Acceptance Scenarios**:

1. **Given** [initial state], **When** [action], **Then** [expected outcome]
2. **Given** [initial state], **When** [action], **Then** [expected outcome]

---

### User Story 2 - [Brief Title] (Priority: P2)

[Journey]

**Why this priority**: [Value]

**Independent Test**: [How]

**Acceptance Scenarios**:

1. **Given** [initial state], **When** [action], **Then** [expected outcome]

---

[Add more user stories as needed]

### Edge Cases

<!-- Consider: duplicate/retried requests, concurrent edits, missing permission, invalid or
     missing data, external dependency failure, empty states, very large inputs. -->

- What happens when [boundary condition]?
- How does the system handle [error scenario]?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST [specific capability]
- **FR-002**: System MUST [specific capability]
- **FR-00X**: System MUST [capability] [NEEDS CLARIFICATION: what is unclear]

{{SPEC_EXTRA}}
### Key Entities *(include if feature involves data)*

- **[Entity 1]**: [What it represents, key attributes without implementation]

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: [Measurable, technology-agnostic outcome]
- **SC-002**: [Measurable outcome]

## Assumptions

- [Reasonable default chosen when the input was silent]

## Out of Scope

- [Explicitly excluded behaviour]
EOF
}

tpl_plan() { cat <<'EOF'
# Implementation Plan: [FEATURE]

**Branch**: `[###-feature-name]` | **Date**: [DATE] | **Spec**: [link]

**Input**: Feature specification from `specs/[###-feature-name]/spec.md`

<!--
  {{PROJECT_NAME}} PLANNING RULES
  1. Read .specify/memory/constitution.md.
  2. Phase 0 research: delegate to the `planner` subagent ({{DELEGATE_HINT}}) with the
     feature directory and spec path. It explores the codebase and writes research.md
     (Decision / Rationale / Alternatives + "Context found" with file paths). Build this plan
     from research.md; do not repeat the exploration in the main session.
  3. Every NEEDS CLARIFICATION is resolved in research.md or returned to the user.
-->

## Summary

[Primary requirement + technical approach]

## Technical Context

**Language/Version**: {{LANGUAGE}}

**Primary Dependencies**: {{FRAMEWORK}}, [others]

**Data access**: {{DATA_LABEL}}

**Testing**: [see constitution "Tests Are Part of the Change"]

**Target Platform**: [e.g. Linux containers, browsers (evergreen + iOS Safari)]

**Performance Goals**: [or NEEDS CLARIFICATION]

**Constraints**: [timeouts, compatibility, budgets]

**Scale/Scope**: [users, rows, requests]

{{AFFECTED_SECTION}}
## Constitution Check

*GATE: must pass before Phase 0 research; re-check after Phase 1 design. Mark ✅ / ⚠️ (justified in Complexity Tracking) / ❌ (blocker).*

| # | Principle | Status | Evidence in this plan |
|---|-----------|--------|-----------------------|
{{PRINCIPLE_INDEX}}
{{PLAN_STACK_SECTIONS}}

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
├── spec.md
├── plan.md              # this file
├── research.md          # Phase 0 (planner subagent)
├── data-model.md        # Phase 1
├── quickstart.md        # Phase 1
├── contracts/           # Phase 1
├── checklists/
└── tasks.md             # tasks command
```

### Source Code (touched paths only)

```text
{{SRC_TREE}}
```

**Structure Decision**: [Paths and why]

## Verification

```bash
{{VERIFY_BLOCK}}```

[Plus quickstart.md scenarios]

## Complexity Tracking

> Fill ONLY if the Constitution Check has ⚠️ items.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|--------------------------------------|
EOF
}

tpl_tasks() { cat <<'EOF'
---

description: "{{PROJECT_NAME}} task list template (agent-executed)"
---

# Tasks: [FEATURE NAME]

**Input**: Design documents from `specs/[###-feature-name]/`

**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Tests**: REQUIRED by the constitution. Test tasks precede the implementation they cover and must fail first.

**Executor**: the `builder` subagent executes one phase at a time ({{CMD_SDD_IMPLEMENT}}); each
phase ends with VERIFY and a REVIEW GATE run by the `reviewer` subagent. A task is ticked `[X]`
only when its code and tests are done.

## Format: `- [ ] T### [P?] [US#?]{{REPO_TAG_FMT}} Description with exact path`

- **[P]**: parallel-safe (different files, no ordering dependency)
- **[US#]**: user story from spec.md (omit in Setup/Foundational/Polish)
{{REPO_TAG_HELP}}

<!--
  ============================================================================
  RULES FOR THE TASKS COMMAND IN {{PROJECT_NAME}} (replace the samples below)

  Ordering inside every story:
{{TASK_ORDER}}
  Every phase that changes code ends with one VERIFY task and one REVIEW GATE task.
  Never generate tasks that edit generated code by hand, edit an already-released
  migration, or skip tests.
  ============================================================================
-->

## Phase 1: Setup

- [ ] T001 BRANCH: ensure branch `[TICKET]-[short-name]` exists{{REPO_TAG_FMT}} (committer agent)
- [ ] T002 [P] [config / dependency change if the plan requires it]

---

## Phase 2: Foundational (blocks all stories)

- [ ] T003 [shared schema / types / infrastructure the stories need]
- [ ] T004 VERIFY: {{VERIFY_INLINE}}
- [ ] T005 REVIEW GATE: reviewer on Phase 2

**Checkpoint**: foundation ready

---

## Phase 3: User Story 1 - [Title] (Priority: P1) 🎯 MVP

**Goal**: [what this story delivers]

**Independent Test**: [maps to spec acceptance scenarios]

### Tests for User Story 1 (write first, must fail)

- [ ] T006 [P] [US1] [test file path]: happy path, validation/error path, permission denied

### Implementation for User Story 1

- [ ] T007 [US1] [path] — [what]
- [ ] T008 [US1] [path] — [what]
- [ ] T009 VERIFY: {{VERIFY_INLINE}}
- [ ] T010 REVIEW GATE: reviewer on US1 against spec + plan + constitution

**Checkpoint**: User Story 1 works and is independently testable

---

## Phase 4: User Story 2 - [Title] (Priority: P2)

[Same structure: tests first → implementation → VERIFY → REVIEW GATE]

---

## Phase N: Polish & Docs

- [ ] TXXX [P] Update docs / API specs / Postman or OpenAPI
- [ ] TXXX Run quickstart.md scenarios
- [ ] TXXX VERIFY all touched modules
- [ ] TXXX FINAL REVIEW GATE, then the converge command

---

## Dependencies & Execution Order

- Setup → Foundational → stories by priority → Polish
- A REVIEW GATE with verdict CHANGES REQUIRED blocks the next phase until fixed

## Notes

- One commit per phase is a good default (committer agent)
- Avoid vague tasks, same-file conflicts and tasks without a path
EOF
}

write_overrides() {
  tpl_spec  | render | write_file .specify/templates/overrides/spec-template.md
  tpl_plan  | render | write_file .specify/templates/overrides/plan-template.md
  tpl_tasks | render | write_file .specify/templates/overrides/tasks-template.md
}
