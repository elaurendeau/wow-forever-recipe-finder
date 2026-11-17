defmodule WowForeverRecipeFinder.Gateways.WorldMapGateway do
  @moduledoc """
  What the application needs from the vector world-map source, per
  docs/CODE_STYLE.md § SOLID (Dependency Inversion). The real
  implementation is `PrivFileWorldMapGateway`.
  """

  alias WowForeverRecipeFinder.{WorldMap, WorldMapLoadError}

  @doc "The vector world map, or a specific, named error if the file is missing/malformed."
  @callback load() :: {:ok, WorldMap.t()} | {:error, WorldMapLoadError.t()}
end
