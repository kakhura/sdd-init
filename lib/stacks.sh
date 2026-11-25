# shellcheck shell=bash
# shellcheck disable=SC2016,SC2034
# shellcheck disable=SC2034  # variables are consumed by other modules via render()
# Stack profiles. Each stack_<id> function sets the variables used by the generators.

stack_reset() {
  STACK_LABEL=''; LANGUAGE=''; FRAMEWORK=''; LAYERING=''; STACK_RULES=''; SRC_TREE=''
  TEST_RULES=''; MIGRATION_RULES=''; TASK_ORDER=''; REVIEW_FOCUS=''; TECH_ROWS=''
  CMD_FORMAT=''; CMD_LINT=''; CMD_TYPECHECK=''; CMD_TEST=''; CMD_GENERATE=''; CMD_BUILD=''; CMD_E2E=''
  DATA_CHOICES=(); DATA_DEFAULT=''; NEEDS_PM=n; NEEDS_PYRUN=n
}

BACKEND_STACKS=(
  "go|Go (chi / net/http, pgx)"
  "laravel|PHP · Laravel"
  "nestjs|Node.js · NestJS (TypeScript)"
  "express|Node.js · Express / Fastify (TypeScript)"
  "fastapi|Python · FastAPI"
  "django|Python · Django / DRF"
  "aspnet|C# · ASP.NET Core"
  "other-be|Other backend (you type the commands)"
)
FRONTEND_STACKS=(
  "react|React + Vite (TypeScript)"
  "nextjs|Next.js (App Router, TypeScript)"
  "vue|Vue 3 + Vite (TypeScript)"
  "nuxt|Nuxt 3/4 (TypeScript)"
  "angular|Angular"
  "sveltekit|Svelte / SvelteKit (TypeScript)"
  "other-fe|Other frontend (you type the commands)"
)

# ---------------------------------------------------------------- backend

stack_go() {
  STACK_LABEL='Go'; LANGUAGE='Go'; FRAMEWORK='net/http + chi'
  LAYERING='`transport/http` (router, handlers) → `service` (business rules, consumer-side interfaces) → `repository` → database. `domain` has no I/O.'
  heredoc STACK_RULES <<'EOF'
- `context.Context` is the first parameter of every I/O function and is propagated; no `context.Background()` on request paths.
- Errors are wrapped with `%w` and mapped to HTTP status in exactly one place.
- Interfaces are declared by the consumer; implementations carry a compile-time assertion `var _ service.X = (*Y)(nil)`.
- No global mutable state; dependencies are wired in `cmd/<app>/main.go`.
- Goroutines always have an owner, a cancellation path and error propagation.
EOF
  heredoc SRC_TREE <<'EOF'
cmd/<app>/main.go
internal/config/
internal/domain/
internal/repository/
internal/service/
internal/transport/http/(handlers|routes.go)
sql/migrations/  sql/queries/
docs/
EOF
  heredoc TEST_RULES <<'EOF'
- Table-driven tests with `t.Run`; `go test -race` is the default.
- Repository code is tested against a real database (testcontainers or a disposable `TEST_DB_DSN`); mocks are for the service layer only.
- HTTP handlers are tested with `httptest` (status codes, response envelope, error mapping).
- A skipped integration test is not a pass: report skips explicitly.
EOF
  heredoc MIGRATION_RULES <<'EOF'
- Numbered `NNNNNN_name.up.sql` + `.down.sql`; the down file must work.
- A migration that has run on a shared environment is never edited — add a new one.
- Expand → migrate → contract; no destructive change in the release that stops using a column.
- New lookup paths get an index in the same migration.
EOF
  heredoc TASK_ORDER <<'EOF'
1. migration (up + down)
2. queries / repository code + repository tests (real DB)
3. domain rules + tests
4. service logic + tests (consumer interfaces)
5. transport: handlers, routes, error mapping + httptest
6. events / clients / workers
7. docs, config (.env.example, deploy manifests)
EOF
  heredoc REVIEW_FOCUS <<'EOF'
- context propagation, goroutine leaks, data races, shared maps without locks
- errors wrapped with `%w`, not swallowed, mapped in one place
- SQL only through the repository; parameters only; `rows.Err()`/`Close` handled
EOF
  TECH_ROWS='| Language | Go (see `go.mod`) |
| HTTP | net/http + chi (adjust to the project) |
| Tests | `testing`, table tests, testcontainers |
| Lint | golangci-lint v2 |'
  CMD_FORMAT='test -z "$(gofmt -l .)"'; CMD_LINT='golangci-lint run ./...'; CMD_TEST='go test -race ./...'
  CMD_BUILD='go build ./...'
  if [ -f Makefile ]; then
    grep -qE '^lint:' Makefile && CMD_LINT='make lint'
    grep -qE '^test:' Makefile && CMD_TEST='make test'
    grep -qE '^build:' Makefile && CMD_BUILD='make build'
  fi
  DATA_CHOICES=(
    "sqlc|sqlc (SQL files → generated Go)"
    "native|Native SQL with pgx (repository pattern)"
    "both|Both: sqlc + native pgx repositories (per service)"
    "gorm|GORM"
    "ent|ent"
    "none|No database"
  )
  DATA_DEFAULT='sqlc'
}

stack_laravel() {
  STACK_LABEL='PHP · Laravel'; LANGUAGE='PHP 8.x'; FRAMEWORK='Laravel'
  LAYERING='route → thin controller → Form Request (validation) → DTO / resource → service (interface bound in a service provider) → Eloquent model.'
  heredoc STACK_RULES <<'EOF'
- Controllers contain no business logic and no queries; they validate (Form Request), call a service, return a response/resource.
- Services are bound to interfaces in a service provider; business rules live in services, not in models or controllers.
- Responses use one consistent envelope / API Resources with correct HTTP codes.
- Enums replace magic strings and ints.
- Side effects run in events/listeners/jobs; work that must not happen on rollback is dispatched after commit.
EOF
  heredoc SRC_TREE <<'EOF'
routes/*.php
app/Http/Controllers/…
app/Http/Requests/…
app/Http/Resources/… (or DTOs)
app/Services/…  app/Interfaces/…
app/Models/…  app/Enums/…
app/(Events|Listeners|Jobs|Policies)/…
database/migrations/…
tests/(Feature|Unit)/…
EOF
  heredoc TEST_RULES <<'EOF'
- PHPUnit/Pest Feature tests for every endpoint (happy path, validation errors, 401/403, other owner's resource); Unit tests for services and helpers.
- `RefreshDatabase` (or transactions) for DB tests; `Bus::fake`, `Event::fake`, `Http::fake` for side effects; external providers are always faked.
EOF
  heredoc MIGRATION_RULES <<'EOF'
- Created with `artisan make:migration`, always with a working `down()`.
- Never edit a migration that ran on a shared environment — add a new one.
- Expand → backfill → switch → contract; heavy backfills become commands or queued jobs.
- Production seeders are idempotent (`updateOrCreate` / `firstOrCreate`).
EOF
  heredoc TASK_ORDER <<'EOF'
1. migration (with down) + model casts/relations/fillable + enums
2. tests (Feature for endpoints, Unit for services) — written to fail
3. Form Request + DTO / Resource
4. service interface + implementation + binding
5. controller method (thin) + route + auth/policy
6. events / listeners / jobs / notifications / cache invalidation
EOF
  heredoc REVIEW_FOCUS <<'EOF'
- N+1 queries (eager loading), unbounded queries in lists/exports
- mass assignment, raw SQL without bindings, policies/permissions on every route
- `DB::transaction` + `lockForUpdate` where state is decided concurrently
EOF
  TECH_ROWS='| Language | PHP 8.x |
| Framework | Laravel |
| Tests | PHPUnit / Pest |
| Quality | Pint, Larastan (PHPStan) |'
  local sail_def=n; [ -f vendor/bin/sail ] && sail_def=y
  confirm USE_SAIL_Q "Run commands through Laravel Sail?" "$sail_def"
  local p=''; [ "$USE_SAIL_Q" = y ] && p='vendor/bin/sail '
  if [ -n "$p" ]; then
    CMD_FORMAT="${p}pint --test"; CMD_LINT="${p}php vendor/bin/phpstan analyse --memory-limit=512M"; CMD_TEST="${p}artisan test"
  else
    CMD_FORMAT='vendor/bin/pint --test'; CMD_LINT='vendor/bin/phpstan analyse --memory-limit=512M'; CMD_TEST='php artisan test'
  fi
  DATA_CHOICES=(
    "eloquent|Eloquent in services"
    "eloquent-repo|Eloquent behind repository interfaces"
    "none|No database"
  )
  DATA_DEFAULT='eloquent'
}

_node_common() {
  NEEDS_PM=y
  heredoc TEST_RULES <<'EOF'
- Unit tests for services/domain logic; integration tests for endpoints (supertest / framework test client) against a real test database.
- External HTTP and queues are mocked at the boundary; never call real providers.
EOF
  heredoc MIGRATION_RULES <<'EOF'
- Migrations are generated by the ORM/migration tool, reviewed, and committed; each has a down/rollback where the tool supports it.
- Never edit a migration that ran on a shared environment — add a new one.
- Expand → backfill → switch → contract.
EOF
  heredoc TASK_ORDER <<'EOF'
1. schema / migration
2. repository / data-access code + integration tests
3. DTOs + validation schemas
4. service logic + unit tests
5. controller / route handler + auth guard + endpoint tests
6. events / jobs / clients
7. docs (OpenAPI), config (.env.example)
EOF
  heredoc REVIEW_FOCUS <<'EOF'
- unhandled promise rejections, missing `await`, error middleware mapping
- input validation on every endpoint (DTO/zod), no `any` leaking through boundaries
- N+1 queries, unbounded list queries, transactions where needed
EOF
  DATA_CHOICES=(
    "prisma|Prisma"
    "typeorm|TypeORM"
    "drizzle|Drizzle ORM"
    "knex|Knex / raw SQL repositories"
    "none|No database"
  )
  DATA_DEFAULT='prisma'
}

stack_nestjs() {
  _node_common
  STACK_LABEL='Node.js · NestJS'; LANGUAGE='TypeScript (Node.js)'; FRAMEWORK='NestJS'
  LAYERING='module → controller (thin, DTO + ValidationPipe, guards) → service (business rules) → repository / ORM → database.'
  heredoc STACK_RULES <<'EOF'
- One Nest module per bounded area; cross-module access goes through exported providers, never deep imports.
- Controllers are thin: DTOs with class-validator (or zod pipes), guards for auth, no business logic.
- Services hold business rules and are injected via constructor DI; no `new` of providers.
- Exceptions are mapped by exception filters to one response format.
- `strict` TypeScript; no `any` across module boundaries.
EOF
  heredoc SRC_TREE <<'EOF'
src/<module>/<module>.module.ts
src/<module>/<module>.controller.ts
src/<module>/<module>.service.ts
src/<module>/dto/*.ts
src/<module>/entities|schema/*
test/*.e2e-spec.ts
EOF
  TECH_ROWS='| Language | TypeScript (strict) |
| Framework | NestJS |
| Tests | Jest / Vitest + supertest |
| Quality | ESLint, Prettier, tsc |'
}

stack_express() {
  _node_common
  STACK_LABEL='Node.js · Express/Fastify'; LANGUAGE='TypeScript (Node.js)'; FRAMEWORK='Express or Fastify'
  LAYERING='router → handler (validation with zod/JSON schema) → service (business rules) → repository → database.'
  heredoc STACK_RULES <<'EOF'
- Routers only wire paths, middleware and handlers; handlers validate input (zod / JSON schema) and call services.
- Services hold business rules and receive dependencies as parameters/constructor args (no hidden singletons).
- One error-handling middleware maps domain errors to HTTP responses.
- `strict` TypeScript; async errors always reach the error handler.
EOF
  heredoc SRC_TREE <<'EOF'
src/routes/*.ts
src/handlers/*.ts
src/services/*.ts
src/repositories/*.ts
src/schemas/*.ts
test/**/*.test.ts
EOF
  TECH_ROWS='| Language | TypeScript (strict) |
| Framework | Express / Fastify |
| Tests | Vitest / Jest + supertest |
| Quality | ESLint, Prettier, tsc |'
}

_python_common() {
  NEEDS_PYRUN=y
  heredoc TEST_RULES <<'EOF'
- pytest; fixtures for DB sessions with transaction rollback or a disposable test DB.
- Endpoint tests with the framework test client (status, payload, auth, validation errors).
- External HTTP mocked (respx / responses); never call real providers.
EOF
  heredoc MIGRATION_RULES <<'EOF'
- Migrations are generated (Alembic / Django), reviewed and committed, with a working downgrade.
- Never edit a migration that ran on a shared environment — add a new one.
- Expand → backfill → switch → contract; data migrations are separate from schema migrations.
EOF
  heredoc REVIEW_FOCUS <<'EOF'
- type hints on public functions, mypy/pyright clean
- N+1 queries (select_related/prefetch_related or selectinload), unbounded queries
- blocking calls inside async code; transactions where state is decided
EOF
}

stack_fastapi() {
  _python_common
  STACK_LABEL='Python · FastAPI'; LANGUAGE='Python 3.12+'; FRAMEWORK='FastAPI'
  LAYERING='router (path operations, Pydantic request/response models, dependencies) → service (business rules) → repository (SQLAlchemy session) → database.'
  heredoc STACK_RULES <<'EOF'
- Routers are thin: Pydantic models in and out, dependencies for auth/session, no business logic.
- Services hold business rules; repositories own all queries.
- Async all the way on request paths; no blocking I/O in async functions.
- One exception handler maps domain errors to HTTP responses.
EOF
  heredoc SRC_TREE <<'EOF'
app/api/routers/*.py
app/schemas/*.py
app/services/*.py
app/repositories/*.py
app/models/*.py
alembic/versions/*.py
tests/**/*.py
EOF
  heredoc TASK_ORDER <<'EOF'
1. model + Alembic migration (with downgrade)
2. repository + tests (test DB)
3. Pydantic schemas
4. service + unit tests
5. router + dependencies (auth) + endpoint tests
6. background tasks / clients
EOF
  TECH_ROWS='| Language | Python 3.12+ |
| Framework | FastAPI, Pydantic v2 |
| Tests | pytest, httpx |
| Quality | ruff, mypy |'
  DATA_CHOICES=(
    "sqlalchemy|SQLAlchemy 2.0 + Alembic"
    "sqlmodel|SQLModel + Alembic"
    "none|No database"
  )
  DATA_DEFAULT='sqlalchemy'
}

stack_django() {
  _python_common
  STACK_LABEL='Python · Django'; LANGUAGE='Python 3.12+'; FRAMEWORK='Django (+ DRF)'
  LAYERING='urls → view / ViewSet (thin) → serializer (validation) → service functions (business rules) → models / QuerySets.'
  heredoc STACK_RULES <<'EOF'
- Views and ViewSets are thin; serializers validate; business rules live in service functions, not in views or signals.
- Permissions classes on every view; querysets are scoped to the requesting user/owner.
- Fat model methods only for logic that belongs to one row; cross-model flows live in services.
- `transaction.atomic` + `select_for_update` where state is decided concurrently.
EOF
  heredoc SRC_TREE <<'EOF'
<app>/models.py  <app>/migrations/
<app>/serializers.py
<app>/services.py
<app>/views.py  <app>/urls.py
<app>/tests/
EOF
  heredoc TASK_ORDER <<'EOF'
1. model + migration
2. service functions + tests
3. serializer + validation tests
4. view/ViewSet + permissions + urls + API tests
5. signals / tasks (Celery) / admin
EOF
  TECH_ROWS='| Language | Python 3.12+ |
| Framework | Django, Django REST Framework |
| Tests | pytest-django |
| Quality | ruff, mypy (django-stubs) |'
  DATA_CHOICES=("django-orm|Django ORM" "none|No database")
  DATA_DEFAULT='django-orm'
}

stack_aspnet() {
  STACK_LABEL='C# · ASP.NET Core'; LANGUAGE='C# (.NET)'; FRAMEWORK='ASP.NET Core'
  LAYERING='endpoint / controller (thin, request DTO + validation) → application service / handler → domain → infrastructure (EF Core / Dapper repositories).'
  heredoc STACK_RULES <<'EOF'
- Controllers / minimal-API endpoints are thin: validate (FluentValidation or DataAnnotations), call an application service, map to a response DTO.
- Domain entities are never returned directly from the API.
- Dependencies are registered in DI with the right lifetime (no scoped services in singletons).
- `CancellationToken` flows through every async call; `async void` is forbidden.
- Nullable reference types enabled; warnings are errors.
- One exception-handling middleware returns ProblemDetails.
EOF
  heredoc SRC_TREE <<'EOF'
src/<App>.Api/(Controllers|Endpoints)/
src/<App>.Application/
src/<App>.Domain/
src/<App>.Infrastructure/(Persistence|Migrations)/
tests/<App>.Tests/
EOF
  heredoc TEST_RULES <<'EOF'
- xUnit (or NUnit) unit tests for application/domain logic.
- Integration tests with `WebApplicationFactory` against a real test database (Testcontainers).
- External HTTP mocked at the `HttpMessageHandler` level.
EOF
  heredoc MIGRATION_RULES <<'EOF'
- EF Core migrations are generated, reviewed and committed; `Down` must work.
- Never edit a migration applied to a shared environment — add a new one.
- Expand → backfill → switch → contract.
EOF
  heredoc TASK_ORDER <<'EOF'
1. entity + configuration + migration
2. repository / DbContext changes + integration tests
3. application service / handler + unit tests
4. request/response DTOs + validators
5. controller / endpoint + authorization policy + API tests
6. background services / clients
EOF
  heredoc REVIEW_FOCUS <<'EOF'
- `CancellationToken` propagation, `async void`, sync-over-async (`.Result`, `.Wait()`)
- DI lifetimes, `IDisposable` handling, EF tracking vs `AsNoTracking` for reads
- authorization policies on every endpoint; ProblemDetails for errors
EOF
  TECH_ROWS='| Language | C# (.NET) |
| Framework | ASP.NET Core |
| Tests | xUnit, WebApplicationFactory, Testcontainers |
| Quality | dotnet format, analyzers (warnings as errors) |'
  CMD_FORMAT='dotnet format --verify-no-changes'; CMD_LINT='dotnet build -warnaserror'; CMD_TEST='dotnet test'
  DATA_CHOICES=(
    "efcore|Entity Framework Core"
    "dapper|Dapper (SQL repositories)"
    "efcore-dapper|EF Core for writes + Dapper for reads"
    "none|No database"
  )
  DATA_DEFAULT='efcore'
}

stack_other_be() {
  STACK_LABEL='Backend'
  ask LANGUAGE "Language (e.g. Rust, Java, Kotlin, Elixir)" "Java"
  ask FRAMEWORK "Framework (e.g. Spring Boot, Axum, Phoenix)" "Spring Boot"
  STACK_LABEL="$LANGUAGE · $FRAMEWORK"
  ask LAYERING "Request flow, one line" "controller → service → repository → database"
  ask CMD_FORMAT "Format check command (empty = none)" ""
  ask CMD_LINT "Lint / static analysis command" ""
  ask CMD_TEST "Test command" ""
  ask CMD_BUILD "Build command (empty = none)" ""
  STACK_RULES='- Controllers/handlers are thin; business rules live in services; data access lives in repositories.
- One place maps domain errors to HTTP responses.'
  SRC_TREE='(fill in the project layout in the constitution)'
  TEST_RULES='- Unit tests for services; integration tests for endpoints and data access against a real test database.
- External providers are always faked.'
  MIGRATION_RULES='- Versioned migrations with rollback; never edit an applied migration.
- Expand → backfill → switch → contract.'
  TASK_ORDER='1. schema / migration
2. data access + tests
3. service + tests
4. endpoint + auth + tests
5. side effects / clients'
  REVIEW_FOCUS='- error handling, transactions, validation, authorization on every endpoint'
  TECH_ROWS="| Language | $LANGUAGE |
| Framework | $FRAMEWORK |"
  DATA_CHOICES=("orm|ORM" "sql|SQL repositories" "none|No database")
  DATA_DEFAULT='orm'
}

# ---------------------------------------------------------------- frontend

_fe_common() {
  NEEDS_PM=y
  heredoc TEST_RULES <<'EOF'
- Component/unit tests with Testing Library semantics (query by role/label, not by CSS class); test behaviour, not implementation.
- API calls are mocked at the network layer (MSW) in component tests.
- Critical user journeys have Playwright e2e tests (happy path + main error path).
EOF
  heredoc TASK_ORDER <<'EOF'
1. API types / client functions (from the contract) + mocks (MSW handlers)
2. state / data hooks (query keys, cache invalidation) + tests
3. presentational components + component tests (incl. loading, empty, error states)
4. page / route composition + guards
5. i18n strings, accessibility pass
6. e2e test for the journey
EOF
  heredoc REVIEW_FOCUS <<'EOF'
- loading / empty / error states present; no unhandled promise rejections
- accessibility: labels, roles, focus management, keyboard navigation, contrast
- XSS: no raw HTML injection without sanitising; no secrets in the bundle
- unnecessary re-renders, oversized bundles, unoptimised images
EOF
  MIGRATION_RULES=''
  DATA_CHOICES=()
}

stack_react() {
  _fe_common
  STACK_LABEL='React + Vite'; LANGUAGE='TypeScript'; FRAMEWORK='React + Vite'
  LAYERING='route/page → feature container (data hooks) → presentational components → design-system primitives. Server state in TanStack Query (or the chosen data layer); UI state local.'
  heredoc STACK_RULES <<'EOF'
- Function components + hooks only; components stay small and presentational where possible.
- Server state lives in the data layer (TanStack Query / RTK Query) with typed query keys; never copy server data into global stores.
- API access only through a typed client module; no `fetch` calls inside components.
- `dangerouslySetInnerHTML` only with sanitised HTML (DOMPurify) and a comment.
- `strict` TypeScript; props are typed; no `any`.
EOF
  heredoc SRC_TREE <<'EOF'
src/app/(routes|providers)
src/features/<feature>/(components|hooks|api|types)
src/shared/(ui|lib|api)
src/test/(msw|utils)
e2e/*.spec.ts
EOF
  TECH_ROWS='| Language | TypeScript (strict) |
| Framework | React + Vite |
| Tests | Vitest, Testing Library, MSW, Playwright |
| Quality | ESLint, Prettier, tsc |'
}

stack_nextjs() {
  _fe_common
  STACK_LABEL='Next.js'; LANGUAGE='TypeScript'; FRAMEWORK='Next.js (App Router)'
  LAYERING='`app/` route segment (Server Component by default, data fetched on the server) → client components only where interactivity is needed → shared UI. Mutations via Server Actions or route handlers.'
  heredoc STACK_RULES <<'EOF'
- Server Components by default; `"use client"` only for interactive leaves.
- Secrets and privileged API calls stay on the server (server components, route handlers, Server Actions); nothing secret in `NEXT_PUBLIC_*`.
- Every route segment defines `loading`, `error` and `not-found` behaviour where relevant.
- Caching and revalidation (`revalidate`, tags, `no-store`) are explicit per fetch.
- Inputs to Server Actions / route handlers are validated (zod) and authorised.
- `next/image` and `next/font` for media and fonts; metadata API for SEO.
EOF
  heredoc SRC_TREE <<'EOF'
app/<segment>/(page|layout|loading|error).tsx
app/api/<route>/route.ts
components/(ui|<feature>)
lib/(api|auth|validation)
e2e/*.spec.ts
EOF
  TECH_ROWS='| Language | TypeScript (strict) |
| Framework | Next.js App Router |
| Tests | Vitest/Jest, Testing Library, MSW, Playwright |
| Quality | ESLint (next), Prettier, tsc |'
}

stack_vue() {
  _fe_common
  STACK_LABEL='Vue 3 + Vite'; LANGUAGE='TypeScript'; FRAMEWORK='Vue 3 + Vite'
  LAYERING='route view → feature components (composables for data) → presentational components → UI kit. Pinia for shared client state; server state through composables / TanStack Query.'
  heredoc STACK_RULES <<'EOF'
- `<script setup lang="ts">` + Composition API; logic reused through composables.
- Pinia stores only for shared client state; server data is fetched through composables with typed API clients.
- Props and emits are typed (`defineProps<T>()`, `defineEmits<T>()`); no prop mutation.
- `v-html` only with sanitised HTML (DOMPurify) and a comment.
EOF
  heredoc SRC_TREE <<'EOF'
src/views/*.vue
src/features/<feature>/(components|composables|api)
src/stores/*.ts
src/components/ui/
e2e/*.spec.ts
EOF
  TECH_ROWS='| Language | TypeScript |
| Framework | Vue 3, Vite, Pinia |
| Tests | Vitest, Vue Testing Library, MSW, Playwright |
| Quality | ESLint (vue), Prettier, vue-tsc |'
}

stack_nuxt() {
  _fe_common
  STACK_LABEL='Nuxt'; LANGUAGE='TypeScript'; FRAMEWORK='Nuxt'
  LAYERING='`pages/` → components (auto-imported) → composables (`useFetch`/`useAsyncData`) → `server/api` routes for server-only work.'
  heredoc STACK_RULES <<'EOF'
- Data fetching with `useFetch` / `useAsyncData` and stable keys; no fetching in `onMounted` for SSR content.
- Secrets only in `runtimeConfig` (server); public config under `runtimeConfig.public` contains nothing secret.
- `server/api` handlers validate input and never trust client headers for identity.
- SSR-safe code: no `window`/`document` access outside client-only hooks.
- `v-html` only with sanitised HTML.
EOF
  heredoc SRC_TREE <<'EOF'
pages/**/*.vue
components/<feature>/*.vue
composables/*.ts
server/api/**/*.ts
stores/*.ts
e2e/*.spec.ts
EOF
  TECH_ROWS='| Language | TypeScript |
| Framework | Nuxt, Pinia |
| Tests | Vitest (@nuxt/test-utils), MSW, Playwright |
| Quality | ESLint (@nuxt/eslint), Prettier, nuxi typecheck |'
}

stack_angular() {
  _fe_common
  STACK_LABEL='Angular'; LANGUAGE='TypeScript'; FRAMEWORK='Angular'
  LAYERING='route → smart (container) component → dumb (presentational) components → services (HttpClient, state via signals/NgRx) → API.'
  heredoc STACK_RULES <<'EOF'
- Standalone components; `OnPush` change detection; signals for local state.
- HTTP only through injectable services; interceptors for auth and errors.
- Subscriptions are owned (`takeUntilDestroyed`, `async` pipe); no leaked subscriptions.
- Template binding to `[innerHTML]` only with sanitised content; never bypass `DomSanitizer` without review.
- Strict TypeScript and strict templates.
EOF
  heredoc SRC_TREE <<'EOF'
src/app/<feature>/(pages|components|services|models)
src/app/core/(interceptors|guards)
src/app/shared/ui/
e2e/*.spec.ts
EOF
  TECH_ROWS='| Language | TypeScript (strict) |
| Framework | Angular |
| Tests | Jest/Karma or Vitest, Angular Testing Library, Playwright |
| Quality | ESLint (angular-eslint), Prettier |'
}

stack_sveltekit() {
  _fe_common
  STACK_LABEL='SvelteKit'; LANGUAGE='TypeScript'; FRAMEWORK='Svelte / SvelteKit'
  LAYERING='`src/routes` (`+page.svelte`, `+page.ts`/`+page.server.ts` load functions, form actions) → components → `$lib` modules (API client, stores/runes).'
  heredoc STACK_RULES <<'EOF'
- Data is loaded in `load` functions; server-only work and secrets live in `+page.server.ts` / `+server.ts` / `$lib/server`.
- Mutations use form actions with validation (zod / superforms) and progressive enhancement.
- Svelte 5 runes (`$state`, `$derived`, `$props`) for component state.
- `{@html}` only with sanitised HTML.
EOF
  heredoc SRC_TREE <<'EOF'
src/routes/**/(+page.svelte|+page.ts|+page.server.ts|+server.ts)
src/lib/(components|api|server|stores)
tests/  e2e/
EOF
  TECH_ROWS='| Language | TypeScript |
| Framework | Svelte 5, SvelteKit |
| Tests | Vitest, Svelte Testing Library, Playwright |
| Quality | ESLint, Prettier, svelte-check |'
}

stack_other_fe() {
  _fe_common
  ask LANGUAGE "Language" "TypeScript"
  ask FRAMEWORK "Framework (e.g. Solid, Qwik, Remix)" "Remix"
  STACK_LABEL="$FRAMEWORK"
  ask LAYERING "UI flow, one line" "route → container → components → API client"
  NEEDS_PM=n
  ask CMD_FORMAT "Format check command (empty = none)" ""
  ask CMD_LINT "Lint command" ""
  ask CMD_TYPECHECK "Type-check command (empty = none)" ""
  ask CMD_TEST "Test command" ""
  ask CMD_BUILD "Build command (empty = none)" ""
  STACK_RULES='- Components are small; data access only through a typed API client.
- Raw HTML injection only with sanitised content.'
  SRC_TREE='(fill in the project layout in the constitution)'
  TECH_ROWS="| Language | $LANGUAGE |
| Framework | $FRAMEWORK |"
}

# JS / Python command defaults once the package manager / runner is known.
apply_runner_commands() {
  if [ "$NEEDS_PM" = y ]; then
    local r="$PM run" x='npx'
    case "$PM" in pnpm) x='pnpm exec' ;; yarn) x='yarn' ;; bun) x='bunx' ;; esac
    # Use package.json scripts when they exist, otherwise the tool directly.
    _has_script() { [ -f package.json ] && grep -q "\"$1\"[[:space:]]*:" package.json; }
    if [ -z "$CMD_FORMAT" ]; then
      if _has_script format:check; then CMD_FORMAT="$r format:check"; else CMD_FORMAT="$x prettier --check ."; fi
    fi
    [ -z "$CMD_LINT" ] && CMD_LINT="$r lint"
    if [ -z "$CMD_TYPECHECK" ]; then
      if _has_script typecheck; then CMD_TYPECHECK="$r typecheck"
      else
        case "$STACK" in
          vue)       CMD_TYPECHECK="$x vue-tsc --noEmit" ;;
          nuxt)      CMD_TYPECHECK="$x nuxi typecheck" ;;
          sveltekit) CMD_TYPECHECK="$x svelte-check" ;;
          angular)   CMD_TYPECHECK='' ;;   # ng build type-checks templates
          *)         CMD_TYPECHECK="$x tsc --noEmit" ;;
        esac
      fi
    fi
    [ -z "$CMD_TEST" ] && CMD_TEST="$r test"
    [ -z "$CMD_BUILD" ] && CMD_BUILD="$r build"
    [ "$DATA" = prisma ] && CMD_GENERATE="$x prisma generate && git diff --exit-code"
    if [ "$KIND" = frontend ] && [ -z "${CMD_E2E:-}" ]; then
      if _has_script test:e2e; then CMD_E2E="$r test:e2e"; else CMD_E2E="$x playwright test"; fi
    fi
  fi
  if [ "$NEEDS_PYRUN" = y ]; then
    local p=''
    case "$PYRUN" in uv) p='uv run ' ;; poetry) p='poetry run ' ;; *) p='' ;; esac
    CMD_FORMAT="${p}ruff format --check ."
    CMD_LINT="${p}ruff check ."
    CMD_TYPECHECK="${p}mypy ."
    CMD_TEST="${p}pytest"
  fi
}

# Data-access rules for backend stacks.
data_profile() {
  DATA_LABEL=''; DATA_RULES=''
  case "$DATA" in
    sqlc)
      DATA_LABEL='sqlc'
      heredoc DATA_RULES <<'EOF'
- Schema source of truth is the migrations folder; queries live in `sql/queries/<table>.sql` with `-- name: X :one|:many|:exec` annotations.
- After any change to migrations or queries run `sqlc generate` (or `make generate`) and commit the output. Generated code is never hand-edited.
- Repositories wrap the generated `Queries`, accept a DBTX (pool or tx) and convert rows to domain types; generated structs never reach handlers.
- If sqlc cannot express a query (dynamic sort, COPY, advisory locks), a native query is allowed inside the repository only, with a comment saying why.
EOF
      CMD_GENERATE='sqlc generate && git diff --exit-code'
      if [ -f Makefile ] && grep -qE '^generate:' Makefile; then CMD_GENERATE='make generate && git diff --exit-code'; fi
      ;;
    native)
      DATA_LABEL='native SQL (pgx) repositories'
      heredoc DATA_RULES <<'EOF'
- All SQL lives in the repository package. No SQL strings in services, handlers or workers.
- Values are always bind parameters (`$1`, `= ANY($n)`); identifiers are concatenated only from constants; `LIKE` input is escaped.
- Column lists are constants and rows are read through one scan helper per entity.
- `rows.Close()` / `rows.Err()` always handled; pg errors are classified into domain errors at the repository boundary.
- Repositories accept a small querier interface satisfied by both the pool and a transaction.
EOF
      ;;
    both)
      DATA_LABEL='sqlc and native pgx (per service)'
      heredoc DATA_RULES <<'EOF'
- Each service/module has ONE primary style, recorded in the constitution; new code follows it. Introducing the other style needs a Complexity Tracking row in the plan.
- **sqlc**: queries in `sql/queries`, run `sqlc generate`/`make generate`, never hand-edit generated code, repositories convert rows to domain types.
- **native pgx**: SQL only in the repository package, bind parameters only, column constants + one scan helper per entity, `rows.Err()` handled, pg errors classified at the boundary.
- Both: consumer-side interfaces, compile-time assertions, transactions via a closure helper that never stays open across an external call, named locks (`FOR UPDATE`, advisory, unique + idempotency row), repository tests on a real database.
EOF
      CMD_GENERATE='sqlc generate && git diff --exit-code   # in sqlc services'
      if [ -f Makefile ] && grep -qE '^generate:' Makefile; then CMD_GENERATE='make generate && git diff --exit-code   # in sqlc services'; fi
      ;;
    gorm)
      DATA_LABEL='GORM'
      heredoc DATA_RULES <<'EOF'
- GORM is used only inside the repository package; models do not leak into handlers.
- No `AutoMigrate` in production — schema changes go through versioned migrations.
- Always pass `WithContext(ctx)`; check `Error` on every call; avoid `Save` on partial structs.
- Preload explicitly; no N+1 loops. Raw SQL only with placeholders.
EOF
      ;;
    ent)
      DATA_LABEL='ent'
      heredoc DATA_RULES <<'EOF'
- Schema lives in `ent/schema`; run `go generate ./ent` and commit the output; never edit generated code.
- Versioned migrations (Atlas) instead of auto-migration in production.
- ent clients are used only from the repository layer; transactions through a helper.
EOF
      CMD_GENERATE='go generate ./ent && git diff --exit-code'
      ;;
    eloquent)
      DATA_LABEL='Eloquent (in services)'
      heredoc DATA_RULES <<'EOF'
- Eloquent models and relationships are the default; query logic lives in services or model scopes — never in controllers.
- Raw SQL (`DB::select`, `whereRaw`, `selectRaw`) only when the Query Builder can't express it, always with bindings, with a comment why.
- Lists, reports and exports eager-load (`with`, `withCount`); N+1 queries are defects; large exports are chunked and queued.
- `$fillable` or DTO-mapped attributes only; no `$guarded = []`.
EOF
      ;;
    eloquent-repo)
      DATA_LABEL='Eloquent behind repositories'
      heredoc DATA_RULES <<'EOF'
- Services depend on repository interfaces; Eloquent is used only inside repository implementations.
- Repositories return models/DTOs, never query builders.
- Raw SQL only with bindings; eager loading in every list method; no N+1.
EOF
      ;;
    prisma)
      DATA_LABEL='Prisma'
      heredoc DATA_RULES <<'EOF'
- `schema.prisma` is the source of truth; migrations via `prisma migrate dev`, committed; `prisma generate` after schema changes.
- PrismaClient is used only in repositories/services, one instance per process.
- `$queryRaw` only with tagged templates (parameterised); never `$queryRawUnsafe` with input.
- `select`/`include` explicitly in list queries; transactions with `$transaction`.
EOF
      ;;
    typeorm)
      DATA_LABEL='TypeORM'
      heredoc DATA_RULES <<'EOF'
- `synchronize` is off outside local dev; schema changes go through generated migrations.
- Repositories own queries; QueryBuilder parameters only (`:name`), never string concatenation.
- Relations are loaded explicitly; transactions via `DataSource.transaction`.
EOF
      ;;
    drizzle)
      DATA_LABEL='Drizzle ORM'
      heredoc DATA_RULES <<'EOF'
- Schema in TypeScript; migrations generated with drizzle-kit and committed.
- `sql` template tag only (parameterised); no string-built SQL.
- Queries live in repository modules; transactions with `db.transaction`.
EOF
      ;;
    knex)
      DATA_LABEL='Knex / SQL repositories'
      heredoc DATA_RULES <<'EOF'
- All SQL in repository modules; bindings only (`?` / named), never string concatenation.
- Knex migrations with `up` and `down`; transactions with `knex.transaction` passed into repositories.
EOF
      ;;
    sqlalchemy|sqlmodel)
      DATA_LABEL='SQLAlchemy 2.0 + Alembic'; [ "$DATA" = sqlmodel ] && DATA_LABEL='SQLModel + Alembic'
      heredoc DATA_RULES <<'EOF'
- Sessions are provided by a dependency and scoped to the request; repositories receive the session.
- 2.0-style `select()`; relationships loaded explicitly (`selectinload`/`joinedload`); no lazy loading in async code.
- `text()` only with bound parameters.
- Alembic autogenerate output is reviewed before commit.
EOF
      ;;
    django-orm)
      DATA_LABEL='Django ORM'
      heredoc DATA_RULES <<'EOF'
- QuerySets are scoped to the requesting user/owner in one place (manager / service).
- `select_related` / `prefetch_related` in every list; no N+1.
- `raw()` / `extra()` only with params; `transaction.atomic` + `select_for_update` for concurrent decisions.
EOF
      ;;
    efcore|efcore-dapper|dapper)
      case "$DATA" in efcore) DATA_LABEL='EF Core' ;; dapper) DATA_LABEL='Dapper' ;; *) DATA_LABEL='EF Core + Dapper' ;; esac
      heredoc DATA_RULES <<'EOF'
- DbContext / connections are used only in the infrastructure layer behind interfaces.
- EF Core: `AsNoTracking` for reads, explicit `Include`, no lazy loading; migrations reviewed and committed.
- Dapper / raw SQL: parameters only (`@name`), never string interpolation into SQL (`FromSqlRaw` with input is forbidden; use `FromSqlInterpolated`/parameters).
- Transactions are explicit and never stay open across external calls.
EOF
      ;;
    orm|sql)
      DATA_LABEL='project data layer'
      DATA_RULES='- Data access lives in one layer behind interfaces; parameterised queries only; versioned migrations.'
      ;;
    none|'')
      DATA_LABEL='none'; DATA_RULES=''
      ;;
  esac
}
