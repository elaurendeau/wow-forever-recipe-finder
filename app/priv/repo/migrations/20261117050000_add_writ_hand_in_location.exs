defmodule WowForeverRecipeFinder.Repo.Migrations.AddWritHandInLocation do
  use Ecto.Migration

  @moduledoc """
  See docs/SCHEMA.md § Craftsman's Writ catalog (Map addition). The
  richer Wowhead extraction adds, per writ hand-in: the NPC's own
  Wowhead id (for grouping several writs under one map pin), the
  zone's Wowhead area id (to place the hand-in on the vector world
  map via that zone's rect), the in-game zone-percentage coordinates
  (`way_x`/`way_y`, what `/way` takes), and which faction(s) Wowhead
  reports the NPC as friendly to. All nullable/defaulted — a writ
  whose hand-in isn't known yet still seeds with nulls, never blocked.
  """

  def change do
    alter table(:writ) do
      add :hand_in_npc_id, :integer
      add :hand_in_zone_id, :integer
      add :hand_in_way_x, :float
      add :hand_in_way_y, :float
      add :hand_in_friendly_to, {:array, :string}, null: false, default: []
    end
  end
end
