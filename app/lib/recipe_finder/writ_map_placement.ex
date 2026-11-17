defmodule WowForeverRecipeFinder.WritMapPlacement do
  @moduledoc """
  Places each `WritEfficiencyResult`'s hand-in on the `WorldMap` canvas
  and groups them into one pin per hand-in NPC — see docs/PRD.md §
  7.10 (Craftsman's Writ Map). Fetching the map goes through the
  configured `WorldMapGateway` (Dependency Inversion, per
  docs/CODE_STYLE.md § SOLID); placement/grouping itself is pure, no
  I/O — see `hand_in_pins/2`.

  In-game hand-in coordinates are percentages of a zone's own map
  rectangle (`way_x`/`way_y`, 0–100) — placing one on the shared
  canvas means resolving its `zone_id` against the matching
  `WorldMap.zone.rect` and interpolating. A hand-in whose zone isn't
  on the map, or that has no coordinates at all yet, has no canvas
  position and is never placed — see `placed?/2`.
  """

  alias WowForeverRecipeFinder.{WorldMap, WritEfficiencyResult}

  @type pin :: %{
          id: String.t(),
          npc_name: String.t() | nil,
          zone: String.t() | nil,
          x: float(),
          y: float(),
          way_x: float() | nil,
          way_y: float() | nil,
          friendly_to: [WowForeverRecipeFinder.WritHandIn.faction()],
          results: [WritEfficiencyResult.t()]
        }

  @doc "Loads the vector world map via the configured gateway."
  @spec load_world_map() ::
          {:ok, WorldMap.t()} | {:error, WowForeverRecipeFinder.WorldMapLoadError.t()}
  def load_world_map, do: world_map_gateway().load()

  @doc "Whether a result's hand-in has coordinates AND a zone the map has a rectangle for."
  @spec placed?(WritEfficiencyResult.t(), WorldMap.t()) :: boolean()
  def placed?(%WritEfficiencyResult{} = result, %WorldMap{} = world_map) do
    not is_nil(canvas_point(result.writ.hand_in, world_map))
  end

  @doc "Results whose hand-in is placed on the map."
  @spec placed_results([WritEfficiencyResult.t()], WorldMap.t()) :: [WritEfficiencyResult.t()]
  def placed_results(results, world_map), do: Enum.filter(results, &placed?(&1, world_map))

  @doc "Results whose hand-in isn't known/placeable yet — PRD § 7.8: listed, never dropped."
  @spec unplaced_results([WritEfficiencyResult.t()], WorldMap.t()) :: [WritEfficiencyResult.t()]
  def unplaced_results(results, world_map), do: Enum.reject(results, &placed?(&1, world_map))

  @doc """
  One pin per hand-in NPC, carrying every placed result at that NPC,
  sorted by zone then NPC name. A hand-in with coordinates but no NPC
  id (some writs only have the zone + spot) still gets its own pin,
  keyed by zone + coordinates instead of an NPC id.
  """
  @spec hand_in_pins([WritEfficiencyResult.t()], WorldMap.t()) :: [pin()]
  def hand_in_pins(results, %WorldMap{} = world_map) do
    results
    |> placed_results(world_map)
    |> Enum.group_by(&pin_id(&1.writ.hand_in))
    |> Enum.map(fn {id, [%WritEfficiencyResult{writ: writ} | _] = pin_results} ->
      {x, y} = canvas_point(writ.hand_in, world_map)

      %{
        id: id,
        npc_name: writ.hand_in.npc_name,
        zone: writ.hand_in.zone,
        x: x,
        y: y,
        way_x: writ.hand_in.way_x,
        way_y: writ.hand_in.way_y,
        friendly_to: writ.hand_in.friendly_to,
        results: Enum.sort_by(pin_results, & &1.writ.name)
      }
    end)
    |> Enum.sort_by(&{&1.zone || "", &1.npc_name || ""})
  end

  @doc "A writ id → pin id lookup, so a table row can be matched to its map pin without recomputing placement."
  @spec pin_id_by_writ_id([pin()]) :: %{optional(pos_integer()) => String.t()}
  def pin_id_by_writ_id(pins) do
    for pin <- pins, result <- pin.results, into: %{}, do: {result.writ.id, pin.id}
  end

  @doc ~S|The TomTom-style waypoint for a pin, e.g. "/way Dustwallow Marsh 40.8 28".|
  @spec waypoint_command(pin()) :: String.t()
  def waypoint_command(%{zone: zone, way_x: x, way_y: y}),
    do: "/way #{zone} #{format_coord(x)} #{format_coord(y)}"

  defp format_coord(value) when is_float(value) and value == trunc(value),
    do: Integer.to_string(trunc(value))

  defp format_coord(value), do: :erlang.float_to_binary(value * 1.0, [:compact, decimals: 1])

  defp pin_id(%{npc_id: npc_id}) when is_integer(npc_id), do: "npc-#{npc_id}"
  defp pin_id(%{zone_id: zone_id, way_x: x, way_y: y}), do: "spot-#{zone_id}-#{x}-#{y}"

  defp canvas_point(%{zone_id: nil}, _world_map), do: nil
  defp canvas_point(%{way_x: nil}, _world_map), do: nil
  defp canvas_point(%{way_y: nil}, _world_map), do: nil

  defp canvas_point(hand_in, %WorldMap{zones: zones}) do
    case Enum.find(zones, &(&1.area == hand_in.zone_id)) do
      %{rect: {{x1, y1}, {x2, y2}}} ->
        {x1 + (x2 - x1) * hand_in.way_x / 100, y1 + (y2 - y1) * hand_in.way_y / 100}

      _no_rect ->
        nil
    end
  end

  defp world_map_gateway do
    Application.get_env(
      :recipe_finder,
      :world_map_gateway,
      WowForeverRecipeFinder.Gateways.PrivFileWorldMapGateway
    )
  end
end
