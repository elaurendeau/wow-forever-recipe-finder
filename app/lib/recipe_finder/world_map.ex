defmodule WowForeverRecipeFinder.WorldMap do
  @moduledoc """
  The vector world map from `priv/world_map/world_map_vectors.json` —
  see docs/DATA_SOURCES.md § Wowhead WoW Forever World Map and
  docs/SCHEMA.md § Craftsman's Writ catalog (Map addition) for why
  this is loaded straight from a committed file rather than Postgres:
  it's pure rendering geometry, never filtered or joined via SQL.
  Plain struct — see docs/CODE_STYLE.md § Clean Architecture. Every
  coordinate is on Wowhead's shared world-map canvas. A polygon is
  `[outer_ring | holes]`, a ring a list of `{x, y}` points (implicitly
  closed).
  """

  @enforce_keys [:continents, :zones, :towns]
  defstruct @enforce_keys

  @type point :: {number(), number()}
  @type polygon :: [[point()]]
  @type rect :: {point(), point()}

  @type continent :: %{key: String.t(), rect: rect(), land: [polygon()]}

  @type zone :: %{
          area: pos_integer(),
          name: String.t() | nil,
          continent: String.t(),
          label: point() | nil,
          rect: rect() | nil,
          polygons: [polygon()]
        }

  @type town :: %{name: String.t(), point: point()}

  @type t :: %__MODULE__{continents: [continent()], zones: [zone()], towns: [town()]}
end
