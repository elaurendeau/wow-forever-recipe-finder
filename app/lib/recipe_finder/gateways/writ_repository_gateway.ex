defmodule WowForeverRecipeFinder.Gateways.WritRepositoryGateway do
  @moduledoc """
  What the application needs from writ-catalog storage, per
  docs/CODE_STYLE.md § SOLID (Dependency Inversion) and
  docs/ARCHITECTURE.md § Anti-Corruption Layer. The real
  implementation is `EctoWritRepositoryGateway`.
  """

  alias WowForeverRecipeFinder.Writ

  @doc "Every writ in the catalog, required items and reputation rewards preloaded, as plain `Writ` structs."
  @callback list_writs() :: [Writ.t()]
end
