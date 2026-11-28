defmodule WowForeverRecipeFinderWeb.ProfessionLevelingLiveTest do
  @moduledoc """
  Outside-in integration test per docs/ELIXIR_TEST_MANIFESTO.md: mounts
  the real LiveView, uploads a real TSM export fixture, and asserts on
  rendered HTML. Covers the page's own real behavior — a collapsed
  segment stopping at green (not grey), a visible gap, the estimated
  total cost/sell figures, the shopping-list popup, and the shared
  price-basis toggle recomputing all of it — not the underlying
  probability/cost math itself, which `profession_leveling_test.exs`
  already covers as pure unit tests.
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

  test "builds a real path: a collapsed segment stopping at green, and a visible gap",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/profession-leveling")
    html = upload_tsm_export(view)

    # Early Robe (trainer, learned 1, colors [1,5,8,10]) covers skill
    # 1-7 as one collapsed segment, not seven separate rows — stops at
    # green (8), not grey (10), per the visitor's own "stop once it's
    # green" choice.
    assert html =~ "1–7"
    assert html =~ "Early Robe"

    # Skill 14 alone is a real gap: Loss Filler (see below) already
    # green by then, Later Robe not learnable yet.
    assert html =~ "14"
    assert html =~ "No recipe is both still in range here and has a known price and reagent cost"

    # Later Robe (vendor, learned 15, colors [15,18,20,25]) covers
    # 15-19, stopping at its own green (20), not grey (25).
    assert html =~ "15–19"
    assert html =~ "Later Robe"

    # Early Robe (trainer, 8 estimated crafts for 1-7) needs no AH
    # purchase: its Total cost is just the reagent total (10c x 8 =
    # 80c), not inflated by a recipe cost it doesn't have.
    assert html =~ ~r{Early Robe.*?~8.*?80c}s

    # Later Robe (vendor, 6 estimated crafts for 15-19) adds its own
    # one-time AH purchase (item 9304, Recent Value 1900c) on top of
    # its reagent total (10c x 6 = 60c) = 1960c = 19s 60c.
    assert html =~ ~r{Later Robe.*?~6.*?19s 60c}s
  end

  test "recommends the least-bad losing recipe, clearly marked, instead of a gap",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/profession-leveling")
    html = upload_tsm_export(view)

    # Loss Filler (trainer, learned 8, colors [8,10,14,15]) is the only
    # recipe in range for skill 8-13 — Early Robe is already green,
    # Later Robe isn't learnable yet — and it loses 5c per craft (price
    # 5c recent, reagent cost 10c). It's recommended anyway, not shown
    # as a gap, since it's still the least-bad real option.
    assert html =~ "8–13"
    assert html =~ "Loss Filler"
    assert html =~ ~r{Loss Filler.*?class="rf-source-pill rf-profit-neg"[^>]*>\s*loses money}s

    # Every real recommendation — safe or losing — is marked as an AH
    # sale, since this app has no vendor data at all.
    assert html =~ "sell: AH"

    # The row itself gets a distinct loss styling, not the same
    # treatment as a safe recommendation.
    assert html =~ ~r{<tr class="rf-leveling-loss">.*?Loss Filler}s
  end

  test "switching price basis recomputes the path's total cost", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/profession-leveling")
    html = upload_tsm_export(view)

    assert html =~ "19s 60c"

    html = view |> element("button.rf-side-chip", "Region Sale Avg") |> render_click()

    assert html =~ ~r/rf-side-chip on[^>]*>\s*Region Sale Avg/
    # Region Sale Avg price for item 9304 is 2000c (vs Recent Value's
    # 1900c), so Later Robe's total cost becomes 2000c + 60c = 2060c =
    # 20s 60c — different from the Recent-Value figure above, proving
    # the switch actually recomputed rather than just relabeling.
    assert html =~ "20s 60c"
    refute html =~ "19s 60c"
  end

  test "clicking a segment's Shopping list button opens the real Auctionator copy popup",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/profession-leveling")
    upload_tsm_export(view)

    html =
      view
      |> element("tr", "Later Robe")
      |> render()

    refute html =~ "rf-shopping-popup"

    html =
      view
      |> element("button[phx-value-from='15']", "Shopping list")
      |> render_click()

    assert html =~ "Later Robe Shopping List"
    # The recipe's own one-time purchase item leads the list, quantity
    # 1 regardless of how many crafts are needed — then the reagent,
    # scaled by the estimated 6 crafts.
    assert html =~ "Pattern: Later Robe x1"
    assert html =~ "Test Cloth x6"

    assert html =~ ~r/data-copy="\*\*\* Later Robe\nPattern: Later Robe\nTest Cloth\n"/

    html = view |> element(".rf-shopping-popup-close") |> render_click()
    refute html =~ "rf-shopping-popup"
  end

  test "switching the profession tab recomputes the path for that profession", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/profession-leveling")
    upload_tsm_export(view)

    html = view |> element("button[phx-value-slug=enchanting]") |> render_click()

    refute html =~ "Early Robe"
  end
end
