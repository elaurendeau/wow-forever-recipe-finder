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

**Added 2026-11-17, revised 2026-11-17 (twice).** A visitor checks the writs they intend to do; the page builds a shopping list — one group per selected writ, its writ item and required item(s) together — and a copy button exports it in a format the [Auctionator](https://github.com/tiny/auctionator) addon's Shopping List feature can import.

**Presentation: a FAB + popup, not an inline panel.** The first cut placed the shopping list inline in the page flow, which shifted the whole results table down every time a row was checked — rejected on sight. It now lives behind a floating action button — bottom-right (this app's own as-yet-unbuilt calculator FAB in `docs/mockups/recipe-finder-reference.html` sits bottom-left; deliberately the opposite corner here, not an inconsistency) — which only appears once at least one writ is selected. A small red badge appears on the FAB whenever the selection changes while the popup is closed, and clears the moment the popup is opened — so a visitor who's mid-browse always has an unobtrusive "something changed" signal without the page ever shifting under them.

**Numbered, grouped by writ — not merged by item name.** A second revision: each checked row shows a small number badge (1, 2, 3…, in the order checked), and the popup groups that writ's items under the same number, rather than merging same-named items from different writs into one flat deduplicated-by-name line (the first cut's approach). A visitor can now tell, at a glance, which writ a given item in the list is actually for. Numbers are a row's *current position* in the selection, recomputed live — unchecking one shifts every later number down by one, same as deleting a line from a numbered list; re-checking it later appends it at the end with whatever number that position is now. The Auctionator export text still deduplicates identical item names across groups (its format has no use for a repeated watch-list entry), and the running total cost still sums every line correctly regardless of grouping, since copper totals don't care whether they were added up per-group or all at once.

**Verified, not guessed, per CLAUDE.md's Diagnosis Discipline:** Auctionator's shopping-list export/import format was read directly from its own Lua source (`Atr_ShpList_Export_GetText` and `Atr_SList_ImportCore` in `AuctionatorConfig.lua`) rather than assumed from memory or a forum post. The real format is a `*** <List Name>` header line followed by one plain item display name per line, until the next `***` line or end of text — **no item IDs, no quantities**. Auctionator's shopping list is a watch-list of names, not a cart with amounts. This directly shapes the design below: quantities are this app's own display concern, dropped entirely from the exported text.

**Use cases:**

*Happy path:*
- Checking a writ's row checkbox shows a number badge next to it (its position in selection order) and makes the FAB appear — the results table itself never shifts.
- Clicking the FAB opens the popup: one group per selected writ, each tagged with its own number, its writ item and required item(s) listed together with quantities and (where computable) per-item and total AH cost in Recent Value, plus total reputation across every selected writ.
- The copy button copies `*** <list name>\n<item name>\n<item name>...` (every distinct item name across every group, deduplicated once) — verified-format text ready to paste into Auctionator's own Import dialog.
- Unchecking a writ removes its whole group from the list; every later writ's number shifts down by one to close the gap.
- Unchecking the last selected writ (or clicking "clear" inside the popup) empties the selection and hides the FAB and popup entirely.

*Boundary/edge conditions:*
- A selected writ with no computable cost (missing Recent Value, or `pending_quest_page` prior to the full extraction) still forms its own group, listed by name/quantity — cost and the running total show as unknown (`—`) rather than silently excluding the item or fabricating a cost.
- A required item needed in bulk (e.g. 200 Crafted Solid Shot for one real writ in the catalog) shows its real quantity inside that writ's own group; the exported Auctionator text still lists its name exactly once, since the format has no quantity field at all.
- Two different selected writs that happen to need the same item name each keep their own group and their own line for it (never merged into one line) — only the Auctionator export text, and the running total cost, treat them as what they are: two real, separate purchases.
- Checking/unchecking more rows while the popup is already open never shows the red badge — the visitor is already looking at the list, so there's nothing to flag. The badge only appears for changes made while the popup is closed, and only clears again once it's reopened.

*State-dependent variations:*
- Selection (an ordered list, not a set — order is what the number badges and group order are derived from), popup-open state, and the "unseen changes" badge all live in LiveView socket state only for this round — none of it persists across a page reload or in `localStorage`, unlike the uploaded snapshot. A deliberate v1 scope cut, not an oversight; revisit if visitors want a selection that survives a refresh.

### 7.10 Feature J — Craftsman's Writs Map

**Added 2026-11-17, revised 2026-11-17.** A second FAB, stacked above the shopping-cart one, opens a vector world map — the zone/travel-path fidelity this feature's Phase 2/3 always planned to reach (§ 7.8), arriving sooner once a real vector world-map source (`priv/world_map/world_map_vectors.json`, see [DATA_SOURCES.md](DATA_SOURCES.md#wowhead-wow-forever-world-map)) became available, rather than the screenshot-tracing/recoloring this session tried first and abandoned.

**The map starts with no writ pins on it at all.** The first cut placed every filtered writ's hand-in as a pin the moment the map opened — rejected on sight as cluttered and not actually useful for planning a route. A pin now only ever appears for a writ that's **checked** (the same checkbox selection the shopping list already uses — see § 7.9) or **currently hovered** in the table: the map is a view of the route you're actually building, not a directory of every hand-in NPC in the game.

**Hovering previews, checking commits.** Hovering a table row (while the map popup is open) makes that row's pin blink on the map — a transient preview, gone the instant you stop hovering, entirely client-side (no server round-trip: hover fires far more often than a filter change, and a pin's position never changes based on hover) via a `data-pin-id` attribute per row and a delegated listener on the table body. Checking a row's box puts its pin on persistently (no blink — a steady pin, same visual state whether the map popup is open or not, consistent with the shopping list treating the same checkbox state the same way) and adds it to the map's side panel list; unchecking removes it. Every pin — checked, hovered, or neither — is still rendered in the page's DOM from the start (for the hover listener to target instantly, no patch needed), just invisible (`opacity: 0`) until one of those two states applies.

**A faction toggle, defaulting to Horde — replacing the text-only "Horde only for now" note.** Per § 7.8's locked-in decision, the page now actually enforces it rather than just stating it: `WritResultsFilter`'s `side` criterion defaults to `:horde`, filtering both the table and which writs are even eligible for a pin identically (not two separately-filtered views of the same data). "Either"/`:any` and "Alliance" are one click away via chips next to the existing search/cost/reputation filters.

**Use cases discovered (per docs/ELIXIR_TEST_MANIFESTO.md's discovery procedure):**

*Happy path:*
- A hand-in with a known zone and in-game coordinates (`way_x`/`way_y`, percentages of that zone's own map rectangle) is placed on the shared canvas via that zone's `rect`, ready to become a pin once checked or hovered.
- Checking a writ's row puts its pin on the map (and into the panel's checked-writs list); unchecking takes it back off. Several checked writs sharing the same hand-in NPC (by Wowhead NPC id) share one pin, numbered with how many checked writs it carries; clicking it opens a side panel listing them, with a `/way <zone> <x> <y>` waypoint command and a copy button.
- Hovering a table row blinks that row's pin on the map, whether or not it's checked, then reverts the instant the mouse leaves the row (back to invisible if unchecked, back to its steady checked appearance if it is).
- Zoom (wheel + buttons), drag-to-pan, and per-continent shortcut buttons are client-side only (same `WritMap` JS hook pattern as the shopping-list's `CopyButton`) and survive every filter/pin-selection LiveView patch.

*Boundary/edge conditions:*
- A hand-in reported **neutral** (Wowhead reaction `0`) to every faction is never hidden by the faction toggle regardless of which side is selected — see docs/DATA_SOURCES.md's verified reaction semantics; only a hand-in explicitly friendly to the *other* faction only is excluded.
- A writ whose hand-in isn't known/placeable yet (no zone id, or a zone id the map has no rectangle for) can never become a pin even if checked, but is also never dropped from the page — same "listed, never dropped" rule as § 7.8's `pending_quest_page` state.
- A hand-in with coordinates but no NPC id in the data still gets its own pin, keyed by zone + spot rather than NPC id.
- A checked writ that a filter change would otherwise hide from the table stays on the map — the map (like the shopping list) reads every checked writ from the full result set, not just the currently filtered/visible rows.
- If the vector world-map file is missing or malformed, the map FAB simply doesn't render (the table/shopping-list still work) rather than crashing the page — a specific, named `WorldMapLoadError`, never a silent empty map.

*State-dependent variations:*
- Switching the faction toggle clears any currently-open pin detail panel (that pin's writs may no longer match the new filter).
- The world map itself is loaded once at mount (static reference data, identical for every visitor) — checking/unchecking a writ re-renders which of the already-loaded pins are visible, never re-fetches the map.

**Deliberately not done in this round:** matching every one of the vector file's ~50 zone/subzone polygons individually back to a specific writ's zone by name beyond what `zone_id` already resolves; a fidelity toggle between this map view and a future full flight-path-time-aware route (the map now has the real flight-master/ship/zeppelin/tram route data to build that from, but using it for actual pathing is new, scoped work, not assumed here).

### 7.11 Feature K — Merchant's Favor Crate Ranking

**Added 2026-11-18.** A third separate page, for WoW Forever's Waylaid Crate / Merchant's Favor system: a Waylaid Crate (looted or AH-bought) is filled with any ONE of several listed material bundles, which turns it into a matching-tier Sealed Crate, which is turned in via an "A Sealed Crate" quest for Merchant's Favor currency (`wowhead_id` 3402). Crates pay no reputation at all — reputation only comes from writs (§ 7.8–7.10); this feature is purely about the cheapest way to convert AH gold into Merchant's Favor.

**Scope cut, made explicitly by the user mid-session, not assumed:** the user's original ask was "choose a number of tokens OR a number of crates, get a shopping list." That requires knowing which Sealed Crate (and therefore which Merchant's Favor amount) each Waylaid Crate becomes once filled — and the delivered extraction has that mapping **unresolved**: every one of the 8 captured "A Sealed Crate" hand-in quests has `sealed_crate_id: null` (not yet read off each quest's own page), against 15 real Sealed Crate variants. Rather than guess a mapping or block the whole feature on it, the user chose, via an explicit prompted choice, to **ship the cost-ranking half now and defer the favor-target half** until a future extraction pass resolves `sealed_crate_id` on the hand-in quests (and ideally the quest→favor-amount relationship generally, since 8 quests for 15 crate variants means even a complete mapping may still be many-to-one in a way that isn't obvious yet). Nothing about the favor-target mode is modeled or persisted in this round.

**Data provenance:** a Wowhead-sourced extraction delivered on the `feat/waylaid-crates-data` branch (`app/priv/crates/waylaid_supply_crates.json` there; copied into this app as `priv/crate_seeds/waylaid_supply_crates.json`) — same extraction family/caveats as the writ catalog (§ 7.8), see [DATA_SOURCES.md](DATA_SOURCES.md#waylaid-crates-privcrate_seedswaylaid_supply_cratesjson) for the verified specifics once committed.

**Cost, same rule as every other page in this app:** a crate's own cost and every fill-option material's cost are both TSM realm-level **Recent Value** (`recent_value_copper`) — never Region Sale Avg, never a crafting-reagent cost. The cheapest priceable fill option is picked automatically for the "total cost" column, since any one option fills the crate equally well — this is a genuine optimization (pick the min), not an arbitrary default.

**Use cases discovered (per docs/ELIXIR_TEST_MANIFESTO.md's discovery procedure) — each must have a covering test:**

*Happy path:*
- A crate with a Recent Value in the visitor's snapshot, and at least one fill option that's both resolved to a real item ID and priced in that snapshot, computes `crate_cost + cheapest_fill_cost` and ranks among the rest by that total.
- Visiting this page after already uploading a snapshot on the main Recipe Finder or Writs page shows computed rows immediately — same shared `localStorage` snapshot, same `TsmSnapshot` hook, as every other page in this app.
- Setting a quantity on one or more crates' Qty input shows a shopping-list FAB; opening it groups by crate (crate line + its cheapest fill option's line, both quantity-multiplied), with an Auctionator-ready copy button — same FAB/popup/group pattern as § 7.9's writ shopping list, reusing its CSS and `AuctionatorExport` export format rather than duplicating either.

*Boundary/edge conditions:*
- **6 of the 30 captured crates have `fill_options: null`** (Wowhead rate-limited the extraction session before their options were read) — rendered with a "not captured yet" pending pill in the Cheapest Fill column, never hidden and never priced as free. All 6 are Expert/Artisan-tier Ingots/Parts/Fabrics crates.
- **Every Ore crate's fill options (Copper Ore, Tin Ore, …) resolve to `wowhead_id: null`** — not a data-entry gap specific to this feature, but the same structural finding already documented for Mining in DATA_SOURCES.md: this app's catalog seeds have no Mining/raw-ore items at all (Mining was never one of the scraped professions), so there's no id to resolve a raw-ore fill option's name against. These crates show "no priceable option," distinct from "not captured yet."
- A crate whose fill options ARE captured, but none of them has both a resolved id and a price in the visitor's own snapshot, shows the same "no priceable option" pending state — distinguished in the UI (and in `CrateEfficiencyResult.missing_data_reasons`, which can hold more than one reason at once) from "not captured yet."
- A crate itself missing a Recent Value in the snapshot (independent of whether its fill options are priceable) shows "unknown" in the Crate Cost column and a `nil` total cost — never summed as if it were free.
- A crate with several fill options where more than one is priceable picks the strictly cheapest one, not the first one listed or an arbitrary one — verified by a mixed-resolution fixture where the cheapest priceable option is not Wowhead's own listed order.
- A fill option that has a resolved item id but no price in the snapshot is excluded from the "cheapest" comparison (never treated as free/zero-cost) — only an option with a real price can win.
- `variant` (`"earthly herbs"` / `"flowering herbs"`, both only on Expert/Artisan Herbs crates) is shown alongside Category where present and omitted entirely where it's `null` — it does not apply to most crates.

*Error/failure paths:*
- An uploaded file that isn't a recognizable TSM export surfaces the same existing parse-error messages as every other page — reuses `ProfitComputation.parse_export/1`, not a reimplementation.
- A malformed crate-catalog seed entry fails the seeder loudly inside its transaction, same discipline as the writ and profession-catalog seeders.

*State-dependent variations:*
- Quantities are keyed by crate id in LiveView socket state only, same deliberate "survives this session, not a reload" scope cut as the writs' selection (§ 7.9) — not persisted to `localStorage`.
- Forgetting the snapshot on any page clears it everywhere (shared storage); visiting this page afterward shows the same no-data state as a fresh visit.

**Requirements (this round):**
- New page, linked from the main Recipe Finder's and the Writs page's nav (not a tab).
- Table columns: Qty (quantity input), Crate (name + required level, links to its Wowhead item page), Tier, Category (+ variant where present), Quality, Crate cost, Cheapest fill (material + quantity), Fill cost, Total cost — sortable by Total cost only (the other numeric columns don't need independent sort for a ranking-focused table this size).
- Search by crate name or category; a tier filter (Any/Apprentice/Journeyman/Expert/Artisan); an optional max-cost threshold — same filter-row conventions as the other two pages.
- A shopping-list FAB + popup, grouped by crate, Auctionator copy button — reusing § 7.9's CSS classes and the newly-extracted shared `AuctionatorExport` module (also now used by the writ shopping list, replacing its own prior duplicate of the same export-text logic).

**Deferred, pending the missing `sealed_crate_id` mapping (documented so a future session doesn't have to re-derive the decision):**
- **Favor-target mode** — the user's original ask: pick a target number of Merchant's Favor, or a target number of crates, and get a shopping list sized to reach it. Needs `sealed_crate_id` resolved on each of the 8 hand-in quests (and the Sealed-Crate↔Waylaid-Crate tier/quality correspondence, which the current extraction doesn't carry either) before it can be built without guessing.
- **The 6 not-yet-captured crates' fill options**, and **resolving ore/raw-material item ids** (would need a Mining catalog seed this app has never had, for any feature) — both real, scoped follow-ups, not assumed here.

### 7.12 Feature L — Realm Selector

**Added 2026-11-22.** A dropdown in the top-right of every page's topbar, listing every realm TSM has ever scanned in the visitor's uploaded export, so they can pick which realm's **Recent Value** figures apply. Cross-cutting: it affects every cost computed on all three pages (Recipe Finder, Writs, Merchant's Favor), since Recent Value is this app's one cost basis everywhere.

**Why this exists — a real, confirmed bug, not a hypothetical:** a visitor asked how the app decides which realm's prices it's showing, since there was no way to tell or control it. Checking the code directly (per CLAUDE.md's Diagnosis Discipline) turned up two real, distinct bugs, both now fixed and regression-tested:
1. **TSM keeps history for every realm it has ever scanned**, not just the one currently played, so a visitor's export can carry more than one `AUCTIONDB_NON_COMMODITY_DATA` block. The app used to silently merge them, with whichever block happened to be written last in the file winning — an arbitrary, undefined outcome that could show a stale/alt-realm price for an item instead of the current realm's. Fixed by reading each block's own trailing-comment timestamp and using it to order them, and — per this feature — by not silently picking a winner at all anymore: every realm's figures are kept separate and the visitor chooses.
2. **A base-32-encoded price whose digits all happen to be `0`–`9` was misread as a plain decimal number** — e.g. 1033 copper encodes to `"109"` in base-32, which the parser's old per-token heuristic silently read as decimal 109, a ~9.5x understatement. Confirmed against a real reported case before fixing. See [DATA_SOURCES.md](DATA_SOURCES.md#tsm-export-format-appdatalua) for the full technical explanation.

**Never blended across realms.** Switching to a realm shows that realm's own figures only — an item the selected realm never scanned shows "unknown," never a different realm's price standing in for it. This is the explicit requirement behind `PriceSnapshot.for_realm/2`'s design: rebuild every item's Recent Value from scratch for the chosen realm, not patch over the existing map.

**Defaults to the most recently scanned realm**, so a visitor who's only ever played one realm sees no behavior change at all. A visitor who's scanned several sees a sensible default and can override it.

**Persisted across every page, the same way the uploaded snapshot already is:** a separate `localStorage` key (not bundled into the snapshot blob, so switching realms never re-saves the whole multi-hundred-KB export text), restored via the same `TsmSnapshot` JS hook and `restore_snapshot` event every page already uses. A visitor who picks a realm on one page and navigates to another sees the same realm already selected — confirmed in a real browser, not just asserted. A refresh preserves the choice the same way.

**Use cases discovered:**

*Happy path:*
- A single-realm export shows no meaningful choice to make but still renders the dropdown with that one realm selected — consistent, not a special-cased hidden state.
- A multi-realm export defaults to the most recently scanned realm; picking another from the dropdown recomputes every cost on the page immediately, no re-upload needed.
- The choice follows the visitor to the other two pages and survives a page reload.

*Boundary/edge conditions:*
- An item the selected realm never scanned (but a different realm in the same export did) shows an unknown/missing Recent Value — the other realm's figure is never substituted in.
- A saved realm choice from localStorage that isn't among the current export's `available_realms` (e.g. a different file was uploaded since) is ignored safely, falling back to the new export's own default — never a crash or a stale reference.

**Deliberately not done in this round:** a per-page override (e.g. viewing Writs on one realm and Merchant's Favor on another simultaneously) — one visitor is assumed to care about one realm's economy at a time, consistent with how the uploaded snapshot itself is already shared, not per-page.
