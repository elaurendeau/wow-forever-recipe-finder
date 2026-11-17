# Data Sources

**Related docs:** [PRD.md](PRD.md) (what we're building) · [ARCHITECTURE.md](ARCHITECTURE.md) (how we isolate ourselves from these sources) · [TECH_STACK.md](TECH_STACK.md) (technology decisions) · [SCHEMA.md](SCHEMA.md) (database schema) · [CODE_STYLE.md](CODE_STYLE.md) (Elixir code style/design) · [DEPLOYMENT.md](DEPLOYMENT.md) (packaging & pipeline)

This is the contract reference for every external shape the app depends on. **This is the first file to check — and update — when TSM's export format or Warcraft Wiki's page structure changes.** See [ARCHITECTURE.md](ARCHITECTURE.md) for how these facts translate into adapters, validation, and contract tests.

## TSM Export Format (`AppData.lua`)

**Source:** the `AppData.lua` file TradeSkillMaster's `AppHelper` addon writes to `Interface/AddOns/TradeSkillMaster_AppHelper/AppData.lua` in the player's WoW install.
**Auth:** None — it's a file the visitor already has and uploads directly.
**Last verified:** 2026-11-15, by direct testing against three real exports captured on different days.

Verified facts:

- **Structure:** a Lua script, not JSON — a sequence of lines shaped `select(2, ...).LoadData("TABLE_NAME","Region_or_Realm",[[return {...}]]) --<TABLE_NAME,Region_or_Realm,timestamp>`. Parsing needs a regex extracting `(table_name, region, lua_table_literal)` per line, then a small recursive-descent-ish pass over the `{...}` literal itself (handling nested `{}` for the row list) — not a general Lua interpreter, the literal's shape is narrow and fixed.
- **Tables observed in a real export, by name:**
  - `AUCTIONDB_REGION_SALE` (region-wide) — **the primary table this app reads.** Fields: `itemString` (the item ID, as a bare integer in every case observed — never a composite itemstring like `item:12345:0:0`), `regionSale`, `regionSoldPerDay`, `regionSalePercent`.
  - `AUCTIONDB_REGION_STAT` (region-wide) — `itemString`, `regionMarketValue`.
  - `AUCTIONDB_REGION_HISTORICAL` (region-wide) — `itemString`, `regionHistorical`.
  - `AUCTIONDB_NON_COMMODITY_DATA` / `_SCAN_STAT` / `_HISTORICAL` (realm-specific, one realm per export) — `minBuyout`, `numAuctions`, `marketValueRecent` / `marketValue` / `historical` respectively. Not currently used (the app reads region-wide data only — see [PRD.md § 7.1](PRD.md#71-feature-a--tsm-export-upload--parsing)), but present and decodable the same way if a future feature needs realm-specific figures.
  - `AUCTIONDB_COMMODITY_HISTORICAL` — observed **empty** (`data={}`) in every real export checked, consistent with WoW Forever's classic-style Auction House having no separate commodity market.
  - `APP_INFO` — addon metadata (version, news), not price data; safe to ignore.
- **Number encoding — base-32, not decimal.** Every numeric field (item IDs included) is encoded as a string in a custom base-32 using the digit set `0-9` then `A-V` (the first 32 characters of `0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ`) — e.g. `"9C"` decodes to 300. This matches standard base-36 digit ordering, so a language's built-in base-N integer parser (base 32 specifically) decodes it directly with no custom digit map needed — confirmed in Python via plain `int(token, 32)`.
- **Field scaling — not all are raw copper/counts:**
  - `regionSale`, `regionMarketValue`, `regionHistorical`, `minBuyout`, `marketValueRecent`, `historical`: plain copper, no scaling.
  - `regionSoldPerDay`: divide the decoded integer by **1000** to get the real sold-per-day float (e.g. decoded `41919` → `41.919`/day). Verified by cross-referencing against realm auction counts for the same item across multiple real exports — order-of-magnitude consistent only at this scale.
  - `regionSalePercent`: divide the decoded integer by **10** to get a 0–100 percentage (verified: the maximum raw value observed across a full real export was exactly `1000`, i.e. 100.0%).
- **Only `AUCTIONDB_REGION_SALE`'s `regionSoldPerDay` carries a sale-rate figure at all** — none of the other tables have an equivalent field. This is why Feature C's profit computation ([PRD.md § 7.3](PRD.md#73-feature-c--profit-computation)) joins against this specific table rather than the realm-level ones.
- **A file with no usable data** (wrong game/TSM version, a realm/region with too little scan history) still parses as syntactically valid Lua with empty or missing tables — the adapter must treat "parsed fine, zero usable rows" as its own explicit, reported condition, not conflate it with a hard parse failure or silently show an empty table with no explanation (see [ARCHITECTURE.md § Validate at the Boundary](ARCHITECTURE.md#2-validate-at-the-boundary-fail-loudly)).

## Warcraft Wiki (Profession Pattern & Reagent Data)

**Source:** [warcraft.wiki.gg](https://warcraft.wiki.gg) — the community Warcraft wiki (formerly hosted as a Fandom/Gamepedia property), which maintains WoW Forever–specific pages.
**Auth:** None (public wiki).
**Last verified:** 2026-11-15, by direct testing scraping real Tailoring and Enchanting pattern lists.

Verified facts:

- **Per-profession pattern-list page**, one per profession, named `Forever_<profession>_patterns` for most professions (confirmed: `Forever_tailoring_patterns`) or `Forever_<profession>_formulas` for at least Enchanting (confirmed: `Forever_enchanting_formulas` — **don't assume the `_patterns` suffix holds for every profession; check each one directly before scraping it**). Each page has up to four HTML tables, one per tier (Apprentice/Journeyman/Expert/Artisan), columns: Item (name + wiki link), Skill, Type, New? (a WoW-Forever-added-content flag), and — confirmed present for Tailoring, **absent** for Enchanting — Source (Trainer/Vendor/Drop/Quest).
- **Per-item page** (`/wiki/<Item_Name>`, spaces as underscores) carries, in its "External links" section, a link to Wowhead in one of **three observed URL shapes**: `wowhead.com/item=N`, `wowhead.com/classic/item=N`, or `wowhead.com/forever/item=N`. **A scraper matching only the first shape silently misses roughly two-thirds of real items** — confirmed directly this session: the original extractor using only the bare `item=N` pattern resolved 230/269 Tailoring items; broadening to all three shapes closed nearly all of the remainder with zero additional network requests (the pages were already fetched, cached, and sitting unparsed for the missed fields).
- **Materials/reagents table** on an item's page: caption text varies (`"Reagents:"`, `"Materials required"`, `"Materials needed"`, `"Relevant items"` all observed) and at least two distinct cell layouts exist. An extractor must handle both; a caption-text match alone isn't sufficient to find the table reliably.
- **Category tags are the real correctness check for an item-ID match, not optional metadata.** Every item page carries `/wiki/Category:...` links; a genuine profession-crafted item carries a category containing that profession's name (e.g. `Tailoring_crafted_items`). **Confirmed real failure mode this session:** scraping Tailoring by name-match alone produced 6 wrong matches out of 269 (ambiguous names resolving to an unrelated wiki page) — a Blacksmithing mail-armor item, a Leatherworking item, a plate-armor item, a cosmetic item, and two removed/beta-only items, none of them Tailoring at all. All 6 were caught, after the fact, by checking each resolved item's own category tags against the expected profession — see [ARCHITECTURE.md § Contract Tests via Fixtures](ARCHITECTURE.md#3-contract-tests-via-fixtures) for why this check belongs in the scraper itself, not a one-off manual audit.
- **Not every pattern has a wiki page yet.** WoW Forever is live beta content; roughly 40% of Tailoring's pattern list had no resolvable wiki page at time of scraping (confirmed: the page literally doesn't exist, not a fetch failure) — see [ARCHITECTURE.md § Catalog Construction](ARCHITECTURE.md#catalog-construction-manual-per-profession) for how this is recorded rather than treated as an error.
- **Rate limiting / access:** plain, unauthenticated GET requests work reliably with no special headers. **`wowhead.com` itself returns HTTP 403 (Cloudflare bot protection) to automated requests and must never be fetched directly** — every fact above comes from `warcraft.wiki.gg` alone, which has no such protection. No published rate limit was found; this project's own scraping used a conservative, deliberately chosen **1.0–1.8s randomized delay between every single sequential request, zero concurrency**, with a 30–60s backoff on any 429/503/challenge response — across several hundred real requests this session, this threshold was never hit even once. Treat that cadence as the floor, not something to tune faster without a real reason.

## Wowhead (WoW Forever recipe data)

**Source:** Wowhead's WoW Forever spell list per profession: `https://www.wowhead.com/forever/spells/professions/<slug>` for primary professions, `https://www.wowhead.com/forever/spells/secondary-skills/<slug>` for Cooking, First Aid and Fishing. Confirmed for all 12 crafting professions; the full list and the step-by-step extraction procedure are in [CATALOG_REFRESH.md](CATALOG_REFRESH.md).
**Auth:** None, but **automated requests are blocked** (HTTP 403, Cloudflare). See the rule above: never fetch it from a script. Read it only from a real, human-operated browser session.
**Last verified:** 2026-11-16, by reading the live pages in a browser.
**Procedure:** [CATALOG_REFRESH.md](CATALOG_REFRESH.md) and `app/priv/catalog_seeds/tools/wowhead_forever_export.js`.

## Craftsman's Writs (`priv/writ_seeds/craftsmans_writs.json`)

**Source:** each Craftsman's Writ quest page under `wowhead.com/forever/quest=<id>` (same 403-to-scripts rule as above — browser-read only). Feeds [PRD.md § 7.8](PRD.md#78-feature-h--craftsmans-writ-route-optimizer).

- **`hand_in.reaction` is `{alliance: N, horde: N}` with `N` one of `1` (friendly), `0` (neutral), `-1` (hostile) — verified against the real 150-writ extraction, not assumed from documentation.** An earlier reading of this field in this project ("0 means that faction can't turn this in") was wrong and was caught by checking the data itself: that reading produced 35 writs reported `{alliance: 0, horde: 0}` simultaneously, which can't be true for genuinely completable content. The real extraction has **zero** writs with a `-1` anywhere (added 2026-11-17) — every placed hand-in is either friendly-to-both (71), neutral-to-both (36, one of them with a malformed `{alliance: null, horde: null}` reaction object rather than `0/0`), friendly-Alliance-only (10), or friendly-Horde-only (5). `WritCatalogSeeder.friendly_factions/1` only ever records `1` (strictly friendly) into `hand_in_friendly_to`; neutral and "no reaction data at all" both end up as `[]` and **must not be conflated** when filtering by faction — see `WritResultsFilter`'s `side_match?/2` and its own comment for why a `[]` hand-in is never excluded by the faction toggle.
- **`hand_in.coordinates`** (`{x, y}`, 0–100) are percentages of the hand-in's own zone's map rectangle, not absolute canvas coordinates — confirmed by computing a known NPC's canvas position from it (via the zone rect in `world_map_vectors.json`, below) and checking it lands inside that zone's real polygon.
- **28 writs have no hand-in NPC on Wowhead at all** (`hand_in.npc_id`/`zone_id`/`coordinates`/`reaction` all absent) — recorded, not hidden, per `WritMapPlacement.unplaced_results/2` and PRD § 7.8's "listed, never dropped" rule.

## Wowhead WoW Forever World Map (`priv/world_map/world_map_vectors.json`)

**Source:** derived from Wowhead's own in-browser world-map tool (`wowhead.com/forever/world-map`) and its backing data endpoint — not downloaded as map tile images (no Blizzard map art is kept in this repo; see the now-superseded screenshot-tracing/recoloring mockup attempts this session, abandoned once this vector source was available). Feeds [PRD.md § 7.10](PRD.md#710-feature-j--craftsmans-writs-map).

- **One shared canvas.** Every continent's coastline, every zone/subzone polygon, and every town point are coordinates on one canvas (`canvas: {width, height, left}`); each continent's own placement on it is `continents[].rect`. This resolves what was an open question earlier this session (whether a Wowhead `x%/y%` hand-in coordinate was zone-local or continent-level) — it's zone-local, and `continents[].rect` / `zones[].rect` are exactly what's needed to place it on the shared canvas; see `WritMapPlacement.hand_in_pins/2`.
- **Verified independently, not just trusted:** `zones[].rect` for Durotar and the real `/way`-style coordinates for a real NPC (Sos'mol, Alterac Mountains) were cross-checked by computing the expected canvas position by hand and confirming `WritMapPlacement` produces the same point (see `writ_map_placement_test.exs`); the rendered continent shapes were also eyeballed against the real in-game world-map screenshots captured earlier this session (before this vector source existed) and match.
- **Not every zone/subzone has a name.** A handful of polygon entries carry `name: null` (decorative/unclaimed land Wowhead's own tool doesn't label) — still rendered, per the same "flagged, not hidden" convention as everywhere else in this app.
- **No map tile images, textures, or screenshots are committed anywhere in this repo** — only this vector JSON (polygons, rects, points). The map is rendered as flat-colored SVG shapes in this app's own dark theme, not Blizzard's art.

**Why it's the source of truth for reagents.** On 2026-11-16 all four committed seeds were checked recipe by recipe against this data. Only 405 of 693 patterns matched. The Warcraft Wiki pages these seeds were scraped from mostly list the **Classic** recipes, and WoW Forever changed many of them:
- Alchemy vials: many recipes use Leaded Vial or Crystal Vial instead of Empty Vial.
- Quantities: Bolt of Runecloth takes 5 Runecloth, not 4; flasks take 30/10 herbs, not 7/3.
- New Forever reagents: Viridian, Cerulean and Magenta Dye; Bloodvine; Pristine Hide/Scale; Copper Modulator; and others.

The scrape had also pulled in 75 Season of Discovery item IDs that aren't in Forever, and some reagent IDs from later expansions (e.g. `156930` for Dream/Vision Dust, `39354` for Blank Parchment). The seeds were then regenerated from this data.

Verified facts:
- The page defines `g_listviews.spells.data`: one object per profession spell. The fields used:
  - `id`: spell ID
  - `name`
  - `creates`: `[itemId, minQty, maxQty]`; absent for enchants and profession-rank spells
  - `learnedat`: required skill
  - `reagents`: `[[itemId, qty], ...]`
  - `source`: array of codes; 2 = drop, 4 = quest, 5 = vendor, 6 = trainer. Codes 16 and 21 also appear and are unmapped.
- `g_items[itemId].name_enus` gives the display name for every item ID referenced on the page.
- An unknown profession slug does **not** 404: Wowhead silently serves its generic all-professions list (title "Forever Profession Spells", capped at 1,000 rows). The exporter refuses that page.
- **Comprehension** (skill 3012, taught by mage trainers) is new in Forever but has no crafts. Its spells read found scrolls, so there's no seed for it.
- `envChange.status` (`new` / `updated` / `unchanged`) shows how Forever changed each recipe relative to Classic.

**How the seeds map from it:**
- Only spells with a `creates` item and `0 < learnedat < 9999` are kept. Enchants produce no item, and the app prices crafted items only.
- `skill` = `learnedat`.
- `tier` comes from skill: ≤75 apprentice, ≤150 journeyman, ≤225 expert, otherwise artisan. These bands match the old wiki-derived seeds' ranges.
- `source` comes from the first mapped code, falling back to the previous seed's value, otherwise null.
- `wiki_slug` (pattern and item) keeps the previous seed's value where one existed. Otherwise it's the name with spaces as underscores.
- Each pattern also records `wowhead_spell_id` for traceability. `CatalogSeeder` ignores that field.

`test/recipe_finder/catalog_seeds_test.exs` pins a few Forever-specific recipes so a regression back to Classic data fails the build.
