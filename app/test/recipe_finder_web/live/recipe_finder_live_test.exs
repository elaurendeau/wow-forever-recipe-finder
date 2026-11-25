defmodule WowForeverRecipeFinderWeb.RecipeFinderLiveTest do
  @moduledoc """
  Outside-in integration test per docs/ELIXIR_TEST_MANIFESTO.md: mounts
  the real LiveView, uploads a real TSM export fixture, and asserts on
  rendered HTML. Focused on the price/cost basis toggle (docs/PRD.md §
  7.3, revised 2026-11-25) — the rest of this page's filter/sort
  behavior isn't otherwise covered by a LiveView test yet, so this file
  stays scoped to the toggle rather than attempting full coverage. The
  missing-data edge cases (a reagent with no price under a given basis)
  are unit-tested directly in profit_computation_test.exs instead of
  here, to avoid fighting the page's own "profitable only" default
  filter in an integration test.
  """
  use WowForeverRecipeFinderWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias WowForeverRecipeFinder.CatalogSeeder

  @catalog_fixture Path.join([
                     __DIR__,
                     "..",
                     "..",
                     "fixtures",
                     "catalog",
                     "sample_tailoring.json"
                   ])
  @tsm_fixture Path.join([__DIR__, "..", "..", "fixtures", "tsm_export", "basis_toggle.lua"])

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

  test "defaults to DB Recent, and the Price/Cost columns come from Recent Value", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    html = upload_tsm_export(view)

    assert html =~ ~r/rf-side-chip on[^>]*>\s*DB Recent/
    assert html =~ "Test Robe"

    # Crafted item (9001) Recent Value 400c; reagent (9002) Recent
    # Value 30c x2 = 60c cost.
    assert html =~ "4s 0c"
    assert html =~ "60c"
  end

  test "switching to Region Sale Avg recomputes both Price and Cost from that basis instead",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    upload_tsm_export(view)

    html = view |> element("button.rf-side-chip", "Region Sale Avg") |> render_click()

    assert html =~ ~r/rf-side-chip on[^>]*>\s*Region Sale Avg/

    # Region Sale Avg: crafted item 300c (Price), reagent 50c x2 = 100c (Cost) —
    # different figures than the Recent-Value basis above, proving the
    # switch actually recomputed rather than just relabeling.
    assert html =~ "3s 0c"
    assert html =~ "1s 0c"
    refute html =~ "4s 0c"
  end

  test "switching basis back to DB Recent is a real toggle, not one-way", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    upload_tsm_export(view)

    view |> element("button.rf-side-chip", "Region Sale Avg") |> render_click()
    html = view |> element("button.rf-side-chip", "DB Recent") |> render_click()

    assert html =~ ~r/rf-side-chip on[^>]*>\s*DB Recent/
    refute html =~ ~r/rf-side-chip on[^>]*>\s*Region Sale Avg/
    assert html =~ "4s 0c"
  end
end
