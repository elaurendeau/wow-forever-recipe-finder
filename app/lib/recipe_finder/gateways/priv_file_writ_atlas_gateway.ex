defmodule WowForeverRecipeFinder.Gateways.PrivFileWritAtlasGateway do
  @moduledoc """
  `WritAtlasGateway` backed by the committed JSON files described in
  docs/DATA_SOURCES.md § Wowhead WoW Forever. Validates their shape at
  the boundary: a missing or malformed file is a `WritAtlasLoadError`
  naming the file, never a crash or a silently empty map.

  The data directory defaults to this app's `priv/` and can be pointed
  elsewhere with `config :recipe_finder, :writ_atlas_dir, path` (tests
  use that to exercise the error paths with real broken fixtures).
  """

  @behaviour WowForeverRecipeFinder.Gateways.WritAtlasGateway

  alias WowForeverRecipeFinder.{WorldMap, Writ, WritAtlasLoadError, WritHandIn}

  @writs_file "writs/craftsmans_writs.json"
  @world_map_file "world_map/world_map_vectors.json"
  @writ_prefix "Craftsman's Writ: "
  @tiers %{"journeyman" => :journeyman, "expert" => :expert, "artisan" => :artisan}

  @impl true
  def load_writs do
    case read_json(@writs_file) do
      {:ok, %{"writs" => writs}} when is_list(writs) -> normalize_all(writs, &normalize_writ/1, @writs_file)
      {:ok, _other} -> {:error, %WritAtlasLoadError{file: @writs_file, reason: :missing_writs_list}}
      {:error, _} = error -> error
    end
  end

  @impl true
  def load_world_map do
    with {:ok, %{"continents" => continents, "zones" => zones} = raw_map}
         when is_list(continents) and is_list(zones) <- read_json(@world_map_file),
         {:ok, continents} <- normalize_all(continents, &normalize_continent/1, @world_map_file),
         {:ok, zones} <- normalize_all(zones, &normalize_zone/1, @world_map_file),
         {:ok, towns} <- normalize_all(Map.get(raw_map, "towns", []), &normalize_town/1, @world_map_file) do
      {:ok, %WorldMap{continents: continents, zones: zones, towns: towns}}
    else
      {:ok, _other} -> {:error, %WritAtlasLoadError{file: @world_map_file, reason: :missing_continents_or_zones}}
      {:error, _} = error -> error
    end
  end

  defp read_json(relative_path) do
    path = Path.join(data_dir(), relative_path)

    with {:read, {:ok, body}} <- {:read, File.read(path)},
         {:decode, {:ok, data}} <- {:decode, Jason.decode(body)} do
      {:ok, data}
    else
      {:read, {:error, reason}} -> {:error, %WritAtlasLoadError{file: relative_path, reason: reason}}
      {:decode, {:error, error}} -> {:error, %WritAtlasLoadError{file: relative_path, reason: {:invalid_json, error}}}
    end
  end

  defp data_dir do
    Application.get_env(:recipe_finder, :writ_atlas_dir) || Application.app_dir(:recipe_finder, "priv")
  end

  # Normalizes every entry or fails on the first one with an unexpected
  # shape, naming the file and the offending entry's position.
  defp normalize_all(entries, normalize, file) do
    entries
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {raw, index}, {:ok, acc} ->
      case normalize.(raw) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        :error -> {:halt, {:error, %WritAtlasLoadError{file: file, reason: {:unexpected_shape, index}}}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp normalize_writ(%{
         "name" => @writ_prefix <> short_name,
         "writ_item" => %{"wowhead_id" => wowhead_id},
         "quest_id" => quest_id,
         "tier" => tier,
         "professions" => professions,
         "required_items" => required_items,
         "hand_in" => hand_in,
         "rewards" => rewards
       })
       when is_map_key(@tiers, tier) and is_list(professions) and is_list(required_items) do
    {:ok,
     %Writ{
       name: short_name,
       wowhead_id: wowhead_id,
       quest_id: quest_id,
       tier: Map.fetch!(@tiers, tier),
       professions: professions,
       required_items: Enum.map(required_items, &normalize_required_item/1),
       hand_in: normalize_hand_in(hand_in),
       rewards: normalize_rewards(rewards)
     }}
  end

  defp normalize_writ(_other), do: :error

  defp normalize_required_item(%{"wowhead_id" => id, "display_name" => name, "quantity" => quantity} = item) do
    skill =
      item
      |> Map.get("recipes", [])
      |> Enum.map(& &1["skill"])
      |> Enum.reject(&is_nil/1)
      |> Enum.min(fn -> nil end)

    %{wowhead_id: id, display_name: name, quantity: quantity, skill: skill}
  end

  defp normalize_hand_in(hand_in) do
    {way_x, way_y} = way_point(hand_in["coordinates"])

    %WritHandIn{
      npc_id: hand_in["npc_id"],
      npc_name: hand_in["npc_name"],
      zone: hand_in["zone"],
      zone_id: hand_in["zone_id"],
      way_x: way_x,
      way_y: way_y,
      friendly_to: friendly_factions(hand_in["reaction"])
    }
  end

  defp way_point(%{"x" => x, "y" => y}) when is_number(x) and is_number(y), do: {x * 1.0, y * 1.0}
  defp way_point(_unknown), do: {nil, nil}

  # Wowhead's reaction codes: 1 friendly, 0 neutral, -1 hostile.
  defp friendly_factions(%{"alliance" => alliance, "horde" => horde}) do
    [{:alliance, alliance}, {:horde, horde}]
    |> Enum.filter(fn {_faction, reaction} -> reaction == 1 end)
    |> Enum.map(fn {faction, _reaction} -> faction end)
  end

  defp friendly_factions(_unknown), do: []

  # Each writ pays the same amount to the Alliance and the Horde trade
  # faction (Azeroth Commerce Authority / Durotar Supply and Logistics);
  # a player earns one of them, so the amount shown is one faction's.
  defp normalize_rewards(rewards) do
    %{
      reputation: rewards |> Map.get("reputation", []) |> Enum.map(& &1["amount"]) |> Enum.max(fn -> 0 end),
      money_copper: Map.get(rewards, "money_copper") || 0,
      item_names: rewards |> Map.get("items", []) |> Enum.map(& &1["display_name"]) |> Enum.reject(&is_nil/1)
    }
  end

  defp normalize_continent(%{"key" => key, "rect" => rect, "land" => land}) when is_list(land) do
    {:ok, %{key: key, rect: to_rect(rect), land: Enum.map(land, &to_polygon/1)}}
  end

  defp normalize_continent(_other), do: :error

  defp normalize_zone(%{"area" => area, "continent" => continent, "polygons" => polygons} = zone)
       when is_list(polygons) do
    {:ok,
     %{
       area: area,
       name: zone["name"],
       kind: zone["kind"],
       continent: continent,
       label: to_point(zone["label"]),
       rect: to_rect(zone["rect"]),
       polygons: Enum.map(polygons, &to_polygon/1)
     }}
  end

  defp normalize_zone(_other), do: :error

  defp normalize_town(%{"name" => name, "kind" => kind, "x" => x, "y" => y}) when is_number(x) and is_number(y) do
    {:ok, %{name: name, kind: kind, point: {x, y}}}
  end

  defp normalize_town(_other), do: :error

  defp to_polygon(rings), do: Enum.map(rings, fn ring -> Enum.map(ring, &to_point/1) end)

  defp to_point([x, y]), do: {x, y}
  defp to_point(nil), do: nil

  defp to_rect([a, b]), do: {to_point(a), to_point(b)}
  defp to_rect(nil), do: nil
end
