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

## Craftsman's Writ catalog (static, rebuilt via a manual seed import) — added 2026-11-16

Same static-reference-data principle as the profession catalogs above, for [PRD.md § 7.8](PRD.md#78-feature-h--craftsmans-writ-route-optimizer). **Deliberately not sharing the `item`/`pattern` tables above:** a writ's items are Wowhead-sourced AH-tradeable items, not Warcraft-Wiki-resolved crafting-catalog entries — `item.wiki_slug` has no meaningful value for them, and coupling the two independently-evolving datasets isn't worth the complexity for what Phase 1 needs. If a future phase needs to join a writ's required item back to a crafting pattern we already track (e.g. to compare AH cost against craft cost), that's new work, not assumed here (see PRD's Non-Goals for this feature).

```
faction
  id                 PK
  wowhead_faction_id unique — the external faction ID as the writ extraction carries it (e.g. 2586, 2587)
  display_name       e.g. "Azeroth Commerce Authority"

writ
  id                      PK
  name                    e.g. "Craftsman's Writ: Elixir of Ogre's Strength"
  wowhead_quest_id        unique — the quest_id the extraction carries, so a reseed can upsert by identity
  writ_item_wowhead_id    the AH-bought item that starts the writ (not a FK into `item` — see above)
  writ_item_display_name
  profession_slugs        {:array, :string} — almost always one slug, occasionally two (e.g. an item craftable
                           by either Alchemy or Engineering) — never assume exactly one
  tier                    enum: apprentice | journeyman | expert | artisan (same bands as pattern.tier)
  repeat                  nullable string — only a literal "daily" is trusted; null means "not yet confirmed
                           either way" per PRD § 7.8's edge-case list, never "one-time"
  hand_in_npc_name        nullable — some writs genuinely have no named NPC yet (a container, or unresolved)
  hand_in_npc_id          nullable — the NPC's own Wowhead id; groups several writs under one map pin
  hand_in_zone            nullable
  hand_in_zone_id         nullable — the zone's Wowhead area id, used to place the hand-in on the vector
                           world map (see "World map vectors" below) via that zone's rect; null for the
                           same writs `hand_in_zone`/`hand_in_npc_name` are null for (hand-in not known yet)
  hand_in_way_x           nullable float — in-game zone-percentage coordinate (0-100), what `/way` takes
  hand_in_way_y           nullable float — same, Y axis
  hand_in_friendly_to     {:array, :string}, default [] — which faction(s) ("alliance"/"horde") Wowhead
                           reports the hand-in NPC as friendly to. **Not** "which faction(s) can turn this
                           in" — added 2026-11-17, see docs/DATA_SOURCES.md for why 0 ("neutral") is
                           deliberately excluded from this list rather than treated as "blocked"
  reward_money_copper     integer, default 0 — every writ seen in the first extraction is 0; still a real
                           field, not assumed to always be
  resolution_status       enum: complete | pending_quest_page — mirrors the extraction's own `data_status`;
                           `pending_quest_page` means required items aren't known yet, not that none exist,
                           and the writ is still a row here, visible, never dropped (same rule as
                           pattern.resolution_status above)

writ_required_item
  id            PK
  writ_id       FK -> writ
  wowhead_id    the turn-in item's item ID
  display_name
  quantity      integer

  unique (writ_id, wowhead_id)

writ_reputation_reward
  id          PK
  writ_id     FK -> writ
  faction_id  FK -> faction
  amount      integer

  unique (writ_id, faction_id)
```

**Deliberately not modeled in Phase 1:** `rewards.items` / `rewards.item_choices` from the extraction (bonus reward items a writ grants) aren't persisted at all yet — Phase 1's ranking only counts reputation and `reward_money_copper`, per PRD § 7.8's Non-Goals. Adding them is a future, scoped extension, not assumed here.

## Waylaid Crate catalog (static, rebuilt via a manual seed import) — added 2026-11-18

Same static-reference-data principle as the writ catalog above, for [PRD.md § 7.11](PRD.md#711-feature-k--merchants-favor-crate-ranking). **Deliberately not sharing the writ tables above, or `item`/`pattern`:** a crate's fill materials are a mix of Wowhead-sourced AH-tradeable items (same family as writ turn-ins) and, for Ore crates, raw materials this app's catalog seeds have never resolved an id for at all (Mining was never scraped — see [DATA_SOURCES.md](DATA_SOURCES.md#waylaid-crates-privcrate_seedswaylaid_supply_cratesjson)) — not worth coupling to either existing table family for what this round needs.

```
waylaid_crate
  id                     PK
  wowhead_id             unique — the crate item's own Wowhead item id
  name                   e.g. "Waylaid Crate: Apprentice Ore"
  tier                   enum: apprentice | journeyman | expert | artisan (same bands as pattern.tier/writ.tier)
  category               e.g. "herbs", "ore", "ingots", "parts", "fabrics", "textiles", "curiosities"
  variant                nullable — e.g. "earthly herbs" / "flowering herbs"; only set on the two Expert/
                          Artisan Herbs crates that have it, null for every other crate
  quality                enum: common | uncommon
  required_level         integer
  fill_options_captured  boolean, default false — false means "Wowhead rate-limited the extraction before
                          this crate's fill options were read," not "this crate needs nothing to fill it."
                          6 of the first 30 crates captured have this false. See PRD § 7.11's edge cases.

waylaid_crate_fill_option
  id               PK
  waylaid_crate_id FK -> waylaid_crate, on_delete: delete_all
  display_name     e.g. "Copper Ore"
  wowhead_id       nullable — null means this material has no resolved id in priv/catalog_seeds (every Ore
                   crate's fill options are null here, since Mining was never one of the scraped professions
                   — a structural gap, not a per-row data-entry miss)
  quantity         integer — how many of this material fill the crate

  unique (waylaid_crate_id, display_name)
```

**Deliberately not modeled in this round:** `sealed_crate` and `hand_in_quest` (the extraction's other two top-level keys, `sealed_crates`/`hand_in_quests`) — every one of the 8 captured hand-in quests has an unresolved `sealed_crate_id: null`, so there's no reliable mapping yet from a filled crate to the Merchant's Favor amount it yields. Persisting an unmapped/guessed relationship would be worse than not persisting it at all. See PRD § 7.11's "Deferred" section — this is the single concrete blocker on the favor-target shopping-list mode the user originally asked for.

## World map vectors — deliberately NOT in Postgres — added 2026-11-17

`priv/world_map/world_map_vectors.json` (continent coastlines, zone/subzone polygons, town points — see [DATA_SOURCES.md § Wowhead WoW Forever World Map](DATA_SOURCES.md#wowhead-wow-forever-world-map)) is loaded straight from that committed file at request time by `PrivFileWorldMapGateway`, **never written to a table**, even though every other static reference dataset in this app (the profession catalogs above, the writ catalog above) lives in Postgres. This is a deliberate exception, not an inconsistency: that convention exists because catalog rows are *filtered and joined via SQL* (a pattern's reagents, a writ's reputation rewards). The world map is never filtered or joined at all — every request that needs it loads the whole file and renders it as-is (a handful of nested polygon arrays, read wholesale). Normalizing ~52 zones' worth of nested ring/point arrays into relational tables would add real schema and query complexity for zero query benefit. Revisit only if some future feature needs to filter/query map geometry in SQL, which nothing does today.

## Deliberately not a table: anything from an uploaded TSM export

Prices, sold-per-day, sale confidence, and every computed `ProfitResult` ([ARCHITECTURE.md § Anti-Corruption Layer](ARCHITECTURE.md#1-anti-corruption-layer)) are **never written here.** A request parses the upload, joins it against the `pattern`/`pattern_reagent`/`item` tables above entirely in memory, and returns the result to the LiveView session — which hands it to the client for `localStorage` persistence (see [TECH_STACK.md § Stack](TECH_STACK.md#stack)). There is no `price_snapshot` table, no `profit_result` table, and none should be added without first revisiting the [PRD.md § 4 Non-Goals](PRD.md#4-non-goals) decision this deliberately reflects.

## No ingestion-state / generation-swap machinery

The sister project ([poe-currency-flip](https://github.com/elaurendeau/poe-currency-flip)'s `exchange_ingestion_state`/generation-tag hot-swap, per its own `SCHEMA.md`) exists because it continuously ingests a live, changing external feed that many requests read concurrently. This app has no equivalent: the profession catalog changes only when the manual scrape skill is run (infrequent, deliberate), and a visitor's uploaded data is per-request and never shared across requests. A catalog rebuild can simply run inside one transaction per profession — insert/update the new `pattern`/`pattern_reagent`/`item` rows, update `profession.catalog_built_at` — with no concurrent-reader hot-swap concern, since the data changes rarely enough that a brief lock during a rebuild is a non-issue in practice. Revisit this only if catalog rebuilds ever need to run automatically/frequently, which [TECH_STACK.md § Catalog refresh](TECH_STACK.md#catalog-refresh) deliberately decided against for now.
