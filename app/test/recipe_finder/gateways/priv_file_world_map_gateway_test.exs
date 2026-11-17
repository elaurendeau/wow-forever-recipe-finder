defmodule WowForeverRecipeFinder.Gateways.PrivFileWorldMapGatewayTest do
  @moduledoc """
  Against real fixture files (test/fixtures/world_map_gateway/), per
  docs/ELIXIR_TEST_MANIFESTO.md — no mocks at this boundary.
  """
  use ExUnit.Case, async: false

  alias WowForeverRecipeFinder.Gateways.PrivFileWorldMapGateway
  alias WowForeverRecipeFinder.{WorldMap, WorldMapLoadError}

  @fixtures_root Path.join([__DIR__, "..", "..", "fixtures", "world_map_gateway"])

  setup do
    previous = Application.get_env(:recipe_finder, :world_map_dir)
    on_exit(fn -> Application.put_env(:recipe_finder, :world_map_dir, previous) end)
  end

  test "loads continents, zones, and towns from the real fixture file" do
    Application.put_env(:recipe_finder, :world_map_dir, Path.join(@fixtures_root, "sample"))

    assert {:ok, %WorldMap{} = world_map} = PrivFileWorldMapGateway.load()

    assert Enum.map(world_map.continents, & &1.key) |> Enum.sort() ==
             ["eastern-kingdoms", "kalimdor"]

    durotar = Enum.find(world_map.zones, &(&1.name == "Durotar"))
    assert durotar.area == 14
    assert durotar.continent == "kalimdor"
    assert durotar.rect == {{18_268, 14_648}, {23_344, 18_032}}

    assert [[[{18_268, 14_648}, {23_344, 14_648}, {23_344, 18_032}, {18_268, 18_032}]]] =
             durotar.polygons

    assert [%{name: "Orgrimmar", point: {20_590.6, 14_650.1}}] = world_map.towns
  end

  test "a zone with no name/rect still loads, never dropped" do
    Application.put_env(:recipe_finder, :world_map_dir, Path.join(@fixtures_root, "sample"))

    {:ok, world_map} = PrivFileWorldMapGateway.load()

    unnamed = Enum.find(world_map.zones, &(&1.area == 999_999))
    assert unnamed.name == nil
    assert unnamed.rect == nil
    assert unnamed.polygons != []
  end

  test "a missing file is a named WorldMapLoadError, never a crash" do
    Application.put_env(
      :recipe_finder,
      :world_map_dir,
      Path.join(@fixtures_root, "does_not_exist")
    )

    assert {:error, %WorldMapLoadError{file: "world_map/world_map_vectors.json", reason: :enoent}} =
             PrivFileWorldMapGateway.load()
  end

  test "malformed JSON is a named WorldMapLoadError, never a crash" do
    Application.put_env(
      :recipe_finder,
      :world_map_dir,
      Path.join(@fixtures_root, "malformed_json")
    )

    assert {:error, %WorldMapLoadError{reason: {:invalid_json, _}}} =
             PrivFileWorldMapGateway.load()
  end

  test "a file missing the zones key is a named WorldMapLoadError, never a silently empty map" do
    Application.put_env(
      :recipe_finder,
      :world_map_dir,
      Path.join(@fixtures_root, "missing_zones")
    )

    assert {:error, %WorldMapLoadError{reason: :missing_continents_or_zones}} =
             PrivFileWorldMapGateway.load()
  end
end
