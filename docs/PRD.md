# PRD: WoW Forever Recipe Finder

**Owner:** elaurendeau
**Last updated:** 2026-11-15

**Related docs:** [ARCHITECTURE.md](ARCHITECTURE.md) (resilience & system design) · [DATA_SOURCES.md](DATA_SOURCES.md) (verified external sources: Warcraft Wiki pattern/reagent data, TSM export format) · [TECH_STACK.md](TECH_STACK.md) (technology decisions) · [SCHEMA.md](SCHEMA.md) (database schema) · [CODE_STYLE.md](CODE_STYLE.md) (Elixir code style/design) · [DEPLOYMENT.md](DEPLOYMENT.md) (packaging & pipeline)

## 1. Overview

WoW Forever players running [TradeSkillMaster (TSM)](https://tradeskillmaster.com) accumulate a complete live snapshot of their realm's Auction House — every item's current price, sale rate, and sale confidence — in a single exported file (`AppData.lua`). That file has no information about *what can be crafted*; a profession's pattern list and reagent costs live only in community wiki pages, entirely separate from TSM's data.

This product is a website that joins the two: upload your TSM export, and see — per profession, one tab each — which patterns are actually worth crafting right now, ranked by profit and by how often the result actually sells. It is a **read-only analysis tool**: it computes and displays, it does not post auctions, craft items, or touch your TSM installation.

## 2. Problem Statement

Figuring out "what's actually profitable to craft" today means manually cross-referencing a wiki's pattern list against TSM's price data, item by item — tedious enough that most players don't do it systematically, even though real margin exists and shifts constantly (WoW Forever's market moves fast enough that even TSM's own built-in averages routinely lag reality, as repeatedly observed working with this exact data this session). TSM's own Restock/Crafting views can approximate this, but only after extensive manual per-operation price-string configuration, and only for items you've already set up — there's no single browsable, filterable view across a whole profession's pattern list ranked by live profitability and sell-through.

## 3. Goals

- Let a player upload their own TSM AuctionDB export and immediately see profitable patterns computed from their own realm's live prices — no manual TSM operation configuration required.
- Cover every WoW Forever profession eventually, one tab each, built and shipped incrementally rather than held back for full coverage.
- Surface both **profit** (gold/day) and **liquidity** (sold/day + sale confidence) side by side — a high-profit item nobody actually buys is a trap, and the UI should make that visible rather than hide it behind a single ranking number.
- Keep the player's own data entirely theirs: the uploaded price snapshot and everything computed from it lives in their browser, never persisted server-side.

## 4. Non-Goals

- No automated AH posting, crafting, or any action taken on the player's behalf — analysis only.
- No price history or trend tracking in v1 — each upload replaces the last; no stored snapshots over time (may revisit later; a deliberate simplicity choice for now, not a technical ceiling).
- No user accounts or authentication of any kind.
- No active publicizing — the site may be usable by strangers who find it, but promoting it isn't a goal for v1.
- No support for WoW versions other than WoW Forever — the scraped pattern/reagent catalogs are specific to it (other versions' profession data would need their own catalogs entirely).
- No mobile app — a responsive web page is in scope, a native app is not.

## 5. Target User

Primarily the builder (elaurendeau), extended to any other WoW Forever player who finds and uses it. Each visitor uploads their own TSM export for their own realm; nothing about one visitor's session is visible to another.

## 6. Terminology

| Term | Meaning |
|---|---|
| **TSM AuctionDB export** | The `AppData.lua` file TSM's AppHelper addon writes, containing realm- and region-wide price/volume tables (`AUCTIONDB_REGION_SALE`, `AUCTIONDB_REGION_STAT`, `AUCTIONDB_NON_COMMODITY_DATA`, etc.), numbers encoded in a custom base-32 scheme. |
| **Pattern / Recipe** | A profession recipe that produces a craftable item; scraped from Warcraft Wiki's per-profession pattern tables. |
| **Reagent** | A material consumed by a pattern; each has its own item ID and a quantity required. |
| **Tier** | A pattern's skill bracket: Apprentice, Journeyman, Expert, or Artisan. |
| **Source** | How a pattern is learned/acquired: Trainer, Vendor, Drop, or Quest. |
| **Sold/day** | `regionSoldPerDay` from the TSM export — the average number of a given item sold per day, region-wide. |
| **Sale confidence** | `regionSalePercent` from the TSM export — how consistently TSM actually observed the item listed for sale; low values mean a thin, noisy sample. |
| **Net profit/day** | `(price − total reagent cost) × sold/day` for a pattern's crafted item. |
| **Catalog** | The static, shared reference data (patterns, reagents, tiers, sources) for one profession — stored server-side in Postgres, refreshed via a manual scrape skill, identical in shape across all visitors. |

## 7. Core Features

### 7.1 Feature A — TSM Export Upload & Parsing

A visitor uploads their `AppData.lua` file. The server parses it (an Elixir port of the base-32 decode + `LoadData(...)` table extraction already built and validated in this project's research phase), extracting the region-wide `AUCTIONDB_REGION_SALE` table (item ID → price, sold/day, sale confidence) at minimum.

**Requirements:**
- Reject/clearly report a file that isn't a recognizable TSM export, rather than failing silently or crashing.
- Reject/clearly report a file with no usable price tables (e.g. from a realm/region combination with insufficient scan data).
- Parsing happens server-side (per the client-owns-its-data model, the *result* goes to the browser — the file itself is not retained after the request completes).

### 7.2 Feature B — Profession Catalogs

Server-stored, shared reference data per profession: every known pattern, its tier, skill requirement, source, crafted item ID, and full reagent list (item ID + quantity each). Built once per profession via scraping Warcraft Wiki (the same pipeline already proven for Tailoring and Enchanting this session, including the validation step that catches name-collision mismatches against the wiki's own item category tags).

**Requirements:**
- One profession at a time, shipped incrementally — Tailoring and Enchanting are complete and go first; each additional profession is its own unit of work.
- Refreshed via a manual `.claude/skill` (mirroring the reference project's `refresh-currency-names`/`refresh-item-icons-catalog` skills) — run deliberately, diffed, and committed, not automatic.
- Gaps are recorded, not hidden: a pattern with no resolvable wiki page (new content not yet documented) stays in the catalog with that fact flagged, not silently dropped.

### 7.3 Feature C — Profit Computation

For every pattern in the active profession's catalog, join the uploaded price data against the catalog to compute: current price, sold/day, sale confidence, total reagent cost, net profit per unit, net profit per day, and revenue per day.

**Requirements:**
- A pattern missing price data (illiquid or unscanned), a missing item ID, or an incomplete reagent cost is flagged with the specific reason, never silently shown as zero profit.
- Computation is deterministic from the uploaded file + the stored catalog — no live external calls during this step.

### 7.4 Feature D — One Tab Per Profession

The main view is a row of profession tabs; selecting one shows that profession's computed pattern table. A profession with no catalog yet shows a clear "not built yet" state rather than an empty table.

### 7.5 Feature E — Filterable, Sortable Results Table

**Requirements:**
- Free-text search by pattern/item name.
- Source-type toggle (Trainer / Drop / Vendor / Quest).
- Inline min/max threshold filters built into the relevant column headers (min sold/day, min confidence, max price, min profit/day) — not a separate filter bar.
- Sortable columns with a visible active-sort indicator.
- A "profitable only" toggle (hide anything with net profit ≤ 0).

### 7.6 Feature F — Client-Owned Persistence

Once a file is processed, the computed per-profession results are stored in the browser (`localStorage` — plain cookies are far too small for this volume of rows) so returning to the site without re-uploading still shows the last computed snapshot. A new upload replaces the stored snapshot entirely; no history of past uploads is kept (see Non-Goals).

### 7.7 Feature G — Data Freshness Indicator

The UI displays when the currently-shown snapshot was computed (from the upload timestamp held client-side), so a player is never looking at stale numbers without knowing it — same underlying concern as the reference project's Data Freshness Banner, adapted to a client-held timestamp rather than a server-tracked one.
