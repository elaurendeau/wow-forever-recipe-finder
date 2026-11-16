/*
 * Wowhead WoW Forever -> catalog seed exporter
 * =============================================
 *
 * Builds one `priv/catalog_seeds/<slug>.json` file from the recipe data on a
 * Wowhead "Forever Spells" profession page. It runs in a real browser's
 * DevTools console. Wowhead returns HTTP 403 (Cloudflare) to scripts, so there
 * is NO server-side or CLI version of this, and there must not be one.
 *
 * Full step-by-step procedure: docs/CATALOG_REFRESH.md.
 * Data-shape reference: docs/DATA_SOURCES.md § Wowhead (WoW Forever recipe data).
 *
 * Usage:
 *   1. Open https://www.wowhead.com/forever/spells/professions/<wowhead-slug>
 *      (e.g. .../professions/first-aid) and wait for the recipe table to load.
 *   2. Paste this whole file into the DevTools console (F12 -> Console).
 *   3. Run:   await exportForeverSeed()
 *      The browser downloads `forever_seed_<slug>.json` and the console logs a
 *      summary. Read the summary (see "Checks" in docs/CATALOG_REFRESH.md).
 *
 * Optional: exportForeverSeed({ download: false }) only builds and returns the
 * seed object (handy for inspecting it in the console before downloading).
 */
(function () {
  // Wowhead page slug -> [seed/app slug, display name]. The seed slug must match
  // the slug in RecipeFinderLive's @professions list.
  const PROFESSIONS = {
    alchemy: ["alchemy", "Alchemy"],
    blacksmithing: ["blacksmithing", "Blacksmithing"],
    enchanting: ["enchanting", "Enchanting"],
    engineering: ["engineering", "Engineering"],
    leatherworking: ["leatherworking", "Leatherworking"],
    tailoring: ["tailoring", "Tailoring"],
    mining: ["mining", "Mining"],
    herbalism: ["herbalism", "Herbalism"],
    skinning: ["skinning", "Skinning"],
    cooking: ["cooking", "Cooking"],
    "first-aid": ["firstaid", "First Aid"],
  };

  // The previous committed seeds, used only to carry over each pattern's and
  // item's `wiki_slug` (and `source` when Wowhead has no usable code), so slugs
  // stay stable between refreshes. Missing files (a profession's first export)
  // are fine.
  const PREVIOUS_SEEDS_BASE =
    "https://raw.githubusercontent.com/elaurendeau/wow-forever-recipe-finder/main/app/priv/catalog_seeds/";

  // Wowhead spell `source` codes -> schema enum. Other codes seen (16, 21, or
  // none, i.e. "learned automatically") map to null unless the previous seed
  // had a value.
  const SOURCE_CODES = { 2: "drop", 4: "quest", 5: "vendor", 6: "trainer" };

  // Same skill bands as the original wiki-derived seeds.
  const tierFor = (skill) =>
    skill <= 75 ? "apprentice" : skill <= 150 ? "journeyman" : skill <= 225 ? "expert" : "artisan";

  const toSlug = (name) => name.replace(/ /g, "_");

  async function loadPreviousSeeds() {
    const seeds = [];
    for (const [slug] of Object.values(PROFESSIONS)) {
      try {
        const res = await fetch(PREVIOUS_SEEDS_BASE + slug + ".json");
        if (res.ok) seeds.push(await res.json());
      } catch (_) {
        /* no previous seed for this profession: fine */
      }
    }
    return seeds;
  }

  window.exportForeverSeed = async function ({ download = true } = {}) {
    const pageSlug = location.pathname.match(/\/forever\/spells\/professions\/([^/?#]+)/)?.[1];
    if (!pageSlug || !PROFESSIONS[pageSlug]) {
      throw new Error(
        `Open a supported page first: https://www.wowhead.com/forever/spells/professions/<one of ${Object.keys(PROFESSIONS).join(", ")}>`
      );
    }
    const spellsLv = window.g_listviews?.spells?.data;
    if (!Array.isArray(spellsLv)) throw new Error("Recipe table (g_listviews.spells) not found. Let the page finish loading.");
    // An unknown/unsupported profession slug makes Wowhead silently serve its
    // generic "all profession spells" list (title "Forever Profession Spells",
    // capped at 1000 rows) instead of a 404. Refuse it rather than export a
    // mixed bag of other professions' recipes.
    if (/Profession Spells/.test(document.title)) {
      throw new Error(`Wowhead served the generic all-professions list for "${pageSlug}", so it has no recipe page of its own.`);
    }
    if (spellsLv.length >= 1000) throw new Error("Wowhead capped this list at 1000 rows; the export would be incomplete.");

    const [slug, displayName] = PROFESSIONS[pageSlug];
    const previous = await loadPreviousSeeds();

    const itemWikiSlug = {};
    for (const seed of previous) {
      for (const p of seed.patterns) {
        itemWikiSlug[p.crafted_item.wowhead_id] = p.crafted_item.wiki_slug;
        for (const r of p.reagents || []) itemWikiSlug[r.wowhead_id] = r.wiki_slug;
      }
    }
    const prevSeed = previous.find((s) => s.profession.slug === slug);
    const prevByItem = {};
    const prevByName = {};
    for (const p of prevSeed?.patterns || []) {
      prevByItem[p.crafted_item.wowhead_id] ||= p;
      prevByName[p.name] ||= p;
    }

    const unnamedItems = new Set();
    const item = (id) => {
      const name = window.g_items?.[id]?.name_enus;
      if (!name) unnamedItems.add(id);
      const displayName = name || String(id);
      return { wowhead_id: id, display_name: displayName, wiki_slug: itemWikiSlug[id] || toSlug(displayName) };
    };

    // Keep only real crafts: spells that create an item and have a real skill
    // requirement. This drops enchants (no item), rank/"learn profession"
    // spells (no item) and internal spells (learnedat 9999).
    const crafts = spellsLv
      .filter((s) => s.creates && s.creates[0] && s.learnedat > 0 && s.learnedat < 9999)
      .sort((a, b) => a.learnedat - b.learnedat || a.name.localeCompare(b.name));

    const patterns = crafts.map((s) => {
      const prev = prevByItem[s.creates[0]] || prevByName[s.name];
      const reagents = (s.reagents || []).map(([id, qty]) => ({ ...item(id), quantity: qty }));
      return {
        name: s.name,
        tier: tierFor(s.learnedat),
        skill: s.learnedat,
        source: (s.source || []).map((c) => SOURCE_CODES[c]).find(Boolean) || prev?.source || null,
        wiki_slug: prev?.wiki_slug || toSlug(s.name),
        resolution_status: reagents.length ? "resolved" : "reagent_cost_incomplete",
        crafted_item: item(s.creates[0]),
        reagents,
        wowhead_spell_id: s.id,
      };
    });

    const seed = { profession: { slug, display_name: displayName }, patterns };
    const summary = {
      profession: slug,
      wowheadRows: spellsLv.length,
      patterns: patterns.length,
      withoutReagents: patterns.filter((p) => !p.reagents.length).map((p) => p.name),
      unnamedItemIds: [...unnamedItems],
      previousPatterns: prevSeed ? prevSeed.patterns.length : null,
    };
    console.table([summary]);

    if (download) {
      const blob = new Blob([JSON.stringify(seed, null, 2) + "\n"], { type: "application/json" });
      const a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = `forever_seed_${slug}.json`;
      document.body.appendChild(a);
      a.click();
      a.remove();
    }
    return { summary, seed };
  };

  console.log("exportForeverSeed() ready. Run: await exportForeverSeed()");
})();
