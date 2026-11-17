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
| **Net profit** | `price × (1 − AH cut) − total reagent cost` for a pattern's crafted item — the AH cut (5%, WoW/Classic's standard) is the cut the auction house takes on a successful sale, deducted before material cost. |
| **Profit %** | Net profit as a percentage of total reagent cost (ROI on what crafting it cost) — undefined, not zero, when the craft costs nothing. |
| **Catalog** | The static, shared reference data (patterns, reagents, tiers, sources) for one profession — stored server-side in Postgres, refreshed via a manual scrape skill, identical in shape across all visitors. |
| **Craftsman's Writ** | A repeatable quest: buy a "writ" item from the AH, buy (never craft, per § 7.8) the specific item it asks for, hand both in to a named NPC in a named zone for reputation (and sometimes gold). See § 7.8. |
| **Recent Value** | `marketValueRecent` from the TSM export's realm-level `AUCTIONDB_NON_COMMODITY_DATA` table — unlike Sale Avg, never populated for commodity items. The only price figure used for Craftsman's Writ cost (§ 7.8), per this session's explicit decision. |
| **Rep per gold spent** | A writ's total reputation reward divided by its total cost in gold (writ item + every required item, all at Recent Value) — § 7.8's ranking objective. |

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

For every pattern in the active profession's catalog, join the uploaded price data against the catalog to compute: current price, sold/day, sale confidence, total reagent cost, net profit per craft (after the AH cut), and profit %.

**Requirements:**
- A pattern missing price data (illiquid or unscanned), a missing item ID, or an incomplete reagent cost is flagged with the specific reason, never silently shown as zero profit.
- Computation is deterministic from the uploaded file + the stored catalog — no live external calls during this step.

### 7.4 Feature D — One Tab Per Profession

The main view is a row of profession tabs; selecting one shows that profession's computed pattern table. A profession with no catalog yet shows a clear "not built yet" state rather than an empty table.

### 7.5 Feature E — Filterable, Sortable Results Table

**Requirements:**
- Free-text search by pattern/item name.
- Source-type toggle (Trainer / Drop / Vendor / Quest).
- Inline min/max threshold filters built into the relevant column headers (min sold/day, min confidence, max price, min profit, min profit %) — not a separate filter bar.
- Sortable columns with a visible active-sort indicator.
- A "profitable only" toggle (hide anything with net profit ≤ 0).

### 7.6 Feature F — Client-Owned Persistence

Once a file is processed, the computed per-profession results are stored in the browser (`localStorage` — plain cookies are far too small for this volume of rows) so returning to the site without re-uploading still shows the last computed snapshot. A new upload replaces the stored snapshot entirely; no history of past uploads is kept (see Non-Goals).

### 7.7 Feature G — Data Freshness Indicator

The UI displays when the currently-shown snapshot was computed (from the upload timestamp held client-side), so a player is never looking at stale numbers without knowing it — same underlying concern as the reference project's Data Freshness Banner, adapted to a client-held timestamp rather than a server-tracked one.

### 7.8 Feature H — Craftsman's Writ Route Optimizer

**Added 2026-11-16.** A separate page (not a tab on the main Recipe Finder page) for WoW Forever's Craftsman's Writ system: daily/repeatable quests bought from the Auction House as a "writ" item, completed by handing in a specific crafted/tradeable item at a specific NPC, rewarding reputation (with two factions simultaneously: Azeroth Commerce Authority and Durotar Supply and Logistics) and sometimes gold. The goal is to rank writs — and, eventually, sequence a visiting order across zones — by how efficiently they convert AH gold into reputation.

**Decisions locked in before implementation (per the drilling conversation this session):**
- **Horde only, for now.** Zone/travel-path modeling (Phase 2/3 below) assumes the Horde flight network. Alliance support is a real future goal, not a non-goal, but out of scope for this round.
- **Cost is always "buy from the AH," never "craft it yourself."** Both the writ item and every required turn-in item are costed at their TSM **Recent Value** (`recent_value_copper` — the realm-level figure, never the region-wide Sale Avg used elsewhere in this app) — explicitly chosen over the existing crafting-reagent-cost engine, even for turn-in items this app already tracks as a crafting pattern elsewhere (e.g. "Elixir of Ogre Strength" under Alchemy). This is a deliberate simplification, not an oversight.
- **Ranking objective: reputation gained per gold spent** (`total_reputation / (total_cost_copper / 10_000)`), not raw gold profit and not raw reputation.
- **Fidelity is phased.** This section covers Phase 1 only — a filterable/sortable ranked table, no pathing. Phase 2 (group writs by zone/hub) and Phase 3 (full flight-path travel-time sequencing, with a fidelity toggle across all three modes) are real planned work, deferred until more of the writ dataset is resolved and a Horde travel graph exists — see "Deferred to Phase 2/3" below.

**Data provenance:** the writ catalog comes from a Wowhead-sourced extraction (same family of source as `docs/CATALOG_REFRESH.md`'s profession catalogs, see `docs/DATA_SOURCES.md` for the exact shape once committed). The first extraction delivered to this app is **partial by design** — a `data_status` of `pending_quest_page` on a writ means its required turn-in item(s) haven't been fetched yet, not that none exist. A second, fuller extraction pass is expected to follow and must be re-seedable without manual cleanup.

**Use cases discovered (per docs/ELIXIR_TEST_MANIFESTO.md's discovery procedure) — each must have a covering test:**

*Happy path:*
- A writ with `resolution_status: :complete` (known writ item + all required items) and full AH Recent Value coverage in the visitor's uploaded snapshot computes total cost, total reputation, and rep-per-gold efficiency, and sorts among the rest by that efficiency.
- Visiting this page after already uploading a snapshot on the main Recipe Finder page shows computed rows immediately — the two pages share the same client-held snapshot (same `localStorage` keys, same `TsmSnapshot` hook), so a visitor never re-uploads per page.
- A fresh, snapshot-less visit shows the same upload prompt / empty state as the main page.

*Boundary/edge conditions:*
- A writ with `resolution_status: :pending_quest_page` (required items not yet known) is **always rendered, never dropped** — same "flagged, not hidden" rule as `Pattern.resolution_status` — with cost shown as a visible pending/unknown state, and sorts last regardless of sort direction (same nils-last convention as `ResultsFilter`).
- A writ item or required item that IS known, but has no `recent_value_copper` in the visitor's own snapshot (e.g. it's a commodity TSM only tracks region-wide — `AUCTIONDB_NON_COMMODITY_DATA` never covers these at all, confirmed in `docs/DATA_SOURCES.md`) computes a `nil` cost with a specific recorded reason — never a fabricated zero.
- A writ requiring more than one distinct turn-in item (the schema supports N, via a join table, even though every writ seen in the first extraction needs exactly one).
- A writ listing more than one profession (e.g. "Craftsman's Writ: Goblin Rocket Fuel" lists both Alchemy and Engineering) stores and displays the full set, never collapsing to one.
- `repeat: null` means **"not yet confirmed," never "non-repeating."** Only a literal `"daily"` value is trusted and surfaced as a repeat indicator; `null` renders as unknown, not as "one-time."
- A writ with no hand-in NPC name (`null`) still shows its zone; the NPC cell renders "—".
- Multiple writs sharing the same hand-in zone are both shown as distinct rows — no collapsing by zone in Phase 1 (that grouping is Phase 2's job).

*Error/failure paths:*
- An uploaded file that isn't a recognizable TSM export surfaces the same existing upload error as the main page — this page reuses `ProfitComputation.parse_export/1` rather than re-implementing parsing, so this path is already covered by existing tests and isn't retested here beyond confirming the same assign is used.
- A malformed writ-catalog seed file (missing a required field) fails the seeder loudly, inside its transaction — never silently skipping one writ and committing the rest, mirroring `CatalogSeeder`.

*State-dependent variations:*
- Forgetting the snapshot on the main Recipe Finder page also clears it here (shared storage) — visiting this page afterward shows the same no-data state.
- Re-running the writ seeder once the fuller extraction lands replaces `pending_quest_page` rows with `complete` ones **atomically** — a partial reseed must never leave some writs half-updated.

**Requirements (Phase 1 — this round):**
- New page, linked from the main Recipe Finder page's nav, not a new profession tab.
- Table columns: writ name, profession(s), tier, hand-in zone, hand-in NPC, total cost (AH Recent Value only), total reputation (both factions shown), rep-per-gold efficiency — sortable, with the same inline min/max filter-row convention as the existing results table.
- A writ with pending data is visible with a clear "awaiting extraction" indicator, not hidden and not silently costed as free.

**Deferred to Phase 2/3 (documented here so a future session doesn't have to re-derive the decision):**
- **Phase 2 — zone grouping:** group writs by a hand-authored "shares a Horde flight hub" zone grouping, order zone visits by that grouping. Needs a small, explicitly-labeled-as-approximate zone→hub reference table; not scraped/verified data, since no such verified source exists for WoW Forever specifically.
- **Phase 3 — full travel-time pathing:** a Horde flight-path/boat graph with travel-time estimates, used to compute a near-optimal full visiting order. Same provenance caveat as Phase 2, at higher fidelity and higher authoring/maintenance cost.
- **A fidelity toggle** across ranked-table / zone-grouped / full-pathing once Phase 2 and 3 exist.
- **Alliance support**, once Horde is proven out.
- **Valuing reward items** (`rewards.items`, `rewards.item_choices`) via their own AH price and folding them into the efficiency metric — not persisted at all in Phase 1; only reputation and `money_copper` are counted.
- **Any crafting-cost comparison** for turn-in items we already track as patterns elsewhere — Phase 1 always assumes buying from the AH, per the locked-in decision above.
- **Netting a non-zero `money_copper` reward into the cost side of the rep-per-gold ratio.** Every writ in the extraction delivered so far rewards 0 gold, so `reward_money_copper` is modeled and stored but not yet subtracted from cost in `WritEfficiency`. Revisit if a future extraction pass surfaces a writ with a real gold reward.

### 7.9 Feature I — Writ Shopping List

**Added 2026-11-17.** A visitor checks the writs they intend to do; the page aggregates every writ item and required item across the selection into one shopping list (quantities summed across writs that need the same item), and a copy button exports it in a format the [Auctionator](https://github.com/tiny/auctionator) addon's Shopping List feature can import.

**Verified, not guessed, per CLAUDE.md's Diagnosis Discipline:** Auctionator's shopping-list export/import format was read directly from its own Lua source (`Atr_ShpList_Export_GetText` and `Atr_SList_ImportCore` in `AuctionatorConfig.lua`) rather than assumed from memory or a forum post. The real format is a `*** <List Name>` header line followed by one plain item display name per line, until the next `***` line or end of text — **no item IDs, no quantities**. Auctionator's shopping list is a watch-list of names, not a cart with amounts. This directly shapes the design below: quantities are this app's own display concern, dropped entirely from the exported text.

**Use cases:**

*Happy path:*
- Checking a writ's row checkbox adds its writ item and required item(s) to a shopping-list panel, with quantities and (where computable) per-item and total AH cost in Recent Value.
- Two selected writs that happen to need the same item name sum to one line with the combined quantity, not two separate lines.
- The copy button copies `*** <list name>\n<item name>\n<item name>...` — verified-format text ready to paste into Auctionator's own Import dialog.
- Unchecking a writ removes its contribution from the list; if another selected writ still needs that same item, its line's quantity drops rather than disappearing.
- Clearing the whole selection hides the panel.

*Boundary/edge conditions:*
- A selected writ with no computable cost (missing Recent Value, or `pending_quest_page` prior to the full extraction) still contributes its item(s) to the shopping list by name/quantity — cost and the running total show as unknown (`—`) rather than silently excluding the item or fabricating a cost.
- A required item needed in bulk (e.g. 200 Crafted Solid Shot for one real writ in the catalog) shows its real quantity in the panel; the exported Auctionator text still lists its name exactly once, since the format has no quantity field at all.

*State-dependent variations:*
- Selection lives in LiveView socket state only for this round — it does **not** persist across a page reload or in `localStorage`, unlike the uploaded snapshot. A deliberate v1 scope cut, not an oversight; revisit if visitors want a selection that survives a refresh.
