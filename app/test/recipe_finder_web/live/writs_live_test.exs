defmodule WowForeverRecipeFinderWeb.WritsLiveTest do
  @moduledoc """
  docs/PRD.md § 7.8 end to end: mount /writs against the real committed
  writ + map data, drive the filters and pin selection, assert on the
  rendered HTML.
  """
  use WowForeverRecipeFinderWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @ugbert_pin "#wm-pin-npc-270919"

  test "renders the map, every placed writ and the unknown-hand-in list", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/writs")

    assert html =~ "122 writs on the map"
    assert html =~ "Hand-in not known yet · 28"
    assert has_element?(view, "#wm-map path.wm-zone")
    assert has_element?(view, @ugbert_pin)
    assert has_element?(view, "#wm-unknown", "Dark Iron Bomb")
  end

  test "links back to the recipes page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/writs")

    assert has_element?(view, ~s(nav.rf-nav a[href="/"]), "Recipes")
  end

  test "profession filter narrows pins, the list and the unknown section", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/writs")

    html = view |> element(~s(#wm-profession-chips button[phx-value-profession="tailoring"])) |> render_click()

    assert html =~ "24 writs on the map"
    refute has_element?(view, @ugbert_pin)
    assert has_element?(view, ~s(#wm-profession-chips button.on[phx-value-profession="tailoring"]))
  end

  test "tier filter", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/writs")

    html = view |> element(~s(#wm-tier-chips button[phx-value-tier="artisan"])) |> render_click()

    assert html =~ "18 writs on the map"
  end

  test "faction filter hides NPCs not friendly to that faction", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/writs")

    view |> element(~s(#wm-side-chips button[phx-value-side="alliance"])) |> render_click()
    refute has_element?(view, @ugbert_pin)

    view |> element(~s(#wm-side-chips button[phx-value-side="horde"])) |> render_click()
    assert has_element?(view, @ugbert_pin)
  end

  test "search filters by NPC name", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/writs")

    html = view |> element("#wm-search-form") |> render_change(%{"search" => "ugbert"})

    assert html =~ "1 writ on the map"
    assert has_element?(view, "#wm-panel", "Steel Weapon Chain")
  end

  test "selecting a pin shows that NPC's writs and a copyable waypoint; back returns to the list", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/writs")

    view |> element(@ugbert_pin) |> render_click()

    assert has_element?(view, "#wm-panel h2", "Ugbert")
    assert has_element?(view, "#wm-copy-way[data-copy='/way Dustwallow Marsh 40.8 28']")
    assert has_element?(view, "#wm-panel", "+125 rep")

    view |> element("#wm-panel button.wm-back") |> render_click()
    assert render(view) =~ "122 writs on the map"
  end

  test "clicking a writ row selects its hand-in NPC", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/writs")

    view |> element(~s(#wm-panel .wm-writ[phx-value-pin="npc-270919"])) |> render_click()

    assert has_element?(view, "#wm-panel h2", "Ugbert")
    assert_push_event(view, "focus_pin", %{x: _, y: _})
  end

  test "continent buttons send the continent's view box to the map", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/writs")

    view |> element(~s(.wm-map-tools button[phx-value-view="kalimdor"])) |> render_click()

    assert_push_event(view, "show_view", %{view_box: [_, _, _, _]})
    assert has_element?(view, ~s(.wm-map-tools button.on[phx-value-view="kalimdor"]))
  end

  test "shows an error state when the data can't be loaded", %{conn: conn} do
    missing_dir = Path.expand("../../fixtures/writ_atlas/does_not_exist", __DIR__)
    Application.put_env(:recipe_finder, :writ_atlas_dir, missing_dir)
    on_exit(fn -> Application.delete_env(:recipe_finder, :writ_atlas_dir) end)

    {:ok, view, _html} = live(conn, ~p"/writs")

    assert has_element?(view, "#writs-load-error", "world_map/world_map_vectors.json")
    refute has_element?(view, "#wm-map")
  end
end
