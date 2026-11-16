# Deployment & Packaging

**Related docs:** [TECH_STACK.md](TECH_STACK.md) (what's hosted where and why) · [SCHEMA.md](SCHEMA.md) (Ecto migrations, run automatically per this doc) · [ARCHITECTURE.md](ARCHITECTURE.md) (resilience principles) · [CODE_STYLE.md](CODE_STYLE.md) (Elixir code style/design)

Same deployment shape as the sister project ([poe-currency-flip](https://github.com/elaurendeau/poe-currency-flip)) — Docker on Render, Postgres on Neon, migrations chained into the release start command, GitHub Actions gating deploy on tests passing. Differences from it are called out explicitly below; everything else, assume identical and copy its actual CI/CD workflow file as the starting point rather than rewriting one from scratch.

## Repo layout

```
app/             Elixir 1.18 + Phoenix 1.7 + LiveView 1.0
docs/            This doc set
.github/workflows/ci-cd.yml   Build+test on every push; deploy only after tests pass on main
```

## Live site

Same as the sister project: the production URL is **not** written in this repo, stored instead as a GitHub Actions repository variable (`PRODUCTION_URL`) visible to collaborators, not public repo visitors. Expect the same ~20-60s cold-start delay after idle (see [TECH_STACK.md](TECH_STACK.md)).

## Local Development

**Prerequisites:** Docker Desktop for local Postgres, [mise](https://mise.jdx.dev/) (or your own Erlang/Elixir install) for `mix`/`iex`.

```bash
docker compose up --build
```

Then, from `app/`:

```bash
mix deps.get
mix ecto.setup   # or mix ecto.create && mix ecto.migrate
mix phx.server
```

Open `http://localhost:4000`. **One extra local-dev step this project needs that the sister project doesn't:** the Postgres database starts empty — there's no live external API to populate it from. Run the catalog-building `.claude/skill` at least once per profession you want to test against locally (see [TECH_STACK.md § Catalog refresh](TECH_STACK.md#catalog-refresh)), or seed from a committed catalog export, before expecting the UI to show anything beyond an empty/not-built-yet state.

## Packaging

**Docker**, same rationale as the sister project: a container image from `app/Dockerfile` (via `mix phx.gen.release --docker`) runs identically on Render, Fly.io, Cloud Run, or a laptop. Build context is `app/`; Render's **Root Directory** is `app`, **Dockerfile Path** is `Dockerfile` relative to that root.

**Migrations run via a chained release command**, same as the sister project and for the same reason (Render's free tier has no separate Pre-Deploy Command): `./migrate && exec ./server`, invoked as a single token since Render's Docker Command field doesn't reliably parse shell operators. **This still applies even though per-request writes never happen** ([SCHEMA.md](SCHEMA.md)) — the migration step is about schema structure (creating the `profession`/`pattern`/`item`/`pattern_reagent` tables), not about data, and runs the same way regardless of how the data in those tables gets populated.

**Build-info footer**, same mechanism as the sister project: reads `RENDER_GIT_COMMIT` in production, falls back to `.git/HEAD` locally, `"unknown"` otherwise.

## CI/CD — `.github/workflows/ci-cd.yml`

- `test-app` — on every push/PR to `dev` or `main`: `mix compile --warnings-as-errors`, `mix credo --strict`, `mix test`.
- `deploy-app` — on push to `main` (or manual dispatch from any branch), gated on `test-app` succeeding. A single `curl -X POST` to a Render deploy hook URL (`RENDER_DEPLOY_HOOK_URL` secret). **Render's own git-triggered auto-deploy must be turned off** in its dashboard — the Actions deploy hook is the only path to a deploy.

Migrations run automatically on every deploy via the chained start command — no separate pipeline step needed.

## First-time setup walkthrough

Same two platforms, same free tier, as [TECH_STACK.md](TECH_STACK.md) — reuse the existing Neon/Render accounts from the sister project rather than creating new ones, unless billing/quota separation between the two projects turns out to matter later.

### 1. Neon (database)

A **new** Neon project/database for this app, separate from the sister project's — the catalog schema here is entirely different data, no reason to share an instance. Copy the connection string, adapt to an `ecto://` URL for Render.

### 2. Render (app)

1. New **Web Service**, this repo. **Environment:** Docker. **Root Directory:** `app`. **Dockerfile Path:** `Dockerfile`.
2. **Environment Variables:** `DATABASE_URL` (from step 1), `SECRET_KEY_BASE` (`mix phx.gen.secret`), `PHX_HOST`, `PHX_SERVER=true`, `PORT=10000`.
3. **Docker Command:** leave blank — the image's own `CMD` is `/app/bin/start`, which chains `migrate` → `seed` → `server`, so no Render-specific override is needed (the same image boots correctly on any Docker host).
4. Deploy once manually (or let auto-deploy run) to confirm it boots, migrates, and seeds against the fresh Neon database.
5. **A profession's catalog ships in the repo at `priv/catalog_seeds/<slug>.json` and loads automatically on every boot via `bin/seed`** — it's safe to re-run (each file's catalog is replaced atomically). A profession with no seed file yet shows its tab as a "not scraped yet" placeholder rather than failing; run the catalog-building skill and commit its output to add one.

### 3. Wire the deploy hook into GitHub Actions

Repo Settings → Secrets and variables → Actions → add `RENDER_DEPLOY_HOOK_URL`, the URL from step 2.6 above. `ci-cd.yml`'s `deploy-app` job already references this secret name.

After this one-time setup, every merge to `main` runs the tests, and only on success, deploys via the hook.
