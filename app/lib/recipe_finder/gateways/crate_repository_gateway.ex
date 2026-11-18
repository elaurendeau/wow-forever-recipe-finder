defmodule WowForeverRecipeFinder.Gateways.CrateRepositoryGateway do
  @moduledoc """
  What the application needs from waylaid-crate-catalog storage, per
  docs/CODE_STYLE.md § SOLID (Dependency Inversion) and
  docs/ARCHITECTURE.md § Anti-Corruption Layer. The real
  implementation is `EctoCrateRepositoryGateway`.
  """

  alias WowForeverRecipeFinder.WaylaidCrate

  @doc "Every waylaid crate in the catalog, fill options preloaded, as plain `WaylaidCrate` structs."
  @callback list_crates() :: [WaylaidCrate.t()]
end
