defmodule WowForeverRecipeFinder.WritAtlas do
  @moduledoc """
  The use case behind docs/PRD.md § 7.8 (Craftsman's Writs Map): load the
  writs and the vector world map through the configured
  `WritAtlasGateway`, place every known hand-in on the map, and filter /
  group writs for display. Everything after `load_atlas/0` is pure — no
  I/O — so the LiveView only calls into here, per docs/CODE_STYLE.md's
  Humble Object rule.
  """

  alias WowForeverRecipeFinder.{WorldMap, Writ, WritAtlasLoadError, WritHandIn}

  @type side :: :any | :alliance | :horde

  @type criteria :: %{
          professions: MapSet.t(String.t()),
          tiers: MapSet.t(Writ.tier()),
          side: side(),
          search: String.t()
        }

  @type pin :: %{
          id: String.t(),
          npc_name: String.t() | nil,
          zone: String.t(),
          x: float(),
          y: float(),
          way_x: float(),
          way_y: float(),
          friendly_to: [WritHandIn.faction()],
          writs: [Writ.t()]
        }

  @type atlas :: %{world_map: WorldMap.t(), writs: [Writ.t()]}

  @tiers [:journeyman, :expert, :artisan]

  @doc "Loads writs + world map and places every hand-in that has zone coordinates."
  @spec load_atlas() :: {:ok, atlas()} | {:error, WritAtlasLoadError.t()}
  def load_atlas do
    with {:ok, world_map} <- gateway().load_world_map(),
         {:ok, writs} <- gateway().load_writs() do
      {:ok, %{world_map: world_map, writs: place_hand_ins(writs, world_map)}}
    end
  end

  @doc "No filter: every profession, every tier, either faction, no search text."
  @spec default_criteria() :: criteria()
  def default_criteria, do: %{professions: MapSet.new(), tiers: MapSet.new(), side: :any, search: ""}

  @doc "Writ tiers in display order."
  @spec tiers() :: [Writ.tier()]
  def tiers, do: @tiers

  @doc """
  Fills each hand-in's canvas coordinates from its zone's map rectangle:
  in-game coordinates are percentages of that rectangle. A hand-in with no
  coordinates, or in a zone the map has no rectangle for, stays unplaced.
  """
  @spec place_hand_ins([Writ.t()], WorldMap.t()) :: [Writ.t()]
  def place_hand_ins(writs, %WorldMap{zones: zones}) do
    rects = Map.new(zones, &{&1.area, &1.rect})
    Enum.map(writs, &place_hand_in(&1, Map.get(rects, &1.hand_in.zone_id)))
  end

  defp place_hand_in(%Writ{hand_in: %WritHandIn{way_x: x, way_y: y} = hand_in} = writ, {{x1, y1}, {x2, y2}})
       when is_number(x) and is_number(y) do
    %{writ | hand_in: %{hand_in | canvas_x: x1 + (x2 - x1) * x / 100, canvas_y: y1 + (y2 - y1) * y / 100}}
  end

  defp place_hand_in(writ, _no_rect), do: writ

  @doc "Whether a writ's hand-in is on the map."
  @spec placed?(Writ.t()) :: boolean()
  def placed?(%Writ{hand_in: %WritHandIn{canvas_x: x}}), do: is_number(x)

  @doc """
  Writs matching the profession / tier / search filters. A writ crafted by
  several professions matches any of them; empty profession or tier sets
  mean "all". The faction filter only applies to placed hand-ins — see
  `placed_writs/2`.
  """
  @spec filter_writs([Writ.t()], criteria()) :: [Writ.t()]
  def filter_writs(writs, criteria) do
    needle = criteria.search |> String.trim() |> String.downcase()

    Enum.filter(writs, fn writ ->
      profession_match?(writ, criteria.professions) and tier_match?(writ, criteria.tiers) and
        search_match?(writ, needle)
    end)
  end

  @doc "Filtered writs that are on the map and whose NPC is friendly to the chosen faction."
  @spec placed_writs([Writ.t()], criteria()) :: [Writ.t()]
  def placed_writs(writs, criteria) do
    writs
    |> filter_writs(criteria)
    |> Enum.filter(&(placed?(&1) and side_match?(&1, criteria.side)))
  end

  @doc "Filtered writs whose hand-in isn't known yet (PRD § 7.8: listed, never dropped)."
  @spec unplaced_writs([Writ.t()], criteria()) :: [Writ.t()]
  def unplaced_writs(writs, criteria) do
    writs
    |> filter_writs(criteria)
    |> Enum.reject(&placed?/1)
  end

  @doc "One pin per hand-in NPC, carrying the filtered writs that NPC takes, ordered by zone then NPC."
  @spec hand_in_pins([Writ.t()], criteria()) :: [pin()]
  def hand_in_pins(writs, criteria) do
    writs
    |> placed_writs(criteria)
    |> Enum.group_by(&pin_id(&1.hand_in))
    |> Enum.map(fn {id, [%Writ{hand_in: hand_in} | _] = npc_writs} ->
      %{
        id: id,
        npc_name: hand_in.npc_name,
        zone: hand_in.zone,
        x: hand_in.canvas_x,
        y: hand_in.canvas_y,
        way_x: hand_in.way_x,
        way_y: hand_in.way_y,
        friendly_to: hand_in.friendly_to,
        writs: npc_writs
      }
    end)
    |> Enum.sort_by(&{&1.zone, &1.npc_name || ""})
  end

  @doc "The pin with this id, or nil."
  @spec find_pin([pin()], String.t() | nil) :: pin() | nil
  def find_pin(_pins, nil), do: nil
  def find_pin(pins, id), do: Enum.find(pins, &(&1.id == id))

  @doc "The pin id a writ's hand-in belongs to (nil when it isn't on the map)."
  @spec pin_id_for(Writ.t()) :: String.t() | nil
  def pin_id_for(%Writ{hand_in: hand_in} = writ) do
    if placed?(writ), do: pin_id(hand_in), else: nil
  end

  @doc "Writs grouped by hand-in zone, zones alphabetical, writs in their original order."
  @spec group_by_zone([Writ.t()]) :: [{String.t(), [Writ.t()]}]
  def group_by_zone(writs) do
    writs
    |> Enum.group_by(& &1.hand_in.zone)
    |> Enum.sort_by(fn {zone, _writs} -> zone || "" end)
  end

  @doc "How many writs each profession has (a two-profession writ counts for both)."
  @spec profession_counts([Writ.t()]) :: %{String.t() => non_neg_integer()}
  def profession_counts(writs), do: writs |> Enum.flat_map(& &1.professions) |> Enum.frequencies()

  @doc "How many writs each tier has."
  @spec tier_counts([Writ.t()]) :: %{Writ.tier() => non_neg_integer()}
  def tier_counts(writs), do: writs |> Enum.map(& &1.tier) |> Enum.frequencies()

  @doc ~S|The TomTom-style waypoint for a pin, e.g. "/way Dustwallow Marsh 40.8 28".|
  @spec waypoint_command(pin()) :: String.t()
  def waypoint_command(%{zone: zone, way_x: x, way_y: y}), do: "/way #{zone} #{format_coord(x)} #{format_coord(y)}"

  defp format_coord(value) when value == trunc(value), do: Integer.to_string(trunc(value))
  defp format_coord(value), do: :erlang.float_to_binary(value * 1.0, [:compact, decimals: 1])

  # NPCs are keyed by id; a hand-in with coordinates but no NPC id falls
  # back to its zone + spot so it still gets a pin of its own.
  defp pin_id(%WritHandIn{npc_id: npc_id}) when is_integer(npc_id), do: "npc-#{npc_id}"
  defp pin_id(%WritHandIn{zone_id: zone_id, way_x: x, way_y: y}), do: "spot-#{zone_id}-#{x}-#{y}"

  defp profession_match?(writ, professions) do
    MapSet.size(professions) == 0 or Enum.any?(writ.professions, &MapSet.member?(professions, &1))
  end

  defp tier_match?(writ, tiers), do: MapSet.size(tiers) == 0 or MapSet.member?(tiers, writ.tier)

  defp search_match?(_writ, ""), do: true

  defp search_match?(writ, needle) do
    [writ.name, writ.hand_in.npc_name, writ.hand_in.zone | Enum.map(writ.required_items, & &1.display_name)]
    |> Enum.reject(&is_nil/1)
    |> Enum.any?(&String.contains?(String.downcase(&1), needle))
  end

  defp side_match?(_writ, :any), do: true
  defp side_match?(writ, side), do: side in writ.hand_in.friendly_to

  defp gateway do
    Application.get_env(
      :recipe_finder,
      :writ_atlas_gateway,
      WowForeverRecipeFinder.Gateways.PrivFileWritAtlasGateway
    )
  end
end
