defmodule WowForeverRecipeFinder.Gateways.PrivFileWorldMapGateway do
  @moduledoc """
  `WorldMapGateway` backed by the committed `priv/world_map/world_map_vectors.json`
  (see docs/DATA_SOURCES.md § Wowhead WoW Forever World Map). Validates
  its shape at the boundary: a missing or malformed file is a
  `WorldMapLoadError` naming the file, never a crash or a silently
  empty map.

  The data directory defaults to this app's `priv/` and can be pointed
  elsewhere with `config :recipe_finder, :world_map_dir, path` (tests
  use that to exercise the error paths with real broken fixtures, per
  docs/ELIXIR_TEST_MANIFESTO.md).
  """

  @behaviour WowForeverRecipeFinder.Gateways.WorldMapGateway

  alias WowForeverRecipeFinder.{WorldMap, WorldMapLoadError}

  @vectors_file "world_map/world_map_vectors.json"

  @impl true
  def load do
    case read_json() do
      {:ok, %{"continents" => continents, "zones" => zones} = raw}
      when is_list(continents) and is_list(zones) ->
        {:ok,
         %WorldMap{
           continents: Enum.map(continents, &normalize_continent/1),
           zones: Enum.map(zones, &normalize_zone/1),
           towns: raw |> Map.get("towns", []) |> Enum.map(&normalize_town/1)
         }}

      {:ok, _other} ->
        {:error, %WorldMapLoadError{file: @vectors_file, reason: :missing_continents_or_zones}}

      {:error, _} = error ->
        error
    end
  end

  defp read_json do
    path = Path.join(data_dir(), @vectors_file)

    with {:read, {:ok, body}} <- {:read, File.read(path)},
         {:decode, {:ok, data}} <- {:decode, Jason.decode(body)} do
      {:ok, data}
    else
      {:read, {:error, reason}} ->
        {:error, %WorldMapLoadError{file: @vectors_file, reason: reason}}

      {:decode, {:error, error}} ->
        {:error, %WorldMapLoadError{file: @vectors_file, reason: {:invalid_json, error}}}
    end
  end

  defp data_dir do
    Application.get_env(:recipe_finder, :world_map_dir) ||
      Application.app_dir(:recipe_finder, "priv")
  end

  defp normalize_continent(%{"key" => key, "rect" => rect, "land" => land}) do
    %{key: key, rect: to_rect(rect), land: Enum.map(land, &to_polygon/1)}
  end

  defp normalize_zone(%{"area" => area, "continent" => continent, "polygons" => polygons} = zone) do
    %{
      area: area,
      name: zone["name"],
      continent: continent,
      label: to_point(zone["label"]),
      rect: to_rect(zone["rect"]),
      polygons: Enum.map(polygons, &to_polygon/1)
    }
  end

  defp normalize_town(%{"name" => name, "x" => x, "y" => y}), do: %{name: name, point: {x, y}}

  defp to_polygon(rings), do: Enum.map(rings, fn ring -> Enum.map(ring, &to_point/1) end)

  defp to_point([x, y]), do: {x, y}
  defp to_point(nil), do: nil

  defp to_rect([a, b]), do: {to_point(a), to_point(b)}
  defp to_rect(nil), do: nil
end
