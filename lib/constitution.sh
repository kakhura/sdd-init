# shellcheck shell=bash
# shellcheck disable=SC2016,SC2034
# shellcheck disable=SC2034
# Builds .specify/memory/constitution.md from the answers and the stack profile.

PRINCIPLES=''
PRINCIPLE_INDEX=''   # rows for the plan template's Constitution Check
_pn=0
_roman() {
  local n=$1 out='' vals=(10 9 5 4 1) syms=(X IX V IV I) i
  for i in 0 1 2 3 4; do while [ "$n" -ge "${vals[$i]}" ]; do out="$out${syms[$i]}"; n=$((n - ${vals[$i]})); done; done
  printf '%s' "$out"
}
# add_principle "Title" "short check text" "body"
add_principle() {
  _pn=$((_pn + 1))
  local r; r=$(_roman "$_pn")
  PRINCIPLES="${PRINCIPLES}### ${r}. $1

${3%$'\n'}

"
  PRINCIPLE_INDEX="${PRINCIPLE_INDEX}| ${r} | $2 | | |
"
}

_p_tenant() { cat <<'EOF'
- Every request, query, cache key, event, file path and log line that touches tenant data is scoped to exactly one tenant.
- The tenant comes from trusted context (authenticated token, gateway header, host mapping) — never from a client-controlled body, query or path field.
- Caches, queues and storage keys include the tenant. Background jobs iterate tenants explicitly and isolate failures per tenant.
- Every feature that reads or writes tenant data has a test proving one tenant cannot read or change another tenant's data.
EOF
}
_p_money() { cat <<'EOF'
- No floating point for money, rates or limits: use exact decimal types or integer minor units, respecting each currency's precision. The rounding rule is written in the plan.
- Every money-moving operation is idempotent (idempotency key or natural unique reference; same key + different payload = conflict).
- Balance changes, their history rows and their outgoing events are written in one transaction (transactional outbox where events leave the service). Financial records are never deleted.
- A provider call that moves money is never retried blindly; an unclear outcome becomes an explicit UNKNOWN / needs-review state.
- No database transaction stays open during an external provider call.
EOF
}
_p_i18n_be() { cat <<'EOF'
- Translatable content is stored per locale (base + translations), validated against the locales enabled for the tenant/site.
- Responses state which locale they are in; a missing translation falls back to the configured default locale by a documented rule (whole record, never a mix).
- Cache keys include the locale; caches are invalidated when any translation changes.
EOF
}
_p_i18n_fe() { cat <<'EOF'
- No hard-coded user-facing strings: every text goes through the i18n layer with keys per feature.
- Dates, numbers and currencies are formatted with the locale; layouts work for long translations and RTL where supported.
- The active locale is part of data-fetch keys and URLs where content differs per locale.
EOF
}
_p_contracts() { cat <<'EOF'
- Every endpoint, event and message has a written contract in the feature's `contracts/` folder before implementation.
- Contract changes are backward compatible (additive fields) or versioned; the plan lists every consumer affected.
- One response/error format across the API; errors carry a stable machine-readable code.
- Lists are paginated with a bounded page size; filters are validated.
EOF
}
_p_security_be() { cat <<'EOF'
- Every new route declares its authentication and authorization (role/permission/policy) and is covered by a "forbidden" test.
- All input is validated at the boundary; mass assignment is explicit.
- Queries are parameterised; no user input reaches SQL text, shell commands, file paths or templates unescaped.
- Secrets live only in environment/secret stores; a new variable is added to `.env.example` and deploy config in the same change. Agents never read real `.env` files or secrets.
- No secrets, tokens, card data or personal data in logs, errors or events.
EOF
}
_p_observability() { cat <<'EOF'
- Structured logs with stable event names; request/correlation IDs propagated across calls.
- Alert-worthy failures log at ERROR with enough context to act, without personal data.
- Configuration is parsed and validated at startup; the service fails fast on invalid config.
EOF
}
_p_docs() { cat <<'EOF'
- When API, schema, events, configuration or behaviour change, the project docs (README, `docs/`, API specs, Postman/OpenAPI) are updated in the same change.
- The feature folder (`specs/NNN-*/`) is the record of WHY; project docs are the record of WHAT IS.
- Copy the closest existing pattern in the codebase instead of inventing a new one. No speculative abstractions, no unrelated refactors; extra ideas become new specs.
EOF
}
_p_components() { cat <<'EOF'
{{STACK_RULES}}
- Reuse the design system / shared UI components before creating new ones; new shared components get stories or a usage example.
- Feature code does not import from another feature's internals; shared code lives in a shared module.
EOF
}
_p_ux_states() { cat <<'EOF'
- Every data-driven view handles loading, empty, error and success states, and the error state offers a recovery path.
- API access goes through one typed client generated from or checked against the backend contract; responses are validated at the boundary when the contract is not typed end-to-end.
- Forms validate on the client for UX and rely on the server for truth; server validation errors are shown next to the field.
- Optimistic updates roll back on failure.
EOF
}
_p_a11y() { cat <<'EOF'
- Target WCAG 2.2 AA: semantic elements, labelled controls, visible focus, full keyboard operation, sufficient contrast, `alt` text for meaningful images.
- Dialogs, menus and toasts manage focus and announce changes to assistive technology.
- Accessibility is checked in component tests (queries by role/label) and with an automated audit on critical pages.
EOF
}
_p_security_fe() { cat <<'EOF'
- Raw HTML is rendered only after sanitising (DOMPurify or equivalent) and with a code comment explaining why.
- No secrets in the client bundle or public env variables; tokens are not stored in `localStorage` when an httpOnly cookie flow is available.
- External links opening new tabs use `rel="noopener noreferrer"`; user-controlled URLs are validated (`http(s)` only).
- Authorization is enforced by the backend; client guards are UX only.
EOF
}
_p_perf_fe() { cat <<'EOF'
- Route-level code splitting; heavy dependencies are justified in the plan.
- Images are sized, lazy-loaded and served in modern formats; fonts are preloaded/self-hosted.
- Core Web Vitals budgets for key pages (LCP < 2.5s, CLS < 0.1, INP < 200ms on a mid-range mobile) are not regressed.
EOF
}
_p_tests() { cat <<'EOF'
- Every behaviour added or changed ships with tests, including error and edge paths. Bugs get a failing regression test first.
{{TEST_RULES}}
EOF
}
_p_gates() { cat <<'EOF'
- Before a change is done, these pass for every touched module:
{{VERIFY_BULLETS}}
- Lint/analyser configuration is never weakened to make code pass; suppressions are single-line, name the rule and give a reason.
- CI runs the same commands.
EOF
}

build_constitution() {
  PRINCIPLES=''; PRINCIPLE_INDEX=''; _pn=0
  local b
  if [ "$TENANT" = y ]; then
    b=$(_p_tenant | render); add_principle "Tenant Isolation (NON-NEGOTIABLE)" "Tenant from trusted context; tenant-scoped queries, caches, jobs; cross-tenant test" "$b"
  fi
  if [ "$KIND" = backend ]; then
    b=$(printf '%s\n\n%s\n' "Request flow: {{LAYERING}}" "{{STACK_RULES}}" | render)
    add_principle "Layered Architecture" "Flow respected; thin transport layer; one error-mapping point" "$b"
    if [ "$DATA" != none ]; then
      b=$(printf '%s\n' "Data access: **{{DATA_LABEL}}**." "" "{{DATA_RULES}}" "- Concurrency-sensitive writes name their lock or uniqueness guarantee in the plan and have a concurrent-request test." "- Every new lookup path has an index; list queries are bounded." | render)
      add_principle "Data Access" "Data-access style followed; SQL safe; locks and indexes named" "$b"
      b=$(printf '%s\n' "{{MIGRATION_RULES}}" | render)
      add_principle "Migrations Are Forward-Only" "Migrations reversible, never edited after release, expand/contract" "$b"
    fi
    if [ "$MONEY" = y ]; then
      b=$(_p_money | render); add_principle "Money and Financial Integrity (NON-NEGOTIABLE)" "No float money; idempotency; single-tx outbox; no blind retries" "$b"
    fi
    b=$(_p_contracts | render); add_principle "Contracts and Compatibility" "Contracts written; backward compatible; consumers listed" "$b"
    b=$(_p_security_be | render); add_principle "Security and Configuration" "Authz on every route; validated input; no secrets/PII in logs" "$b"
    if [ "$I18N" = y ]; then
      b=$(_p_i18n_be | render); add_principle "Localization" "Locales validated; documented fallback; locale in cache keys" "$b"
    fi
    b=$(_p_tests | render); add_principle "Tests Are Part of the Change" "Tests at the right level incl. error paths; skips reported" "$b"
    b=$(_p_gates | render); add_principle "Quality Gates Are Absolute" "Format, lint, type-check, generate, tests pass" "$b"
    b=$(_p_observability | render); add_principle "Observability" "Structured logs, correlation IDs, fail-fast config" "$b"
  else
    b=$( { printf '%s\n\n' "UI flow: {{LAYERING}}"; _p_components; } | render)
    add_principle "Component Architecture" "Flow respected; shared UI reused; no cross-feature imports" "$b"
    b=$(_p_ux_states | render); add_principle "Data, State and UX States" "Typed API client; loading/empty/error states; form errors" "$b"
    b=$(_p_a11y | render); add_principle "Accessibility (NON-NEGOTIABLE)" "WCAG 2.2 AA; keyboard; labels; focus" "$b"
    b=$(_p_security_fe | render); add_principle "Client Security" "No unsanitised HTML; no secrets in bundle; backend authz" "$b"
    b=$(_p_perf_fe | render); add_principle "Performance Budgets" "Code splitting; images; Web Vitals not regressed" "$b"
    if [ "$I18N" = y ]; then
      b=$(_p_i18n_fe | render); add_principle "Localization" "No hard-coded strings; locale-aware formatting and data keys" "$b"
    fi
    if [ "$MONEY" = y ]; then
      b='- Amounts are displayed from server-provided decimal strings/minor units with currency formatting; the client never computes authoritative totals.
- Payment actions are idempotent from the UI (disabled while pending, idempotency key forwarded) and show an explicit pending/unknown state.'
      add_principle "Money in the UI" "Server-authoritative amounts; idempotent payment actions" "$b"
    fi
    b=$(_p_tests | render); add_principle "Tests Are Part of the Change" "Component tests by role/label; MSW; e2e for journeys" "$b"
    b=$(_p_gates | render); add_principle "Quality Gates Are Absolute" "Format, lint, type-check, tests, build pass" "$b"
  fi
  b=$(_p_docs | render); add_principle "Documentation and Smallest Change" "Docs updated; sibling pattern reused; no scope creep" "$b"
  register_vars PRINCIPLES PRINCIPLE_INDEX
}

tpl_constitution() { cat <<'EOF'
<!--
Sync Impact Report
- Version: 0.0.0 (template) → 1.0.0
- Ratified: {{TODAY}} (generated by sdd-init {{SDD_INIT_VERSION}})
- Principles: generated from answers (kind={{KIND}}, stack={{STACK_LABEL}}, data={{DATA_LABEL}}, tenant={{TENANT}}, money={{MONEY}}, i18n={{I18N}})
- Templates aligned: .specify/templates/overrides/{spec,plan,tasks}-template.md
- Agents aligned: planner, builder, reviewer, committer ({{TOOLS_LABEL}})
- TODO: refine with evidence from this repository (`{{CMD_CONSTITUTION}} Refine this generated constitution against the actual code…`)
-->

# {{PROJECT_NAME}} Constitution

{{PROJECT_NAME}} is a {{KIND}} project built with {{STACK_LABEL}}. This constitution holds the
rules that every spec, plan, task, implementation and review MUST satisfy.

MUST / MUST NOT / SHOULD / MAY follow RFC 2119. A plan that breaks a MUST needs a row in its
**Complexity Tracking** table and explicit approval; a plan that breaks a NON-NEGOTIABLE
principle is rejected.

## Core Principles

{{PRINCIPLES}}
## Technology Baseline

| Area | Standard |
|---|---|
{{TECH_ROWS}}
| Data access | {{DATA_LABEL}} |
| Repo layout | {{LAYOUT_LABEL}} |
| Default branch | `{{DEFAULT_BRANCH}}` |

## Development Workflow & Agents

Spec-Driven Development (GitHub Spec Kit) runs from this folder. Feature folders live in
`specs/NNN-short-name/` (put the ticket key in the short name, e.g. `{{TICKET_EXAMPLE}}`).

| Step | Command ({{PRIMARY_TOOL_LABEL}}) | Who does the work | Output |
|---|---|---|---|
| 1 | `{{CMD_SPECIFY}}` | main session (+ you) | `spec.md`, `checklists/requirements.md` |
| 2 | `{{CMD_CLARIFY}}` | main session (+ you) | answers recorded in `spec.md` |
| 3 | `{{CMD_PLAN}}` | main session; Phase 0 research delegated to **planner** | `research.md`, `plan.md`, `data-model.md`, `contracts/`, `quickstart.md` |
| 4 | `{{CMD_TASKS}}` | main session | `tasks.md` (gated phases) |
| 5 | `{{CMD_ANALYZE}}` | main session (read-only) | consistency report |
| 6 | `{{CMD_SDD_IMPLEMENT}}` | **builder** per phase, **reviewer** per gate | code, `[X]` in `tasks.md` |
| 7 | `{{CMD_CONVERGE}}` | main session | remaining gaps appended as tasks |
| 8 | "commit and push" | **committer** | commits on the feature branch |

Rules:
- `spec.md` describes WHAT and WHY only; frameworks, tables and endpoints belong in `plan.md`.
- `plan.md` contains the Constitution Check and the exact verification commands.
- The builder follows `tasks.md`; when the plan is wrong it stops and reports.
- The reviewer checks code against `spec.md`, `plan.md` and this constitution and cites principle numbers.
- Never push to {{PROTECTED_BRANCHES_MD}}; changes reach `{{DEFAULT_BRANCH}}` through reviewed pull/merge requests.
- Small, obvious fixes (one file, no schema/contract/security change) MAY skip Spec Kit and go straight to the builder.

## Governance

- This constitution overrides plans and agent defaults. Agent files and templates MUST stay consistent with it.
- Amendments go through `{{CMD_CONSTITUTION}}` with a Sync Impact Report and semantic versioning (MAJOR: principle removed/redefined; MINOR: principle/section added; PATCH: wording).
- Every `plan.md` runs the Constitution Check before research and after design; every review states which principles were checked.

**Version**: 1.0.0 | **Ratified**: {{TODAY}} | **Last Amended**: {{TODAY}}
EOF
}
