# Instructions for AI coding agents

Before writing or modifying code in this repo, read the relevant docs first — do not rely on general knowledge or default conventions instead:

- [docs/CODE_STYLE.md](docs/CODE_STYLE.md) is required reading before any code change. It defines naming, function design, SOLID, and the Clean Architecture layering (Entities → Contexts → Gateways → LiveView, per Phoenix's own structure) this codebase follows, plus error-handling and testing discipline.
- [docs/ELIXIR_TEST_MANIFESTO.md](docs/ELIXIR_TEST_MANIFESTO.md) is required reading before writing any test. Outside-in TDD, fixture-based integration tests (no mocks at external boundaries), and the Use-Case Discovery Procedure for drilling every use case before writing its test.
- TSM export parsing or Warcraft Wiki scraping: also read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/DATA_SOURCES.md](docs/DATA_SOURCES.md) first.
- Database schema changes: also read [docs/SCHEMA.md](docs/SCHEMA.md) — new Ecto migration files only, never edits to the existing init migration.

Full doc index: [README.md](README.md).

**Enforcement:** compile-time boundary layering is wired up via the [`boundary`](https://github.com/sasa1977/boundary) library and `mix compile --warnings-as-errors` (see [docs/CODE_STYLE.md § Clean Architecture](docs/CODE_STYLE.md#clean-architecture--layering-elixir-shape)) — a layering violation fails the build, not just a local warning. Don't let the architecture rules be prose-only; keep this enforcement in place for any new module.

## Sister project

[poe-currency-flip](https://github.com/elaurendeau/poe-currency-flip) is the same owner's earlier project, same stack and documentation conventions by deliberate choice (see [docs/TECH_STACK.md](docs/TECH_STACK.md) for exactly what's shared and what's genuinely different). When a doc here says "same as the sister project," that's not filler — check its actual current file rather than assuming this repo's copy stays in sync forever; the two can drift.

## Branching

`main` is this repository's mainline/default branch, matching the sister project's convention. A `master` branch exists in history (the original default before the rename) — treat it as legacy; never create, target, or base new work off it. Feature branches are cut from `main`, and PRs target `main`.

## Diagnosis discipline

When discussing whether something is a bug, or why data is missing/wrong/unexpected — especially anything sourced from an uploaded TSM export or scraped from Warcraft Wiki — verify directly against the actual file/page content or the actual code path before asserting a cause. Don't present a plausible-sounding theory as a confirmed explanation; if it hasn't been checked, say that explicitly.

(Concretely, from this project's own research phase: a "Destroy value price source is configurable in Settings → Tooltip Settings" claim was made from TSM's own 2022-dated public documentation, without first checking the actual live settings screen — it was wrong for the TSM build actually in use, and the real screen had to be checked directly before giving the user a correct answer. The lesson generalizes directly to this codebase: a wiki page's table structure, a TSM export's field scaling, a category tag's exact text — check the real thing, don't extrapolate from what a doc or a memory of a similar case implies.)

## Regression discipline

Whenever a bug or gap is found and fixed, add a test (or, if genuinely untestable, a documented manual-verification step) that would have caught it, committed in the same change as the fix. Prefer fixture-based tests over mocks where the two compete — see [docs/ARCHITECTURE.md § Contract Tests via Fixtures](docs/ARCHITECTURE.md#3-contract-tests-via-fixtures) and [docs/ELIXIR_TEST_MANIFESTO.md](docs/ELIXIR_TEST_MANIFESTO.md).

(Concretely: the Tailoring catalog scrape's item-ID resolver originally matched only one of three real Wowhead URL shapes Warcraft Wiki pages actually use, silently missing roughly two-thirds of resolvable items — see [docs/DATA_SOURCES.md § Warcraft Wiki](docs/DATA_SOURCES.md#warcraft-wiki-profession-pattern--reagent-data). The fix without a fixture test covering all three shapes would be exactly the kind of regression this rule exists to prevent from recurring silently.)

## UI layout discipline

Whenever a UI layout is added or changed, check it against the approved mockup and the relevant [PRD.md](docs/PRD.md) requirement section before considering the work done. PRD.md's prose describes intent and requirements, not exact layout — when the two seem to disagree, the mockup wins on placement/structure/styling, and PRD.md wins on functional requirements (what must be shown, when, in what precision).

The settled reference is [docs/mockups/recipe-finder-reference.html](mockups/recipe-finder-reference.html) — open it directly in a browser, the same non-framework HTML/CSS/JS treatment the sister project gives its own `docs/mockups/*.html`. It started as a Claude Design-canvas artifact and was hand-converted to plain HTML/CSS/vanilla JS for this file; the two can drift if the artifact is iterated on again without this file being updated to match — this file is the one that counts for implementation.

The Craftsman's Writs page ([PRD.md § 7.8](docs/PRD.md)) has its own reference, [docs/mockups/writs-map-reference.html](docs/mockups/writs-map-reference.html) — self-contained (the real writ and vector-map data are embedded), open it directly in a browser.

When a mockup doesn't yet cover a new element, update the mockup itself in the same change, not just the real component — a mockup that's drifted out of sync with the actual UI stops being a reliable reference for the next change.
