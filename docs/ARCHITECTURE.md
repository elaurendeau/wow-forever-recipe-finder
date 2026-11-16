# Architecture & Resilience

**Related docs:** [PRD.md](PRD.md) (what we're building) · [DATA_SOURCES.md](DATA_SOURCES.md) (verified external data shapes) · [TECH_STACK.md](TECH_STACK.md) (technology decisions) · [SCHEMA.md](SCHEMA.md) (database schema) · [CODE_STYLE.md](CODE_STYLE.md) (Elixir code style/design) · [DEPLOYMENT.md](DEPLOYMENT.md) (packaging & pipeline)

This document defines *how* the system is built so it stays resilient to changes in sources we don't control: Warcraft Wiki's page structure, and WoW Forever's own content (still in beta, actively adding patterns). **Any AI coding agent implementing or modifying catalog-scraping or TSM-parsing code should read this document — and [DATA_SOURCES.md](DATA_SOURCES.md) — before writing code.**

## Guiding Principle: Isolate What We Don't Control

We depend on Warcraft Wiki's page structure (unversioned, can change without notice) and on TSM's export format (a semi-structured Lua literal, not a documented API contract). The goal, same as the sister project: when either changes, exactly one small, well-tested part of the codebase needs to change — not features, not the schema, not the UI.

### 1. Anti-Corruption Layer

Two adapters, each converting one external, uncontrolled shape into our own internal domain model. Nothing outside an adapter ever sees the raw external shape.

- **TSM export adapter**: raw `AppData.lua` text → internal `PriceSnapshot` (a map of item ID → `%ItemPrice{price, sold_per_day, sale_confidence}`). Owns the base-32 number decode and the `LoadData("TABLE_NAME", "Region", [[return {...}]])` literal extraction — this format was fully reverse-engineered and validated against real exports this session (see [DATA_SOURCES.md § TSM Export Format](DATA_SOURCES.md#tsm-export-format)).
- **Catalog scraper adapter**: raw Warcraft Wiki HTML → internal `Pattern` (tier, skill, source, crafted item ID, `[%Reagent{item_id, quantity}]`). Owns all wiki-page-structure-specific parsing.
- Internal domain concepts, stable regardless of either source's quirks: `Pattern`, `Reagent`, `PriceSnapshot`, `ItemPrice`, `ProfitResult` (the computed join feeding [PRD.md § 7.3](PRD.md#73-feature-c--profit-computation)).
- If TSM changes its export encoding, or the wiki changes its table markup, only the one adapter that produces that domain type changes.

### 2. Validate at the Boundary, Fail Loudly

- An uploaded file that isn't a recognizable TSM export (wrong format, no usable price tables) is rejected immediately with a specific, visible error — never silently treated as "zero patterns found."
- A catalog scrape that can't find the expected pattern-table structure on a profession's wiki page fails loudly for that profession, rather than silently committing an empty or partial catalog that looks like a legitimate "nothing's profitable right now" result.
- A single pattern within an otherwise-successful scrape that can't resolve an item ID or reagent list is **flagged on that pattern, not a scrape failure** — same distinction the sister project draws between "one unresolvable market pair" (skip and count) and "the whole ingestion walk" (abort). See [PRD.md § 7.2](PRD.md#72-feature-b--profession-catalogs).

### 3. Contract Tests via Fixtures

Both adapters are tested against **saved real responses**, committed to the repo:

- TSM export adapter: real `AppData.lua` exports captured this session (three separate snapshots, taken days apart, already proven to decode correctly) become committed test fixtures.
- Catalog scraper adapter: the already-fetched Warcraft Wiki pages cached during this session's research (per-pattern pages plus the per-profession pattern-list pages) become committed fixtures, so the scraper's tests don't depend on hitting the live wiki (which is also bot-protection-sensitive — see [DATA_SOURCES.md](DATA_SOURCES.md)).
- **A real lesson from this session belongs in this test suite, not just institutional memory:** the Tailoring catalog scrape produced 6 wrong item-ID matches out of 269 (name collisions against unrelated items on the wiki — a Blacksmithing mail-armor piece, a Leatherworking item, a plate-armor piece, two removed/beta items). These were caught by cross-checking each resolved item's wiki category tags against the expected profession (e.g. a Tailoring pattern's crafted item must carry a "Tailoring_crafted_items"-type category). **This category cross-check is not an optional nicety — it is the adapter's actual correctness mechanism** and must ship as real, tested code, not a one-off manual audit. A contract test fixture capturing one of these exact collision cases (wiki page content that superficially name-matches but fails the category check) belongs in the suite.

### 4. Centralized Reference Data

The profession catalogs (patterns, reagents, tiers, sources) are the single source of truth for "what can this profession craft" — see [SCHEMA.md](SCHEMA.md). No pattern/reagent/item-ID data is ever duplicated or hardcoded into feature code; everything reads from the catalog tables.

## Processing Architecture

Unlike the sister project, there is no persistent ingestion checkpoint or change-stream to manage — both of this app's inputs are processed synchronously, in full, on demand.

### TSM Export Processing (per-request, stateless)

1. Visitor uploads a file via the LiveView upload channel.
2. The TSM export adapter decodes it in full (no incremental/partial parse — the whole file is small enough, see [DATA_SOURCES.md](DATA_SOURCES.md), to parse in one pass).
3. The resulting `PriceSnapshot` is joined in-memory against the active profession's catalog (already loaded from Postgres) to produce the `ProfitResult` list for [PRD.md § 7.3](PRD.md#73-feature-c--profit-computation).
4. The result is pushed to the LiveView session and handed to the client to persist ([TECH_STACK.md § Client persistence](TECH_STACK.md#stack)). **Nothing from this step is written to Postgres** — per [PRD.md § 7.6](PRD.md#76-feature-f--client-owned-persistence), the server holds no record of the upload once the response is sent.
5. A parse or join failure (malformed file, empty price tables, a catalog that doesn't exist yet for the requested profession) surfaces a specific error to the visitor — never a blank or silently-empty table.

### Catalog Construction (manual, per profession)

> **Update 2026-11-16:** reagent lists, skills and the pattern set in `priv/catalog_seeds/*.json` now come from Wowhead's WoW Forever spell data, read from a real browser session. The Warcraft Wiki scrape below produced Classic-era reagents and Season of Discovery items; see [DATA_SOURCES.md § Wowhead](DATA_SOURCES.md#wowhead-wow-forever-recipe-data). The steps below describe the original wiki pipeline.

Implements [PRD.md § 7.2](PRD.md#72-feature-b--profession-catalogs), run via a `.claude/skill` (see [TECH_STACK.md § Catalog refresh](TECH_STACK.md#catalog-refresh)):

1. Scrape the profession's pattern-list page(s) on Warcraft Wiki for every pattern: name, tier, skill, source.
2. For each pattern, resolve its crafted item's own wiki page to extract its Wowhead item ID, **then validate via the category cross-check described above** before accepting the match.
3. Resolve each reagent the same way.
4. A pattern whose wiki page doesn't exist yet (new WoW Forever content, undocumented) is **currently dropped from the seed file** rather than kept with the fact recorded — `Pattern.crafted_item_id` has no nullable path through `CatalogSeeder`/the schema to store one at all (confirmed: both the real `tailoring.json` and `enchanting.json` seeds omit these patterns entirely, ~40% and ~40% of their respective candidate lists). Recording them properly (a `crafted_item_id` nullable column, a seeder/UI path for "not yet on the wiki" as its own visible state) is real, scoped work, not yet done — WoW Forever is live beta content, so this gap will keep mattering as more content ships undocumented.
5. The result replaces that profession's catalog atomically (same principle as the sister project's generation-swap — a bad/partial scrape run must never leave the catalog half-overwritten) — see [SCHEMA.md](SCHEMA.md) for the concrete mechanism.

## Failure Handling

- Upload failures (bad format, empty tables) surface a specific, visible error — never a blank/stale table with no explanation.
- The UI always shows when the currently-displayed data was computed ([PRD.md § 7.7](PRD.md#77-feature-g--data-freshness-indicator)), sourced from the client-held upload timestamp, so staleness is always visible rather than silently trusted.
- A catalog scrape that fails partway through commits nothing — no half-built catalog ever becomes the active one for a profession.

## Credential Handling

No external source currently in use requires authentication — Warcraft Wiki is public and unauthenticated; the TSM export is a file the visitor already has, not a credentialed API call. Standing principle if this ever changes: **never hold or use a single shared credential on behalf of all visitors.** Each visitor's own credential, used only for that visitor's own requests — same principle as the sister project, for the same reason (no shared quota/rate-limit exposure).

## Open Questions

- Whether the catalog-construction scrape (step 2 above) should be formalized as its own standalone Elixir module usable both from the `.claude/skill` and from a future automated path, or stay a script invoked by the skill — deferred until the second or third profession's catalog is built and the actual reuse shape is clearer.
