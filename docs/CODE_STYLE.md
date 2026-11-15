# Code Style & Design (Elixir/Phoenix/LiveView)

**Related docs:** [ARCHITECTURE.md](ARCHITECTURE.md) (system-level resilience design) · [ELIXIR_TEST_MANIFESTO.md](ELIXIR_TEST_MANIFESTO.md) (testing discipline for this stack)

Same discipline as the sister project ([poe-currency-flip](https://github.com/elaurendeau/poe-currency-flip)'s own `CODE_STYLE.md`), which this document mirrors near-verbatim on principle and adapts on domain examples — Clean Code / SOLID / Clean Architecture translated into idiomatic Elixir, not restated generically.

## Naming

- Names reveal intent — `net_profit_per_day_copper` beats `profit`.
- Predicate functions end in `?` (`resolved?`, `profitable?`) — functions only, never a boolean struct/schema field (`is_current`, `predictable`, not `resolved?`), since a field access isn't a function call and every domain struct eventually backs an Ecto schema whose field names map to DB columns.
- A function that can raise, alongside a same-named tagged-tuple-returning function, gets a `!` suffix (`parse_export!/1` raises; `parse_export/1` returns `{:ok, result} | {:error, reason}`). The `!` version is always a thin raising wrapper — never independent logic living only under the `!` name.
- One word per concept, project-wide: `parse_*` (decoding a raw external shape), `resolve_*` (computed/derived lookups, e.g. resolving an item ID against the wiki), `normalize_*` (adapter raw→domain conversion), `compute_*` (pure functional-core math, e.g. `compute_profit/2`).
- Module names are nouns matching their architectural role (`TsmExportGateway`, `ProfitResult`); function names are verb phrases (`normalize_snapshot/1`, `compute_profit/2`).

## Functions

- Small, one thing, one level of abstraction per function. Prefer multiple function clauses with pattern matching over a single function body with an internal `case`/`cond` — a function whose first move is a large branch on its argument's shape is usually better expressed as separate clauses.
- Pipe-friendly: a function meant to be piped takes its "subject" as the first argument, so `export |> parse() |> join_catalog(patterns)` reads top to bottom.
- No boolean flag arguments. A descriptive atom matched in the function head (`:strict` / `:lenient`), or two separately named functions, never a bare `true`/`false`.
- Command-query separation: a function either returns data or causes a side effect — never both silently. Side-effecting functions say so in their name (`persist_catalog!/1`), never disguised as a plain getter.
- `{:ok, result} | {:error, reason}` over exceptions for *expected* failure paths (malformed upload, unresolvable wiki page); `raise` is reserved for genuinely exceptional, programmer-error states.

## Comments & Documentation

- Prefer expressive code over comments: fix the code before reaching for a comment.
- `@doc`/`@moduledoc` (part of the public contract, expected on every public module/function in the Gateways and Contexts layers) are separate from inline `#` comments (only non-obvious *why*, never *what*, never commented-out code).
- `@moduledoc false` on internal modules not part of any public API.

## Formatting

- `mix format` is non-negotiable and runs in CI.
- Step-down/newspaper ordering within a module: public API first, private helpers below, in call order, kept vertically close to their caller.
- [Credo](https://github.com/rrrene/credo) `--strict` in CI mechanically enforces naming/consistency/readability.

## Data

Elixir has no objects — every value already *is* a data structure with no attached behavior, so there's no encapsulated/exposed hybrid to guard against.

- Domain structs (`%Pattern{}`, `%Reagent{}`, `%PriceSnapshot{}`, `%ProfitResult{}`, from [ARCHITECTURE.md § Anti-Corruption Layer](ARCHITECTURE.md#1-anti-corruption-layer)) are plain structs with `@enforce_keys` for required fields — no validation or business logic embedded as struct methods; validation lives in the gateway/adapter that produces the struct.
- Don't scatter deep field-access chains (`pattern.catalog.profession.slug`) across call sites. Give the module that owns that concept a function instead of letting every caller know the internal shape.

## SOLID → Elixir Idiom

- **Single Responsibility** — `ProfitComputation` orchestrating the catalog/price join and `TsmExportParser` decoding the raw Lua export are different modules.
- **Open/Closed** — a new profession is new catalog rows and a new scrape-skill run, not a new branch in an existing module's `case`. A new feature is a new context function, not a growing `cond` inside an existing one.
- **Liskov Substitution** — any module implementing `@behaviour CatalogRepositoryGateway` must be swappable behind that behaviour with zero caller changes. This is also the exact seam [ELIXIR_TEST_MANIFESTO.md](ELIXIR_TEST_MANIFESTO.md) uses to wire in fixture-backed gateways under test.
- **Interface Segregation** — narrow, focused `@behaviour`s (`CatalogReader`, `CatalogWriter`) rather than one fat behaviour a caller only partially implements.
- **Dependency Inversion** — context/use-case modules depend on a `@behaviour`, never a concrete module. Chosen via `Application.get_env/3`, configured per Mix env (`:dev`/`:prod` → real Ecto-backed gateway, `:test` → fixture-backed gateway).

## Clean Architecture / Layering, Elixir Shape

Concentric-rings Dependency Rule: nothing in an inner ring may name, import, or know about an outer ring.

- **Entities** — plain structs (`Pattern`, `Reagent`, `PriceSnapshot`, `ProfitResult`). No `Ecto.Schema`, no `Phoenix` imports.
- **Use Cases** — plain functions in Context modules (a `ProfitComputation` context exposing `compute_results/2`). Functional core: pure input → output, no `Ecto.Repo` call, no HTTP call, no `Phoenix` reference inside these functions.
- **Gateways** — `@behaviour`s the context defines for what it needs from outside (`TsmExportGateway`, `CatalogRepositoryGateway`, `WikiScraperGateway`). Concrete implementations (the real file-parsing module, the Ecto-backed catalog repo, the real HTTP-fetching scraper) live in the imperative shell.
- **Controllers/Presenters, collapsed** — LiveView plays both roles at once: `mount/3` and `handle_event/3` (including the file-upload event) call into context functions and assign the result; the `.heex` template shapes it for display. No business logic in a template, no direct `Ecto.Repo` or gateway call from a LiveView module.
- **Frameworks & Drivers (outermost)** — Phoenix/LiveView itself, Ecto, the file-upload channel, Ecto migrations.

**Humble Object rule for LiveView:** filtering/sorting/threshold-filter logic, or a direct `Ecto.Repo`/gateway call, inside `handle_event/3` or a `.heex` template — stop. That logic belongs in a context function or a small pure formatting function next to it.

**Day-one enforcement (already in place on the sister project; carry over identically):**

1. [`boundary`](https://github.com/sasa1977/boundary), configured with groups matching the rings above, enforced at compile time. `mix compile --warnings-as-errors` turns a boundary violation into a build failure, not a local-only warning.
2. Credo `--strict`, wired into CI.

## Error Handling

- Guiding principle: validate at the boundary, fail loudly (see [ARCHITECTURE.md § 2](ARCHITECTURE.md#2-validate-at-the-boundary-fail-loudly)).
- Gateways/adapters return `{:ok, normalized}` or `{:error, %TsmExportParseError{...}}` / `{:error, %WikiPageStructureError{...}}` — a specific, named error struct, never a bare string or generic atom — the moment raw data doesn't match the expected shape.
- `raise` is reserved for genuinely exceptional/programmer-error states. Expected failure modes (malformed upload, unresolvable wiki page, missing reagent cost) are values, propagated up through context functions as `{:error, reason}` and surfaced as an explicit error assign in the LiveView, rendered as a visible error state — never swallowed by a bare `rescue` that logs and continues.
- Every error struct carries context (which table failed to decode, which pattern/item ID, which wiki page) — this is what an AI agent or maintainer sees first when a fixture-based test fails.

## Testing

Integration-first, fixture-backed, no mocks at external boundaries — see [ELIXIR_TEST_MANIFESTO.md](ELIXIR_TEST_MANIFESTO.md).

## The Boy Scout Rule

Leave code cleaner than you found it; keep drive-by cleanups small and scoped to the file already being touched.
