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
  Loads every profession catalog under priv/catalog_seeds/*.json — see
  docs/ARCHITECTURE.md § Catalog Construction. Safe to re-run: each
  file's catalog is replaced atomically, not appended. Run in a release
  via bin/seed (no Mix available there, hence a Release function rather
  than priv/repo/seeds.exs, which delegates here for dev/test use).
  """
  def seed do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, fn _repo -> load_catalog_seeds() end)
    end
  end

  defp load_catalog_seeds do
    :recipe_finder
    |> :code.priv_dir()
    |> Path.join("catalog_seeds")
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.each(fn path ->
      IO.puts("Loading catalog from #{path}...")
      WowForeverRecipeFinder.CatalogSeeder.load_from_file!(path)
    end)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
