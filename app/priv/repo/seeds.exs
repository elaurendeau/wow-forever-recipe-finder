# Loads every profession catalog under priv/catalog_seeds/*.json into
# Postgres — see docs/ARCHITECTURE.md § Catalog Construction and
# WowForeverRecipeFinder.CatalogSeeder. Run with: mix run priv/repo/seeds.exs
# Safe to re-run: each file's catalog is replaced atomically, not appended.
#
# Delegates to WowForeverRecipeFinder.Release.seed/0 so dev/test (this
# script, which has Mix available) and prod (bin/seed, which doesn't)
# share the exact same loading logic.

WowForeverRecipeFinder.Release.seed()
