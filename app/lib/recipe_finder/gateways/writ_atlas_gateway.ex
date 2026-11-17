defmodule WowForeverRecipeFinder.Gateways.WritAtlasGateway do
  @moduledoc """
  What `WritAtlas` needs from storage, per docs/CODE_STYLE.md § SOLID
  (Dependency Inversion). The real implementation is
  `PrivFileWritAtlasGateway`, reading the committed JSON under `priv/`.
  """

  alias WowForeverRecipeFinder.{WorldMap, Writ, WritAtlasLoadError}

  @doc "Every Craftsman's Writ, hand-in canvas coordinates not yet filled in."
  @callback load_writs() :: {:ok, [Writ.t()]} | {:error, WritAtlasLoadError.t()}

  @doc "The vector world map: continent coastlines and zone polygons."
  @callback load_world_map() :: {:ok, WorldMap.t()} | {:error, WritAtlasLoadError.t()}
end
