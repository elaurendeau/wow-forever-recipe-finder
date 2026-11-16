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

**Source:** Wowhead's WoW Forever spell list per profession, `https://www.wowhead.com/forever/spells/professions/<profession>` (confirmed for `alchemy`, `enchanting`, `engineering`, `tailoring`).
**Auth:** None, but **automated requests are blocked** (HTTP 403, Cloudflare). See the rule above: never fetch it from a script. Read it only from a real, human-operated browser session.
**Last verified:** 2026-11-16, by reading the live pages in a browser.

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
- `envChange.status` (`new` / `updated` / `unchanged`) shows how Forever changed each recipe relative to Classic.

**How the seeds map from it:**
- Only spells with a `creates` item and `0 < learnedat < 9999` are kept. Enchants produce no item, and the app prices crafted items only.
- `skill` = `learnedat`.
- `tier` comes from skill: ≤75 apprentice, ≤150 journeyman, ≤225 expert, otherwise artisan. These bands match the old wiki-derived seeds' ranges.
- `source` comes from the first mapped code, falling back to the previous seed's value, otherwise null.
- `wiki_slug` (pattern and item) keeps the previous seed's value where one existed. Otherwise it's the name with spaces as underscores.
- Each pattern also records `wowhead_spell_id` for traceability. `CatalogSeeder` ignores that field.

`test/recipe_finder/catalog_seeds_test.exs` pins a few Forever-specific recipes so a regression back to Classic data fails the build.
