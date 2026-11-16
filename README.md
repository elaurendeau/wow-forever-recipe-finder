# WoW Forever Recipe Finder

A website that finds profitable crafting patterns in WoW Forever — upload your TSM AuctionDB export, see which patterns are actually worth crafting right now, one tab per profession.

Sister project: [poe-currency-flip](https://github.com/elaurendeau/poe-currency-flip) — same stack and documentation conventions, adapted where this project's constraints genuinely differ (see [docs/TECH_STACK.md](docs/TECH_STACK.md) for exactly where and why).

## Docs

- [docs/PRD.md](docs/PRD.md) — product spec: problem, goals, non-goals, features.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — system design and resilience principles. Read this before touching catalog-scraping or TSM-parsing code.
- [docs/DATA_SOURCES.md](docs/DATA_SOURCES.md) — verified external shapes (TSM export format, Warcraft Wiki page structure). Check/update this first when either changes.
- [docs/TECH_STACK.md](docs/TECH_STACK.md) — technology decisions.
- [docs/CATALOG_REFRESH.md](docs/CATALOG_REFRESH.md): step-by-step procedure for extracting every profession's WoW Forever recipes from Wowhead into `app/priv/catalog_seeds/`.
- [docs/SCHEMA.md](docs/SCHEMA.md) — database schema: the shared profession-catalog domain model.
- [docs/CODE_STYLE.md](docs/CODE_STYLE.md) — Elixir code style and design discipline. Any AI agent writing code in this repo should follow this.
- [docs/ELIXIR_TEST_MANIFESTO.md](docs/ELIXIR_TEST_MANIFESTO.md) — testing discipline: outside-in TDD, fixture-based integration tests, the Use-Case Discovery Procedure. Any AI agent writing a test should follow this.
- [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) — packaging, CI/CD pipeline, and the first-time Render/Neon setup walkthrough.
