defmodule WowForeverRecipeFinder.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :recipe_finder

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Loads every profession catalog under priv/catalog_seeds/*.json (see
  docs/ARCHITECTURE.md § Catalog Construction) and the Craftsman's Writ
  catalog under priv/writ_seeds/*.json (see docs/PRD.md § 7.8 and
  docs/SCHEMA.md § Craftsman's Writ catalog). Safe to re-run: each
  file's catalog is replaced atomically, not appended. Run in a release
  via bin/seed (no Mix available there, hence a Release function rather
  than priv/repo/seeds.exs, which delegates here for dev/test use).

  A full catalog load is a few thousand sequential queries in one
  transaction — fine locally, but Ecto's default 15s per-query timeout
  can be too tight over a hosted free-tier DB's connection/pooler
  latency. The repo-wide `timeout:` in config/runtime.exs is what
  actually raises it (an option here doesn't reliably override a single
  call's timeout); this one is kept as a harmless, explicit belt and
  suspenders.
  """
  def seed do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(
          repo,
          fn _repo ->
            load_seeds("catalog_seeds", &WowForeverRecipeFinder.CatalogSeeder.load_from_file!/1)
            load_seeds("writ_seeds", &WowForeverRecipeFinder.WritCatalogSeeder.load_from_file!/1)
            load_seeds("crate_seeds", &WowForeverRecipeFinder.CrateCatalogSeeder.load_from_file!/1)
          end,
          timeout: 120_000
        )
    end
  end

  defp load_seeds(priv_subdir, load_from_file) do
    :recipe_finder
    |> :code.priv_dir()
    |> Path.join(priv_subdir)
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.each(fn path ->
      IO.puts("Loading #{priv_subdir} from #{path}...")
      load_from_file.(path)
    end)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
