defmodule WowForeverRecipeFinder.WritHandIn do
  @moduledoc """
  Where a `Writ` is turned in. `way_x`/`way_y` are in-game zone
  coordinates (0–100, what `/way` takes); `canvas_x`/`canvas_y` are the
  same point on the world-map canvas, filled in by `WritAtlas` from the
  zone's map rectangle. All four are `nil` for a writ whose hand-in isn't
  known yet. `friendly_to` lists the factions Wowhead reports the NPC as
  friendly to.
  """

  @enforce_keys [:npc_id, :npc_name, :zone, :zone_id, :way_x, :way_y, :friendly_to]
  defstruct @enforce_keys ++ [canvas_x: nil, canvas_y: nil]

  @type faction :: :alliance | :horde

  @type t :: %__MODULE__{
          npc_id: pos_integer() | nil,
          npc_name: String.t() | nil,
          zone: String.t() | nil,
          zone_id: pos_integer() | nil,
          way_x: float() | nil,
          way_y: float() | nil,
          friendly_to: [faction()],
          canvas_x: float() | nil,
          canvas_y: float() | nil
        }
end
