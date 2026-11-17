defmodule WowForeverRecipeFinder.WritHandIn do
  @moduledoc """
  Where a `Writ` is turned in. See docs/PRD.md § 7.8/§ 7.10 and
  docs/SCHEMA.md § Craftsman's Writ catalog. Every field is `nil`
  (or `[]` for `friendly_to`) for a writ whose hand-in isn't known
  yet — this struct is always present on a `Writ`, never itself nil,
  so callers pattern-match on its fields rather than on its presence.

  `way_x`/`way_y` are in-game zone-percentage coordinates (0–100,
  what `/way` takes). `canvas_x`/`canvas_y` are the same point placed
  on the `WorldMap`'s shared canvas — filled in by `WritMapPlacement`
  from the zone's map rectangle, never by the gateway/seeder.
  """

  @enforce_keys [:friendly_to]
  defstruct [
    :npc_id,
    :npc_name,
    :zone,
    :zone_id,
    :way_x,
    :way_y,
    :canvas_x,
    :canvas_y,
    friendly_to: []
  ]

  @type faction :: :alliance | :horde

  @type t :: %__MODULE__{
          npc_id: pos_integer() | nil,
          npc_name: String.t() | nil,
          zone: String.t() | nil,
          zone_id: pos_integer() | nil,
          way_x: float() | nil,
          way_y: float() | nil,
          canvas_x: float() | nil,
          canvas_y: float() | nil,
          friendly_to: [faction()]
        }
end
