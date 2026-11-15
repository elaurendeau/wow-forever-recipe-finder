# Database Schema

**Related docs:** [PRD.md](PRD.md) (what we're building) · [ARCHITECTURE.md](ARCHITECTURE.md) (resilience principles this schema follows) · [DATA_SOURCES.md](DATA_SOURCES.md) (verified external shapes this schema normalizes) · [TECH_STACK.md](TECH_STACK.md) (Postgres via Ecto) · [CODE_STYLE.md](CODE_STYLE.md) (Elixir code style/design) · [DEPLOYMENT.md](DEPLOYMENT.md) (packaging & pipeline)

This is the internal domain model referenced in [ARCHITECTURE.md § Anti-Corruption Layer](ARCHITECTURE.md#1-anti-corruption-layer) — the only shape the rest of the application ever sees. Warcraft Wiki's raw HTML is normalized into these tables at the scraper adapter boundary; nothing outside that adapter touches raw wiki markup.

**This document is the rationale; `app/priv/repo/migrations/` is the actual executable schema.** The two must stay in sync. Schema changes going forward are new Ecto migration files, never edits to the existing init migration.

**The one rule that shapes every table below:** per [PRD.md § 7.6](PRD.md#76-feature-f--client-owned-persistence) and the client-owns-its-data decision, **no visitor-uploaded data or any value computed from it is ever persisted here.** Every table in this schema is shared, static reference data — the profession catalogs — identical for every visitor. A visitor's uploaded `AppData.lua` and everything joined/computed from it lives only in-memory for the lifetime of the request, then in the visitor's own browser (`localStorage`) — never in Postgres.

## Profession catalogs (static, rebuilt per profession via a manual scrape skill)

```
profession
  id            PK
  slug          unique — e.g. "tailoring", "enchanting"
  display_name  e.g. "Tailoring"
  catalog_built_at   when this profession's catalog was last (re)built — null if never scraped

item
  id            PK
  wowhead_id    unique — the Wowhead item ID resolved per DATA_SOURCES.md § Warcraft Wiki
  display_name
  wiki_slug     the Warcraft Wiki page title this was resolved from, for traceability back to source

pattern
  id                PK
  profession_id     FK -> profession
  crafted_item_id   FK -> item
  name              pattern/recipe display name (may differ from crafted_item.display_name)
  tier              enum: apprentice | journeyman | expert | artisan
  skill             integer, required skill level
  source            enum: trainer | vendor | drop | quest, nullable (Enchanting's formula table has no Source column — see DATA_SOURCES.md § Warcraft Wiki)
  wiki_slug         the pattern's own wiki page/row, for traceability
  resolution_status enum: resolved | no_wiki_page | reagent_cost_incomplete — per ARCHITECTURE.md's
                    "flagged on that pattern, not a scrape failure" rule; a pattern with no wiki page
                    yet is still a row here, just unresolved, never silently dropped

pattern_reagent
  id          PK
  pattern_id  FK -> pattern
  item_id     FK -> item
  quantity    integer
  unique (pattern_id, item_id)
```

A pattern's crafted item and its reagents are both rows in `item` — the same table, since an item (e.g. Bolt of Linen Cloth) can be both a crafted output of one pattern and a reagent of another. `resolution_status` lives on `pattern`, not as a separate table, so an incomplete/unresolved pattern is still queryable and visible in the UI as a known gap (per [PRD.md § 7.2](PRD.md#72-feature-b--profession-catalogs)) rather than invisible.

## Deliberately not a table: anything from an uploaded TSM export

Prices, sold-per-day, sale confidence, and every computed `ProfitResult` ([ARCHITECTURE.md § Anti-Corruption Layer](ARCHITECTURE.md#1-anti-corruption-layer)) are **never written here.** A request parses the upload, joins it against the `pattern`/`pattern_reagent`/`item` tables above entirely in memory, and returns the result to the LiveView session — which hands it to the client for `localStorage` persistence (see [TECH_STACK.md § Stack](TECH_STACK.md#stack)). There is no `price_snapshot` table, no `profit_result` table, and none should be added without first revisiting the [PRD.md § 4 Non-Goals](PRD.md#4-non-goals) decision this deliberately reflects.

## No ingestion-state / generation-swap machinery

The sister project ([poe-currency-flip](https://github.com/elaurendeau/poe-currency-flip)'s `exchange_ingestion_state`/generation-tag hot-swap, per its own `SCHEMA.md`) exists because it continuously ingests a live, changing external feed that many requests read concurrently. This app has no equivalent: the profession catalog changes only when the manual scrape skill is run (infrequent, deliberate), and a visitor's uploaded data is per-request and never shared across requests. A catalog rebuild can simply run inside one transaction per profession — insert/update the new `pattern`/`pattern_reagent`/`item` rows, update `profession.catalog_built_at` — with no concurrent-reader hot-swap concern, since the data changes rarely enough that a brief lock during a rebuild is a non-issue in practice. Revisit this only if catalog rebuilds ever need to run automatically/frequently, which [TECH_STACK.md § Catalog refresh](TECH_STACK.md#catalog-refresh) deliberately decided against for now.
