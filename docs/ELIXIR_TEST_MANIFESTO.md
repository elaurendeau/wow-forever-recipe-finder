# Test Manifesto (Elixir/Phoenix/LiveView)

**Related docs:** [CODE_STYLE.md](CODE_STYLE.md) (code style/design this testing discipline pairs with) · [ARCHITECTURE.md § 3 Contract Tests via Fixtures](ARCHITECTURE.md#3-contract-tests-via-fixtures) (the principle this document generalizes)

Same discipline as the sister project ([poe-currency-flip](https://github.com/elaurendeau/poe-currency-flip)), carried over near-verbatim — the philosophy doesn't change with the domain, only the fixtures do.

## Guiding Principle: Integration Is the Default, Not the Exception

Every test that exercises code crossing a boundary — a LiveView upload-event handler, a context function calling a gateway, a catalog scrape — is written as an **integration test that runs the real path end to end**, not an isolated unit test with mocked collaborators standing in for real ones.

There's no separate JSON API to contract-test apart from the UI it feeds: LiveView is one process. Mounting a LiveView and driving a real file upload already exercises parse → normalization → catalog join → profit computation → rendered HTML in one pass.

**The one deliberate carve-out:** pure, stateless functional-core functions — the base-32 number decoder, the profit/margin math, a sort comparator — still get a plain, fast `ExUnit` unit test with no I/O (see "What Still Gets a Plain Unit Test" below).

## TDD Workflow: Outside-In, Red-Green-Refactor

**Red** (failing test expressing desired behavior) → **Green** (minimum code to pass) → **Refactor**.

- The outermost Red test is usually a `Phoenix.LiveViewTest` test (uploading a real fixture export, asserting on rendered table rows) or a context-level integration test against a fixture-backed gateway — not a narrow unit test against a mock for an interface that doesn't exist yet.
- Minimum code to pass, every step.
- A red integration test must fail for the *right* reason (missing behavior), not an unrelated setup error (a fixture file typo, a malformed test catalog seed).

## Use-Case Discovery — Drill First, PRD-Trace, Then Test

1. **Drill for every use case** a behavior must satisfy before writing its test — not just the golden path. For each context function, gateway, or LiveView interaction: the happy path(s); boundary/edge conditions (an item with zero reagents, a pattern missing its item ID, a 0% confidence row, a tie in sort order); error/failure paths (a malformed upload, a wiki page with no category tags at all, a reagent that itself has no resolvable price); state-dependent variations (first visit with no `localStorage` data yet vs. a returning visitor, switching professions mid-session, re-uploading over an existing snapshot).
2. **Every discovered use case is written into `docs/PRD.md` before its test is written** — a bullet under the relevant Feature section. A use case that exists only as a test with no PRD entry, or a PRD line with no covering test, is a gap to close.
3. Only then does outside-in TDD begin.

This loop survives across sessions — a future session picking this codebase back up should find it already documented here, not have to re-derive it from a conversation it wasn't part of.

## No Mocks at the Boundary — Real Fixtures Are the Test Double

**When the app would normally parse an external shape, the test environment uses real, committed fixture files — never a mocking library standing in with hand-built data.**

- Real fixtures committed under `test/fixtures/<source>/<scenario>.ext`:
  - `test/fixtures/tsm_export/*.lua` — the three real `AppData.lua` snapshots already captured this session (different days, proving the decoder against genuinely varying real data, not one static sample), plus a deliberately malformed one for the "fail loudly" error path.
  - `test/fixtures/wiki/<profession>_patterns.html`, `test/fixtures/wiki/items/<item_slug>.html` — real captured Warcraft Wiki pages, including at least one of the real name-collision cases found this session (see [DATA_SOURCES.md § Warcraft Wiki](DATA_SOURCES.md#warcraft-wiki-profession-pattern--reagent-data)), so the category-cross-check logic has a real regression test, not just the memory of having fixed it once.
- **No mocking library (e.g. Mox) stands in for a parse/scrape call.** The `@behaviour` swap approach: in `:test`, `Application.put_env/3` points the relevant gateway at a `FixtureTsmExportGateway` / `FixtureWikiScraperGateway` that reads the real committed file and runs it through the *actual* production parsing/normalization code — only the file-read or HTTP hop is faked.
- Same rule stated in [CLAUDE.md](../CLAUDE.md): a saved real response from the actual external source in, an asserted normalized output out. Mocking remains the right tool one layer up — isolating a LiveView's own event-handling from a context it calls — never for the boundary adapter itself.

## Fixture Governance

- **Location:** `test/fixtures/<source>/`, one file per meaningfully distinct scenario.
- **Provenance:** each fixture gets a one-line note (sibling `.meta` file) recording capture date and, for a wiki fixture, the source URL.
- **Refresh discipline:** when WoW Forever's export format or the wiki's page structure is suspected to have changed, or periodically regardless, fixtures are re-captured and committed fresh. A fixture test failing right after a refresh is the intended, ideal failure mode: specific, scoped to one gateway/adapter.

## LiveView Integration Tests

- Written with `Phoenix.LiveViewTest`: `live/2` to mount, a real file upload via the test helpers for `allow_upload`/`live_file_input`, `render_click/2`/`render_change/2` for filter/sort interactions — asserting against rendered HTML, not internal `assigns` directly, except where no rendered element expresses the state being checked.
- A test for the results table mounts the LiveView, uploads a real fixture export, selects a profession tab, and asserts on the rendered rows — proving the full slice (parse → normalize → catalog join → compute → assigns → rendered HTML) in one test.

## What Still Gets a Plain Unit Test

- Pure functional-core functions with no I/O: the base-32 decoder, `compute_profit/2`, a sort comparator, a gold/silver/copper formatter. Fast, isolated `ExUnit` tests, real inputs/outputs, no fixtures needed.
- Narrow exception, not a fallback — a function needing a gateway, the database, or a fixture to exercise meaningfully gets an integration test.

## FIRST

- **Fast** — fixtures are local files. No test ever makes a real network call to Warcraft Wiki.
- **Independent** — each test sets up its own fixture-backed gateway; DB-touching tests use the Ecto Sandbox.
- **Repeatable** — a committed fixture file is deterministic.
- **Self-validating** — pass/fail on rendered HTML or returned structs.
- **Timely** — written alongside the code.

## CI Enforcement

- `mix test` runs with no real network access needed in `:test` — every boundary call is fixture-backed by design.
- A stale fixture (the wiki or TSM's format actually changed) surfaces as a specific, scoped CI failure pointing at one gateway/adapter, never a vague downstream symptom.
