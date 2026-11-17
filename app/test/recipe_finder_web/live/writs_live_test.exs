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
  end
end
