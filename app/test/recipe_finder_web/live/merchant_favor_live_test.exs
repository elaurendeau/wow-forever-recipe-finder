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
  @multi_realm_fixture Path.join([
                         __DIR__,
                         "..",
                         "..",
                         "fixtures",
                         "tsm_export",
                         "multi_realm.lua"
                       ])

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

    # Crate cost 200c + cheapest fill (Elixir of Ogre Strength, 300c) = 500c = 5s 0c.
    assert html =~ "Waylaid Crate: Apprentice Curiosities"
    assert html =~ "5s 0c"

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

  test "defaults to sorting by Price/Favor ascending, cheapest-per-token first", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/merchant-favor")
    html = upload_tsm_export(view)

    # Both known-cost crates in this fixture are Apprentice/Common (the
    # same Favor amount, 5, for each), so Price/Favor and Total cost
    # happen to agree here — Curiosities (5s 0c, cheaper) sorts before
    # Herbs (7s 97c). The dedicated unit test in
    # crate_results_filter_test.exs covers a case where the two
    # columns actually disagree.
    assert html =~ ~r/Apprentice Curiosities.*Apprentice Herbs/s
  end

  test "clicking the Total cost header sorts by that column specifically", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/merchant-favor")
    upload_tsm_export(view)

    asc_html = view |> element("th", "Total cost") |> render_click()
    assert asc_html =~ ~r/Apprentice Curiosities.*Apprentice Herbs/s

    desc_html = view |> element("th", "Total cost") |> render_click()
    assert desc_html =~ ~r/Apprentice Herbs.*Apprentice Curiosities/s
  end

  test "clicking the Price/Favor header sorts by that column specifically", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/merchant-favor")
    upload_tsm_export(view)

    desc_html = view |> element("th", "Price/Favor") |> render_click()
    assert desc_html =~ ~r/Apprentice Herbs.*Apprentice Curiosities/s
  end

  describe "realm selector (the user's own real question: there's no way to tell which realm's prices are shown)" do
    test "no realm dropdown is shown until a snapshot is uploaded", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/merchant-favor")

      refute html =~ "rf-realm-select"
    end

    test "uploading a multi-realm export shows a dropdown defaulting to the most recently scanned realm",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/merchant-favor")

      export = File.read!(@multi_realm_fixture)

      file =
        file_input(view, "#upload-form", :tsm_export, [
          %{name: "AppData.lua", content: export, type: "text/x-lua"}
        ])

      render_upload(file, "AppData.lua")
      html = view |> form("#upload-form", %{}) |> render_submit()

      assert html =~ "rf-realm-select"
      assert html =~ "PvP-Horde"
      assert html =~ "Stale-OldRealm"
      # Fireblood (item 4625) is priced at 1544c on the PvP-Horde realm
      # (the more recently scanned one, selected by default) — x10 for
      # the Earthly Expert Herbs crate's fill option = 15440c = 1g 54s 40c.
      assert html =~ "1g 54s 40c"
    end

    test "switching realms recomputes Fill cost from that realm's own Recent Value only, never blending realms",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/merchant-favor")

      export = File.read!(@multi_realm_fixture)

      file =
        file_input(view, "#upload-form", :tsm_export, [
          %{name: "AppData.lua", content: export, type: "text/x-lua"}
        ])

      render_upload(file, "AppData.lua")
      view |> form("#upload-form", %{}) |> render_submit()

      html = view |> form("#realm-form", %{"realm" => "Stale-OldRealm"}) |> render_change()

      # Fireblood is 109c on Stale-OldRealm — x10 = 1090c = 10s 90c.
      # The PvP-Horde figure (1g 54s 40c) must be gone, not just added
      # alongside it: a visitor should never see a blend of two realms.
      assert html =~ "10s 90c"
      refute html =~ "1g 54s 40c"
    end
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
      # 200c * 3 = 600c = 6s 0c.
      assert html =~ "6s 0c"
      # Elixir of Ogre Strength at 300c/unit * 3 = 900c = 9s 0c.
      assert html =~ "Elixir of Ogre Strength x3"
      assert html =~ "9s 0c"
      # Apprentice/Common pays 5 Favor (MerchantFavorFormula) * 3 crates = 15.
      assert html =~ "15"
      assert html =~ "total Merchant&#39;s Favor"
      assert html =~ "Copy for Auctionator"
    end

    test "the popup totals Merchant's Favor across every selected crate, not just one", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/merchant-favor")
      upload_tsm_export(view)

      curiosities_id = crate_id!("Waylaid Crate: Apprentice Curiosities")
      herbs_id = crate_id!("Waylaid Crate: Apprentice Herbs")

      set_quantity(view, curiosities_id, "2")
      set_quantity(view, herbs_id, "3")
      html = open_shopping_list(view)

      # Both are Apprentice/Common (5 Favor each): 2*5 + 3*5 = 25.
      assert html =~ "25"
      assert html =~ "total Merchant&#39;s Favor"
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
