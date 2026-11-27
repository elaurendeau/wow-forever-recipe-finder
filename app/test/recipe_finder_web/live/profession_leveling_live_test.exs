defmodule WowForeverRecipeFinderWeb.ProfessionLevelingLiveTest do
  @moduledoc """
  Outside-in integration test per docs/ELIXIR_TEST_MANIFESTO.md: mounts
  the real LiveView, uploads a real TSM export fixture, and asserts on
  rendered HTML. Covers the page's own real behavior — a collapsed
  segment, a visible gap, a non-trainer recipe cost, and the shared
  price-basis toggle recomputing the path — not profit math itself,
  which `profession_leveling_test.exs` already covers as pure
  unit tests.
  """
  use WowForeverRecipeFinderWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias WowForeverRecipeFinder.CatalogSeeder

  @catalog_fixture Path.join([__DIR__, "..", "..", "fixtures", "catalog", "sample_leveling.json"])
  @tsm_fixture Path.join([__DIR__, "..", "..", "fixtures", "tsm_export", "leveling_path.lua"])

  setup do
    :ok = CatalogSeeder.load_from_file!(@catalog_fixture)
    :ok
  end

  defp upload_tsm_export(view) do
    export = File.read!(@tsm_fixture)

    file =
      file_input(view, "form[phx-submit=process_upload]", :tsm_export, [
        %{name: "AppData.lua", content: export, type: "text/x-lua"}
      ])

    render_upload(file, "AppData.lua")
    view |> form("form[phx-submit=process_upload]", %{}) |> render_submit()
  end

  test "renders the no-data empty state before any upload", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/profession-leveling")

    assert html =~ "Upload a TSM export to see the leveling path"
  end

  test "builds a real path: a collapsed segment, a gap, and a non-trainer recipe's one-time cost",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/profession-leveling")
    html = upload_tsm_export(view)

    # Early Robe (trainer, learned 1, grey 10) covers skill 1-9 as one
    # collapsed segment, not nine separate rows.
    assert html =~ "1–9"
    assert html =~ "Early Robe"

    # No recipe covers skill 10-14 (Early Robe already grey, Later Robe
    # not learnable yet) — a real gap, shown, never hidden.
    assert html =~ "10–14"
    assert html =~ "No recipe both still gives a skill-up here"

    # Later Robe (vendor, learned 15, grey 25) covers 15-24, and shows
    # its own one-time recipe cost (item 9304, Recent Value 1900c =
    # 19s 0c) — separate from its per-craft reagent cost.
    assert html =~ "15–24"
    assert html =~ "Later Robe"
    assert html =~ "19s 0c"

    # Early Robe never shows a recipe cost — it's trainer-taught, so its
    # row's own Recipe cost cell is the nil-safe em dash, not a figure.
    assert html =~ ~r{Early Robe.*?rf-muted">—</td>}s
  end

  test "switching price basis recomputes the path's profit figures", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/profession-leveling")
    upload_tsm_export(view)

    html = view |> element("button.rf-side-chip", "Region Sale Avg") |> render_click()

    assert html =~ ~r/rf-side-chip on[^>]*>\s*Region Sale Avg/
    # Region Sale Avg recipe cost for item 9304 is 2000c = 20s 0c,
    # different from the Recent-Value figure (19s 0c) above — proving
    # the switch actually recomputed rather than just relabeling.
    assert html =~ "20s 0c"
  end

  test "switching the profession tab recomputes the path for that profession", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/profession-leveling")
    upload_tsm_export(view)

    html = view |> element("button[phx-value-slug=enchanting]") |> render_click()

    refute html =~ "Early Robe"
  end
end
