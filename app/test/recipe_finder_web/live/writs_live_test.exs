defmodule WowForeverRecipeFinderWeb.WritsLiveTest do
  @moduledoc """
  Outside-in integration test per docs/ELIXIR_TEST_MANIFESTO.md:
  mounts the real LiveView, uploads a real TSM export fixture, and
  asserts on rendered HTML — proving the full slice (upload → parse →
  WritEfficiency join → assigns → rendered HTML) in one pass, backed
  by the real sandboxed Postgres DB for the writ catalog (no mocks at
  that boundary).
  """
  use WowForeverRecipeFinderWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias WowForeverRecipeFinder.Gateways.EctoWritRepositoryGateway
  alias WowForeverRecipeFinder.WritCatalogSeeder

  @writs_fixture Path.join([__DIR__, "..", "..", "fixtures", "writs", "sample_writs.json"])
  @tsm_fixture Path.join([__DIR__, "..", "..", "fixtures", "tsm_export", "snapshot_1.lua"])

  setup do
    :ok = WritCatalogSeeder.load_from_file!(@writs_fixture)
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

  test "mounting with no snapshot yet shows the upload prompt and no writ rows", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/writs")

    assert html =~ "No data uploaded yet"
    refute html =~ "Craftsman&#39;s Writ: Elixir of Ogre&#39;s Strength"
  end

  test "uploading a real TSM export computes writ cost/reputation and renders every writ, including pending ones",
       %{
         conn: conn
       } do
    {:ok, view, _html} = live(conn, ~p"/writs")

    html = upload_tsm_export(view)

    # The "complete" writ: both the writ item (5571) and its required
    # item (264031) have a Recent Value in the real fixture export.
    assert html =~ "Craftsman&#39;s Writ: Elixir of Ogre&#39;s Strength"
    # writ item (5571) + required item (264031), both at Recent Value
    # 300 in the real fixture export: 300 + 300 = 600 copper = 6s 0c.
    assert html =~ "6s 0c"

    # The pending_quest_page writ is still rendered, never dropped —
    # per docs/PRD.md § 7.8's "flagged, not hidden" rule.
    assert html =~ "Craftsman&#39;s Writ: Heavy Bronze Mace"
    assert html =~ "awaiting data"

    # The writ with wowhead IDs absent from the uploaded snapshot
    # entirely shows no fabricated cost.
    assert html =~ "Craftsman&#39;s Writ: Goblin Rocket Fuel"
  end

  test "the search filter narrows rows by writ name without a re-upload", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/writs")
    upload_tsm_export(view)

    html = view |> form("#filter-form", %{"filter" => %{"search" => "Bronze"}}) |> render_change()

    assert html =~ "Heavy Bronze Mace"
    refute html =~ "Elixir of Ogre&#39;s Strength"
  end

  test "clearing the snapshot empties the table and asks the client to clear localStorage", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/writs")
    upload_tsm_export(view)

    html = view |> element("button", "forget") |> render_click()

    assert html =~ "No data uploaded yet"
    refute html =~ "Elixir of Ogre&#39;s Strength"
  end

  describe "shopping list (docs/PRD.md § 7.9) — FAB + popup, never shifts the table" do
    defp writ_id!(name) do
      EctoWritRepositoryGateway.list_writs()
      |> Enum.find(&(&1.name == name))
      |> Map.fetch!(:id)
    end

    defp open_shopping_list(view) do
      view |> element("button.rf-shopping-fab") |> render_click()
    end

    test "no FAB is shown until a writ is checked", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/writs")
      html = upload_tsm_export(view)

      refute html =~ "rf-shopping-fab"
    end

    test "checking a writ shows the FAB with an unseen badge, but the popup stays closed", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/writs")
      upload_tsm_export(view)

      id = writ_id!("Craftsman's Writ: Elixir of Ogre's Strength")
      html = view |> element("input[phx-value-id='#{id}']") |> render_click()

      assert html =~ "rf-shopping-fab"
      assert html =~ "rf-shopping-fab-badge"
      refute html =~ "Copy for Auctionator"
    end

    test "clicking the FAB opens the popup with the writ item and required item, and clears the badge",
         %{
           conn: conn
         } do
      {:ok, view, _html} = live(conn, ~p"/writs")
      upload_tsm_export(view)

      id = writ_id!("Craftsman's Writ: Elixir of Ogre's Strength")
      view |> element("input[phx-value-id='#{id}']") |> render_click()
      html = open_shopping_list(view)

      refute html =~ "rf-shopping-fab-badge"
      assert html =~ "<strong>1</strong>"
      assert html =~ "writs selected"
      assert html =~ "Craftsman&#39;s Writ: Elixir of Ogre&#39;s Strength"
      assert html =~ "Elixir of Ogre Strength"
      assert html =~ "Copy for Auctionator"
    end

    test "the Auctionator export text has Auctionator's real *** header and one item name per line, no quantities",
         %{
           conn: conn
         } do
      {:ok, view, _html} = live(conn, ~p"/writs")
      upload_tsm_export(view)

      id = writ_id!("Craftsman's Writ: Elixir of Ogre's Strength")
      view |> element("input[phx-value-id='#{id}']") |> render_click()
      html = open_shopping_list(view)

      assert html =~
               "data-copy=\"*** WoW Forever Writs\nCraftsman&#39;s Writ: Elixir of Ogre&#39;s Strength\nElixir of Ogre Strength\n\""
    end

    test "unchecking the only selected writ hides the FAB and popup entirely", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/writs")
      upload_tsm_export(view)

      id = writ_id!("Craftsman's Writ: Elixir of Ogre's Strength")
      view |> element("input[phx-value-id='#{id}']") |> render_click()
      html = view |> element("input[phx-value-id='#{id}']") |> render_click()

      refute html =~ "rf-shopping-fab"
    end

    test "the clear button empties the selection and hides the FAB", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/writs")
      upload_tsm_export(view)

      id = writ_id!("Craftsman's Writ: Elixir of Ogre's Strength")
      view |> element("input[phx-value-id='#{id}']") |> render_click()
      open_shopping_list(view)
      html = view |> element("button", "clear") |> render_click()

      refute html =~ "rf-shopping-fab"
    end

    test "a selected writ with unknown cost still appears on the list by name, cost shown as unknown",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/writs")
      upload_tsm_export(view)

      pending_id = writ_id!("Craftsman's Writ: Heavy Bronze Mace")
      view |> element("input[phx-value-id='#{pending_id}']") |> render_click()
      html = open_shopping_list(view)

      assert html =~ "Craftsman&#39;s Writ: Heavy Bronze Mace"
      assert html =~ "total cost"
    end

    test "each checked writ gets a number in selection order, and the popup groups by that same number",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/writs")
      upload_tsm_export(view)

      first_id = writ_id!("Craftsman's Writ: Elixir of Ogre's Strength")
      second_id = writ_id!("Craftsman's Writ: Heavy Bronze Mace")

      html1 = view |> element("input[phx-value-id='#{first_id}']") |> render_click()
      # The first writ checked shows a "1" badge right away, on the table row itself.
      assert html1 =~ ~r/rf-writ-number[^>]*>\s*1\s*</

      html2 = view |> element("input[phx-value-id='#{second_id}']") |> render_click()
      assert html2 =~ ~r/rf-writ-number[^>]*>\s*2\s*</

      popup = open_shopping_list(view)

      # Both writs' own groups show up, each tagged with its number,
      # each still listing its own writ item line under that group.
      assert popup =~
               ~r/rf-writ-number[^>]*>\s*1\s*<\/span>\s*<span>Craftsman&#39;s Writ: Elixir of Ogre&#39;s Strength/

      assert popup =~
               ~r/rf-writ-number[^>]*>\s*2\s*<\/span>\s*<span>Craftsman&#39;s Writ: Heavy Bronze Mace/
    end

    test "unchecking the first of two selected writs renumbers the remaining one", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/writs")
      upload_tsm_export(view)

      first_id = writ_id!("Craftsman's Writ: Elixir of Ogre's Strength")
      second_id = writ_id!("Craftsman's Writ: Heavy Bronze Mace")

      view |> element("input[phx-value-id='#{first_id}']") |> render_click()
      view |> element("input[phx-value-id='#{second_id}']") |> render_click()
      html = view |> element("input[phx-value-id='#{first_id}']") |> render_click()

      # The remaining writ (formerly #2) is now #1 — numbers reflect
      # current position, not a sticky tag assigned once.
      assert html =~ ~r/rf-writ-number[^>]*>\s*1\s*</
      refute html =~ ~r/rf-writ-number[^>]*>\s*2\s*</
    end
  end

  describe "writ route map (docs/PRD.md § 7.10) — FAB + floating panel, table stays visible" do
    test "the map FAB is shown once the real world map loads", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/writs")
      html = upload_tsm_export(view)

      assert html =~ "rf-map-fab"
    end

    test "the Horde faction toggle is on by default, Alliance is not", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/writs")
      html = upload_tsm_export(view)

      assert html =~ ~r/rf-side-chip on[^>]*>\s*Horde/
      refute html =~ ~r/rf-side-chip on[^>]*>\s*Alliance/
    end

    test "switching to Alliance hides a writ friendly to Horde only, without a re-upload", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/writs")
      upload_tsm_export(view)

      # Goblin Rocket Fuel's fixture hand-in is {alliance: -1, horde: 1}.
      html = view |> element("button.rf-side-chip", "Alliance") |> render_click()

      refute html =~ "Goblin Rocket Fuel"
      assert html =~ "Elixir of Ogre&#39;s Strength"
    end

    test "clicking the map FAB opens a floating panel (not a full-page modal) listing every placed pin",
         %{
           conn: conn
         } do
      {:ok, view, _html} = live(conn, ~p"/writs")
      upload_tsm_export(view)

      html = view |> element("button.rf-map-fab") |> render_click()

      assert html =~ "rf-map-popup"
      refute html =~ "rf-map-backdrop"
      # Sos'mol (Elixir of Ogre's Strength's hand-in) is placed; Heavy
      # Bronze Mace's hand-in has no coordinates at all and is not.
      assert html =~ "Sos&#39;mol"
    end

    test "a writ whose hand-in has no coordinates at all is never shown as a pin", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/writs")
      upload_tsm_export(view)

      view |> element("button.rf-map-fab") |> render_click()
      # Gorgrash (Heavy Bronze Mace's hand-in, no zone_id/coordinates in
      # the fixture) is legitimately in the table's NPC column — scope
      # to the map's own pin list, not the whole page, to prove it has
      # no pin rather than merely that the word appears somewhere.
      panel_html = view |> element(".rf-map-panel-list") |> render()

      refute panel_html =~ "Gorgrash"
    end

    test "clicking a pin's row in the panel shows that NPC's writs and a waypoint command", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/writs")
      upload_tsm_export(view)

      view |> element("button.rf-map-fab") |> render_click()
      html = view |> element(".rf-map-panel-row", "Sos'mol") |> render_click()

      assert html =~ "Sos&#39;mol"
      assert html =~ "Craftsman&#39;s Writ: Elixir of Ogre&#39;s Strength"
      assert html =~ "/way Alterac Mountains"
      assert html =~ "← All pins"
    end

    test "each table row carries its pin id as a data attribute, for the client-side hover-flash",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/writs")
      html = upload_tsm_export(view)

      assert html =~ ~s(data-pin-id="npc-257281")
    end
  end
end
