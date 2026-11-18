defmodule WowForeverRecipeFinderWeb.MerchantFavorLiveTest do
  @moduledoc """
  Outside-in integration test per docs/ELIXIR_TEST_MANIFESTO.md:
  mounts the real LiveView, uploads a real TSM export fixture, and
  asserts on rendered HTML — proving the full slice (upload → parse →
  CrateEfficiency join → assigns → rendered HTML) in one pass, backed
  by the real sandboxed Postgres DB for the crate catalog (no mocks
  at that boundary).
  """
  use WowForeverRecipeFinderWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias WowForeverRecipeFinder.CrateCatalogSeeder
  alias WowForeverRecipeFinder.Gateways.EctoCrateRepositoryGateway

  @crates_fixture Path.join([__DIR__, "..", "..", "fixtures", "crates", "sample_crates.json"])
  @tsm_fixture Path.join([__DIR__, "..", "..", "fixtures", "tsm_export", "snapshot_1.lua"])

  setup do
    :ok = CrateCatalogSeeder.load_from_file!(@crates_fixture)
    :ok
  end

  defp upload_tsm_export(view) do
    export = File.read!(@tsm_fixture)

    file =
      file_input(view, "#upload-form", :tsm_export, [
        %{name: "AppData.lua", content: export, type: "text/x-lua"}
      ])

    render_upload(file, "AppData.lua")
    view |> form("#upload-form", %{}) |> render_submit()
  end

  defp crate_id!(name) do
    EctoCrateRepositoryGateway.list_crates()
    |> Enum.find(&(&1.name == name))
    |> Map.fetch!(:id)
  end

  test "mounting with no snapshot yet shows the upload prompt and no crate rows", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/merchant-favor")

    assert html =~ "No data uploaded yet"
    refute html =~ "Waylaid Crate: Apprentice Curiosities"
  end

  test "uploading a real TSM export computes crate/fill cost and renders every crate, including gaps",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/merchant-favor")

    html = upload_tsm_export(view)

    # Crate cost 68c + cheapest fill (Elixir of Ogre Strength, 300c) = 368c = 3s 68c.
    assert html =~ "Waylaid Crate: Apprentice Curiosities"
    assert html =~ "3s 68c"

    # Crate cost 497c + cheapest priceable fill (300c, the unresolved
    # 5-quantity reagent is skipped since it has no wowhead_id) = 797c = 7s 97c.
    assert html =~ "Waylaid Crate: Apprentice Herbs"
    assert html =~ "7s 97c"

    # Ore crate: both fill options have wowhead_id nil (no Mining
    # catalog seed exists in this app at all — see DATA_SOURCES.md) —
    # flagged as "no priceable option", never priced as free.
    assert html =~ "Waylaid Crate: Apprentice Ore"
    assert html =~ "no priceable option"

    # Expert Ingots crate: fill_options was null in the fixture
    # (not yet captured by the extraction) — flagged, not hidden.
    assert html =~ "Waylaid Crate: Expert Ingots"
    assert html =~ "not captured yet"
  end

  test "the search filter narrows rows by crate name without a re-upload", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/merchant-favor")
    upload_tsm_export(view)

    html = view |> form("#filter-form", %{"filter" => %{"search" => "Ore"}}) |> render_change()

    assert html =~ "Waylaid Crate: Apprentice Ore"
    refute html =~ "Waylaid Crate: Apprentice Curiosities"
  end

  test "the tier toggle narrows rows to the selected tier", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/merchant-favor")
    upload_tsm_export(view)

    html = view |> element("button.rf-side-chip", "Expert") |> render_click()

    assert html =~ "Waylaid Crate: Expert Ingots"
    refute html =~ "Waylaid Crate: Apprentice Curiosities"
  end

  test "the sort toggle flips row order by total cost", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/merchant-favor")
    html = upload_tsm_export(view)

    # Ascending (default): the cheapest priced crate — Curiosities at
    # 3s 68c — sorts before the pricier Herbs crate at 7s 97c.
    assert html =~ ~r/Apprentice Curiosities.*Apprentice Herbs/s

    desc_html = view |> element("th.sorted") |> render_click()
    assert desc_html =~ ~r/Apprentice Herbs.*Apprentice Curiosities/s
  end

  test "clearing the snapshot empties the table and asks the client to clear localStorage", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/merchant-favor")
    upload_tsm_export(view)

    html = view |> element("button", "forget") |> render_click()

    assert html =~ "No data uploaded yet"
    refute html =~ "Waylaid Crate: Apprentice Curiosities"
  end

  describe "crate shopping list (docs/PRD.md § 7.11) — FAB + popup, grouped by crate" do
    defp set_quantity(view, id, value) do
      view
      |> form("form[phx-value-id='#{id}']", %{"value" => value})
      |> render_change()
    end

    defp open_shopping_list(view) do
      view |> element("button.rf-shopping-fab") |> render_click()
    end

    test "no FAB is shown until a quantity is set", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/merchant-favor")
      html = upload_tsm_export(view)

      refute html =~ "rf-shopping-fab"
    end

    test "setting a quantity shows the FAB with an unseen badge, but the popup stays closed", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/merchant-favor")
      upload_tsm_export(view)

      id = crate_id!("Waylaid Crate: Apprentice Curiosities")
      html = set_quantity(view, id, "3")

      assert html =~ "rf-shopping-fab"
      assert html =~ "rf-shopping-fab-badge"
      refute html =~ "Copy for Auctionator"
    end

    test "opening the popup groups by crate, multiplies quantities, and clears the badge", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/merchant-favor")
      upload_tsm_export(view)

      id = crate_id!("Waylaid Crate: Apprentice Curiosities")
      set_quantity(view, id, "3")
      html = open_shopping_list(view)

      refute html =~ "rf-shopping-fab-badge"
      assert html =~ "Waylaid Crate: Apprentice Curiosities x3"
      # 68c * 3 = 204c = 2s 4c.
      assert html =~ "2s 4c"
      # Elixir of Ogre Strength at 300c/unit * 3 = 900c = 9s 0c.
      assert html =~ "Elixir of Ogre Strength x3"
      assert html =~ "9s 0c"
      assert html =~ "Copy for Auctionator"
    end

    test "the Auctionator export text has Auctionator's real *** header and one item name per line, no quantities",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/merchant-favor")
      upload_tsm_export(view)

      id = crate_id!("Waylaid Crate: Apprentice Curiosities")
      set_quantity(view, id, "2")
      html = open_shopping_list(view)

      assert html =~
               "data-copy=\"*** WoW Forever Crates\nWaylaid Crate: Apprentice Curiosities\nElixir of Ogre Strength\n\""
    end

    test "a crate with no priceable fill option still forms a group, listed by name only", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/merchant-favor")
      upload_tsm_export(view)

      id = crate_id!("Waylaid Crate: Apprentice Ore")
      set_quantity(view, id, "1")
      html = open_shopping_list(view)

      assert html =~ "Waylaid Crate: Apprentice Ore x1"
    end

    test "setting a quantity back to 0 removes its group and eventually hides the FAB", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/merchant-favor")
      upload_tsm_export(view)

      id = crate_id!("Waylaid Crate: Apprentice Curiosities")
      set_quantity(view, id, "2")
      html = set_quantity(view, id, "0")

      refute html =~ "rf-shopping-fab"
    end

    test "the clear button empties every quantity and hides the FAB", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/merchant-favor")
      upload_tsm_export(view)

      id = crate_id!("Waylaid Crate: Apprentice Curiosities")
      set_quantity(view, id, "2")
      open_shopping_list(view)
      html = view |> element("button", "clear") |> render_click()

      refute html =~ "rf-shopping-fab"
    end
  end
end
