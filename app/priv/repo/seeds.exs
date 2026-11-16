# Loads every profession catalog under priv/catalog_seeds/*.json into
# Postgres — see docs/ARCHITECTURE.md § Catalog Construction and
# WowForeverRecipeFinder.CatalogSeeder. Run with: mix run priv/repo/seeds.exs
# Safe to re-run: each file's catalog is replaced atomically, not appended.

seeds_dir = Path.join(:code.priv_dir(:recipe_finder), "catalog_seeds")

seeds_dir
|> Path.join("*.json")
|> Path.wildcard()
|> Enum.each(fn path ->
  IO.puts("Loading catalog from #{path}...")
  WowForeverRecipeFinder.CatalogSeeder.load_from_file!(path)
end)
