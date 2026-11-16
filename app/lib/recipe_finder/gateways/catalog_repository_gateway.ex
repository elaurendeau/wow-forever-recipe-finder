defmodule WowForeverRecipeFinder.Gateways.CatalogRepositoryGateway do
  @moduledoc """
  What the application needs from catalog storage, per
  docs/CODE_STYLE.md § SOLID (Dependency Inversion) and
  docs/ARCHITECTURE.md § Anti-Corruption Layer. The real implementation
  is `EctoCatalogRepositoryGateway`; a fixture-backed one is swapped in
  for tests per docs/ELIXIR_TEST_MANIFESTO.md.
  """

  alias WowForeverRecipeFinder.Pattern

  @doc "Every pattern for a profession, reagents preloaded, as plain `Pattern` structs."
  @callback list_patterns(profession_slug :: String.t()) :: [Pattern.t()]

  @doc "Every profession slug that has a catalog built at all (even an empty/stale one)."
  @callback known_profession_slugs() :: [String.t()]
end
