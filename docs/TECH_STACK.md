# Tech Stack

**Related docs:** [PRD.md](PRD.md) (what we're building) · [ARCHITECTURE.md](ARCHITECTURE.md) (how we isolate ourselves from external sources) · [DATA_SOURCES.md](DATA_SOURCES.md) (verified external data shapes) · [SCHEMA.md](SCHEMA.md) (database schema) · [CODE_STYLE.md](CODE_STYLE.md) (Elixir code style/design) · [DEPLOYMENT.md](DEPLOYMENT.md) (packaging & pipeline)

## Decision: same stack as poe-currency-flip, different reason

The sister project ([poe-currency-flip](https://github.com/elaurendeau/poe-currency-flip)) is server-rendered because GGG's Currency Exchange API sends no CORS header, forcing all ingestion server-side. **That constraint does not apply here** — this app's input is a file the visitor uploads from their own browser, which has no CORS problem; parsing it client-side was a real option.

Phoenix/LiveView + Postgres was chosen anyway, for a different reason: this app needs a shared, server-owned **profession catalog** (every pattern, its tier, its reagents — scraped from Warcraft Wiki) that every visitor's uploaded prices get joined against. That catalog is exactly the same shape as the sister project's `vendor_recipe`/`divination_card` reference tables — static, rebuilt occasionally by a scrape skill, read by every request. Keeping one Elixir/Phoenix/Postgres stack across both projects also means one set of skills, one deployment pattern, one place to look things up — not re-deriving a second stack's worth of conventions for a project this similarly shaped.

**What's genuinely different from the sister project, by explicit decision:** nothing about an uploaded file or its computed results is stored in Postgres, or anywhere server-side, past the lifetime of the request that processed it. The server parses the upload and computes the joined profit table in memory, returns it to the LiveView session, and the client is responsible for persisting it (`localStorage`) — see [ARCHITECTURE.md § Client-Owned Results](ARCHITECTURE.md#client-owned-results) and [PRD.md § 7.6](PRD.md#76-feature-f--client-owned-persistence). Postgres here holds only the shared catalog, never a visitor's personal data.

## Stack

| Layer | Choice | Why |
|---|---|---|
| Application | Elixir 1.18 + Phoenix 1.7 + LiveView 1.0 | Same version pins as poe-currency-flip. Owns catalog storage, upload parsing, and profit computation in one process; LiveView pushes the computed table to the browser, which then persists it client-side itself. |
| Database | PostgreSQL (via Ecto) | Stores only the profession catalogs (patterns, reagents, tiers, sources) — see [SCHEMA.md](SCHEMA.md). No per-visitor data ever lands here. |
| Schema migrations | Ecto Migrator | Versioned migration files under `app/priv/repo/migrations/`, same convention as the sister project. |
| Client persistence | Browser `localStorage` | Holds the most recent computed profit table per profession, plus the upload timestamp for the freshness indicator ([PRD.md § 7.7](PRD.md#77-feature-g--data-freshness-indicator)). Not cookies — the data volume (hundreds of rows per profession) is well past what a cookie can hold. Replaced wholesale on each new upload; no history retained ([PRD.md § 7.6](PRD.md#76-feature-f--client-owned-persistence)). |
| Communication | None — server-rendered | Same as the sister project: LiveView's persistent connection, no separate REST/GraphQL API. The one addition here is a LiveView file-upload channel (Phoenix's built-in `allow_upload`/`live_file_input`) for the TSM export itself. |

## Hosting (free tier)

Identical to poe-currency-flip, reusing the same accounts:

| Component | Where | Notes |
|---|---|---|
| Application | [Render.com](https://render.com) free web service (Docker) | Same cold-start tradeoff as the sister project (~20-60s after ~15 min idle) — accepted for the same reason: occasional, manual use, not continuous traffic. See [DEPLOYMENT.md](DEPLOYMENT.md). |
| Database | [Neon.tech](https://neon.tech) free Postgres | Serverless, scale-to-zero, requires `ssl: true`. Holds only catalog data, so its total size stays small and stable regardless of how many visitors use the site. |

## Catalog refresh

Each profession's catalog is rebuilt by a manual `.claude/skill` (mirroring the sister project's `refresh-currency-names`/`refresh-item-icons-catalog` skills), not a scheduled job — see [PRD.md § 7.2](PRD.md#72-feature-b--profession-catalogs). Run deliberately, its diff reviewed, and committed as a new seed/migration-adjacent dataset. WoW Forever is still in beta and adds patterns between runs (observed directly this session — several Enchanting wands existed in live price data with no wiki page yet at scrape time), so a catalog is a snapshot of "what the wiki documents as of this run," not a claim of total completeness.

## UI Style

**Direction:** dark trading-terminal aesthetic, directly inspired by [poe-currency-flip](https://github.com/elaurendeau/poe-currency-flip)'s own UI (see its [TECH_STACK.md § UI Style](https://github.com/elaurendeau/poe-currency-flip/blob/main/docs/TECH_STACK.md)) — near-black background, warm gold/amber accent (rather than their orange — a merchant/currency association that fits this project's framing), green for profit, monospace for every numeric column. Dense, scannable rows over whitespace-heavy cards.

**Reference implementation:** [docs/mockups/recipe-finder-reference.html](mockups/recipe-finder-reference.html) — a working (non-framework) HTML/CSS/vanilla-JS mockup with real tab-switching across all ten professions (sample data for Tailoring/Enchanting, an explicit "not scraped yet" placeholder state for the rest) and the settled table/filter layout. Open it directly in a browser. Treat it the same way the sister project treats its own `docs/mockups/*.html`: the visual source of truth for layout, over any prose description here. When implementing the real LiveView table/tab component, match this reference rather than reinterpreting the prose above.

**Row/table structure:**
1. **Item** — pattern/crafted-item name, with its tier shown as a muted subtitle line beneath.
2. **Skill** — required skill level, right-aligned, monospace.
3. **Source** — Trainer / Drop / Vendor / Quest, shown as a small pill.
4. **Sold/day** — monospace, with an inline min-value filter built into the column header (not a separate filter bar).
5. **Confidence** — sale confidence percentage, monospace, inline min-value filter.
6. **Price** — current price, monospace, inline max-value filter.
7. **Profit/day** — net profit per day, monospace, color-coded (green when positive), inline min-value filter.

**Tabs + sub-filters stacked:** profession tabs across the top; directly below them, a row of source-type checkboxes (Trainer/Drop/Vendor/Quest) that filter the active tab's table — same stacked-filter pattern as the sister project's mode-tabs-plus-category-checkboxes.

**Explicitly not carried over from the sister project's UI:** no favorites/pinning (considered and declined for v1 — see [PRD.md § 4 Non-Goals](PRD.md#4-non-goals) framing; may revisit later), no right-click context menus.
