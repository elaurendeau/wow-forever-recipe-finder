# Catalog Refresh: Extracting WoW Forever Recipes from Wowhead

**Related docs:** [DATA_SOURCES.md § Wowhead](DATA_SOURCES.md#wowhead-wow-forever-recipe-data) (data-shape reference) · [ARCHITECTURE.md § Catalog Construction](ARCHITECTURE.md#catalog-construction-manual-per-profession) · [SCHEMA.md](SCHEMA.md) (what the seed files load into)

This is the step-by-step procedure for producing `app/priv/catalog_seeds/<slug>.json`, the recipe catalog for each profession, from Wowhead's WoW Forever data. Follow it whenever WoW Forever patches recipes, or whenever a recipe's mats in the app look wrong.

**Last run:** 2026-11-16. All 12 crafting professions, 2,013 recipes.

---

## 1. Why it works this way

- **Wowhead is the source of truth for Forever recipes.** Warcraft Wiki mostly lists the original Classic recipes. Forever changed many of them, so the old wiki scrape had wrong mats on 213 of 693 patterns. See [DATA_SOURCES.md § Wowhead](DATA_SOURCES.md#wowhead-wow-forever-recipe-data) for the details.
- **It must run in a real browser that a person is operating.** Wowhead returns HTTP 403 (Cloudflare bot protection) to scripts, `curl`, server code and headless tools. **Don't try to work around that**: no user-agent spoofing, no headless browsers, no proxies. The extraction is a script you paste into your own browser's DevTools console while you're on the page.
- **There's no scraping, only reading data the page already has.** Every Wowhead recipe-list page embeds its whole recipe table as JavaScript data (`g_listviews.spells.data`) and the names of every referenced item (`g_items`). The script reads those two objects. It makes no requests to Wowhead beyond the page you already opened.

## 2. What you need

- A desktop browser (Chrome, Edge, Firefox) with DevTools.
- This repo checked out locally, on a branch cut from `main`.
- Python 3, for the validation step.
- About 10 minutes for all 12 professions.

## 3. The script

`app/priv/catalog_seeds/tools/wowhead_forever_export.js`

It defines one console function, `exportForeverSeed()`. Run on a supported page, it:

1. Works out which profession the page is from the URL.
2. Refuses to run if Wowhead served its generic all-professions list instead of the profession's own list (see [Troubleshooting](#7-troubleshooting)).
3. Fetches the **current committed seeds from `main` on GitHub** (raw.githubusercontent.com, not Wowhead). It uses them only to keep existing `wiki_slug` values stable and as a fallback for `source`.
4. Turns every craft on the page into a seed pattern (mapping rules in [§ 6](#6-how-wowhead-data-maps-to-a-seed-file)).
5. Prints a summary table in the console and downloads `forever_seed_<slug>.json`.

`exportForeverSeed({ download: false })` builds and returns `{ summary, seed }` without downloading, so you can inspect the result first.

## 4. Profession pages

| Seed file (`<slug>.json`) | Wowhead page | Recipes on 2026-11-16 |
|---|---|---|
| `alchemy` | https://www.wowhead.com/forever/spells/professions/alchemy | 176 |
| `blacksmithing` | https://www.wowhead.com/forever/spells/professions/blacksmithing | 429 |
| `enchanting` | https://www.wowhead.com/forever/spells/professions/enchanting | 56 |
| `engineering` | https://www.wowhead.com/forever/spells/professions/engineering | 249 |
| `leatherworking` | https://www.wowhead.com/forever/spells/professions/leatherworking | 510 |
| `tailoring` | https://www.wowhead.com/forever/spells/professions/tailoring | 409 |
| `mining` | https://www.wowhead.com/forever/spells/professions/mining | 17 |
| `herbalism` | https://www.wowhead.com/forever/spells/professions/herbalism | 3 |
| `skinning` | https://www.wowhead.com/forever/spells/professions/skinning | 3 |
| `cooking` | https://www.wowhead.com/forever/spells/**secondary-skills**/cooking | 128 |
| `firstaid` | https://www.wowhead.com/forever/spells/**secondary-skills**/first-aid | 30 |
| `fishing` | https://www.wowhead.com/forever/spells/**secondary-skills**/fishing | 3 |

Notes:
- **Cooking, First Aid and Fishing are secondary skills.** Their pages are under `/secondary-skills/`, not `/professions/`.
- **First Aid's seed slug is `firstaid`** (no hyphen), matching the app's tab list. The Wowhead URL uses `first-aid`.
- **Enchanting only includes recipes that create an item:** rods, oils, wands, idols, librams and so on. Plain enchants create no item, so there's nothing to sell or price; the script drops them.
- **Mining** is mostly smelting (ore → bars), plus Forever's camping items (Lodestone, Rock Garden, Molten Foundry).
- **Herbalism, Skinning and Fishing** each have only 3 crafts, all Forever camping items (e.g. Greenhouse, Camp Chair, Field Guide).
- **Comprehension** (skill 3012) is a new Forever secondary skill taught by **mage trainers** (Maginor Dumas, Archmage Shymm, ...). **It has no recipes**: its spells ("Comprehend Scroll", "Research") read the 17 scrolls you find in the world, e.g. "Scroll: KWYJIBO". Nothing is crafted from mats, so there's no seed file. If Wowhead ever lists crafts for it, check `https://www.wowhead.com/forever/skill=3012` and add it to the script's `PROFESSIONS` map.
- **There's no Jewelcrafting or Inscription in WoW Forever.** Wowhead's Forever skill list (`https://www.wowhead.com/forever/skills`) has neither.

To check for **new professions** after a Forever patch: open `https://www.wowhead.com/forever/skills`, look at "Professions" and "Secondary Skills", and compare against the table above.

## 5. Step by step

### Step 1: Load the script on the first page

1. Open the first page in the table, e.g. https://www.wowhead.com/forever/spells/professions/alchemy.
2. Wait until the recipe table has finished loading.
3. Open DevTools: **F12** (or Ctrl+Shift+I / Cmd+Option+I) → **Console** tab.
4. Paste the whole of `app/priv/catalog_seeds/tools/wowhead_forever_export.js` and press Enter.
   - Chrome may ask you to type `allow pasting` first. Do that, then paste again.
   - You should see: `exportForeverSeed() ready. Run: await exportForeverSeed()`.

### Step 2: Export

```js
await exportForeverSeed()
```

The browser downloads `forever_seed_<slug>.json`, usually into your Downloads folder, and the console shows a summary like:

| profession | wowheadRows | patterns | withoutReagents | unnamedItemIds | previousPatterns |
|---|---|---|---|---|---|
| alchemy | 191 | 176 | [] | [] | 182 |

Read the summary as described in [Step 4](#step-4-sanity-check-each-summary).

### Step 3: Repeat for every profession

Navigating to another page **clears the script**: each page is a fresh JavaScript context. For each remaining row of the table:

1. Open the page and wait for it to load.
2. Paste the script into the console again.
3. Run `await exportForeverSeed()`.

Tip: run `localStorage.setItem('exp', <paste the script as a string>)` once, then on each page run `eval(localStorage.getItem('exp')); await exportForeverSeed()`. `localStorage` survives navigation within wowhead.com.

If the browser asks **"This site is trying to download multiple files"**, click **Allow**.

### Step 4: Sanity-check each summary

- `withoutReagents` should be `[]`. Any name listed there is a craft Wowhead shows with no mats. It's kept with `resolution_status: "reagent_cost_incomplete"`, but look at it on Wowhead.
- `unnamedItemIds` should be `[]`. Any ID listed there was missing from the page's item data, so its `display_name` fell back to the bare number. Look the item up at `https://www.wowhead.com/forever/item=<id>` and fix the name by hand.
- `patterns` vs `previousPatterns` (the current count on `main`): a large drop usually means the page didn't load fully. Reload and export again.
- `wowheadRows` minus `patterns` is the number of non-craft rows the script dropped: profession-rank spells, enchants and internal spells. That's expected.

### Step 5: Copy the files into the repo

```bash
cd <repo>
for f in ~/Downloads/forever_seed_*.json; do
  b=$(basename "$f" .json)
  cp "$f" "app/priv/catalog_seeds/${b#forever_seed_}.json"
done
```

Move or delete old `forever_seed_*.json` files from Downloads **before** exporting. Otherwise the browser saves new ones as `forever_seed_alchemy (1).json`, and the loop above copies the stale file.

### Step 6: Validate

```bash
cd app/priv/catalog_seeds
python3 - <<'EOF'
import json, glob, collections
names = collections.defaultdict(set); errs = []
for f in sorted(glob.glob('*.json')):
    d = json.load(open(f, encoding='utf-8')); slug = d['profession']['slug']
    assert f == slug + '.json', f'{f}: profession.slug is {slug}'
    for p in d['patterns']:
        for k in ['name', 'tier', 'skill', 'wiki_slug', 'resolution_status', 'crafted_item']:
            if p.get(k) in (None, ''): errs.append((slug, p.get('name'), 'missing ' + k))
        if p['tier'] not in ('apprentice', 'journeyman', 'expert', 'artisan'): errs.append((slug, p['name'], 'tier'))
        if p['source'] not in (None, 'trainer', 'vendor', 'drop', 'quest'): errs.append((slug, p['name'], 'source'))
        ids = [r['wowhead_id'] for r in p['reagents']]
        if len(ids) != len(set(ids)): errs.append((slug, p['name'], 'duplicate reagent'))
        for it in [p['crafted_item']] + p['reagents']:
            names[it['wowhead_id']].add(it['display_name'])
    print(f"{slug:15} {len(d['patterns'])}")
print('errors:', errs or 'none')
print('item IDs with conflicting names:', [(k, v) for k, v in names.items() if len(v) > 1] or 'none')
EOF
```

Expect `errors: none` and `item IDs with conflicting names: none`. Each check matches a database constraint in `priv/repo/migrations/` (not-null columns, the `tier`/`source` enums the gateway parses, and the unique index on `pattern_reagent (pattern_id, item_id)`) or the seeder's first-write-wins item upsert.

Then run the app's tests (`cd app && mix test`). `test/recipe_finder/catalog_seeds_test.exs` checks the same structure and pins a few known Forever recipes.

### Step 7: Review the diff and spot-check in-game

```bash
git diff --stat app/priv/catalog_seeds
```

Wowhead's Forever data is datamined, and Forever is still changing. Before merging, spot-check a handful of changed recipes against the in-game profession window. Pick recipes whose mats changed (`git diff` shows them) rather than unchanged ones.

### Step 8: Commit and open a PR into `main`

The seeds load on the next deploy: `priv/repo/seeds.exs` and the release `seed` command load every `priv/catalog_seeds/*.json`.

**A new profession's tab only appears in the UI if its slug is in `@professions` in `lib/recipe_finder_web/live/recipe_finder_live.ex`**, and in the mockup `docs/mockups/recipe-finder-reference.html` per CLAUDE.md's UI rule.

`mining`, `herbalism`, `skinning` and `fishing` were extracted (see the table above) but their seed files were deliberately not committed — each has only 1–3 crafts, all Forever camping items, not a gathering profession's actual output (ore/herbs/leather aren't "crafted" from a reagent list). Not worth a tab. Re-extracting them if that changes is just re-running Step 1-6 above.

## 6. How Wowhead data maps to a seed file

Each entry of `g_listviews.spells.data` that passes the filter becomes one pattern:

| Seed field | Comes from | Notes |
|---|---|---|
| *(filter)* | `creates` present, `0 < learnedat < 9999` | Drops enchants (no item), profession-rank spells and internal spells |
| `name` | `name` | The spell's name, usually the item's name |
| `skill` | `learnedat` | Required skill in Forever |
| `tier` | from `learnedat` | ≤75 apprentice, ≤150 journeyman, ≤225 expert, otherwise artisan |
| `source` | first of `source[]` mapped: 2 → drop, 4 → quest, 5 → vendor, 6 → trainer | Otherwise the previous seed's value, otherwise `null`. Codes 16 and 21 are unmapped. |
| `wiki_slug` | previous seed's value | Otherwise the name with spaces → `_` |
| `resolution_status` | `resolved` if it has reagents | Otherwise `reagent_cost_incomplete` |
| `crafted_item.wowhead_id` | `creates[0]` | `creates` is `[itemId, minQty, maxQty]` |
| `crafted_item.display_name` | `g_items[id].name_enus` | |
| `reagents[]` | `reagents` = `[[itemId, qty], ...]` | Each with `display_name` from `g_items` and `wiki_slug` carried over or derived |
| `wowhead_spell_id` | `id` | For traceability (`https://www.wowhead.com/forever/spell=<id>`). `CatalogSeeder` ignores it. |

Patterns are sorted by skill, then name.

## 7. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Wowhead served the generic all-professions list for "<slug>"` | That URL isn't a real Forever recipe page, so Wowhead silently showed its 1,000-row all-professions list. Usually it's the wrong path segment: secondary skills need `/secondary-skills/`. |
| `Recipe table (g_listviews.spells) not found` | The page hasn't finished loading, or a consent/ad wall is covering it. Dismiss it, reload, wait, try again. |
| `Wowhead capped this list at 1000 rows` | A list hit Wowhead's display cap. No single profession is near that (largest: Leatherworking at 521 rows). If it happens, Wowhead's filters can split the page by skill range, but the script would need extending to merge the parts. |
| `Open a supported page first` | You're not on a `/forever/spells/professions/...` or `/forever/spells/secondary-skills/...` page, or the profession isn't in the script's `PROFESSIONS` map. |
| Only some files downloaded | The browser blocked repeated downloads. Allow multiple downloads for wowhead.com, or re-run `await exportForeverSeed()` on the missing pages. |
| `forever_seed_x (1).json` in Downloads | Old exports were still there. See Step 5. |
| An item name is a bare number | It's in `unnamedItemIds`; see Step 4. |
