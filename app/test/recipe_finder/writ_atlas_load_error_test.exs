defmodule WowForeverRecipeFinder.WritAtlasLoadErrorTest do
  @moduledoc """
  docs/PRD.md § 7.8's error state: a missing or malformed data file is a
  `WritAtlasLoadError` naming the file — never a crash or an empty map.
  Points the gateway at broken fixtures under test/fixtures/writ_atlas, so
  not async (it changes application env).
  """
  use ExUnit.Case, async: false

  alias WowForeverRecipeFinder.{WritAtlas, WritAtlasLoadError}

  @fixtures Path.expand("../fixtures/writ_atlas", __DIR__)

  setup do
    on_exit(fn -> Application.delete_env(:recipe_finder, :writ_atlas_dir) end)
  end

  defp use_data_dir(dir), do: Application.put_env(:recipe_finder, :writ_atlas_dir, dir)

  test "a missing data file names the file" do
    use_data_dir(Path.join(@fixtures, "does_not_exist"))

    assert {:error, %WritAtlasLoadError{file: "world_map/world_map_vectors.json", reason: :enoent}} =
             WritAtlas.load_atlas()
  end

  test "malformed JSON names the file" do
    use_data_dir(Path.join(@fixtures, "malformed_json"))

    assert {:error, %WritAtlasLoadError{file: "world_map/world_map_vectors.json", reason: {:invalid_json, _}}} =
             WritAtlas.load_atlas()
  end

  test "a writ entry without the expected fields names the file and the entry" do
    use_data_dir(Path.join(@fixtures, "unexpected_shape"))

    assert {:error, %WritAtlasLoadError{file: "writs/craftsmans_writs.json", reason: {:unexpected_shape, 0}}} =
             WritAtlas.load_atlas()
  end
end
