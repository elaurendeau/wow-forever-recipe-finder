defmodule WowForeverRecipeFinder.TsmExportParserTest do
  use ExUnit.Case, async: true

  alias WowForeverRecipeFinder.{PriceSnapshot, TsmExportParser}

  @fixtures_dir Path.join([__DIR__, "..", "fixtures", "tsm_export"])

  defp read_fixture!(name), do: File.read!(Path.join(@fixtures_dir, name))

  describe "parse/1 against real captured exports" do
    test "parses the first real snapshot and decodes a value this session already hand-verified" do
      export = read_fixture!("snapshot_1.lua")

      assert {:ok, %PriceSnapshot{} = snapshot} = TsmExportParser.parse(export)
      assert map_size(snapshot.prices_by_item_id) > 0

      # Item 5571's AUCTIONDB_REGION_SALE row was independently decoded and
      # verified by hand during this project's research session:
      # {regionSale: 285, regionSoldPerDay: 41919, regionSalePercent: 413}.
      # This pins that exact result as a regression test.
      assert {:ok, price} = PriceSnapshot.fetch_price(snapshot, 5571)
      assert price.price_copper == 285
      assert_in_delta price.sold_per_day, 41.919, 0.0001
      assert_in_delta price.sale_confidence_pct, 41.3, 0.0001

      # Same item's AUCTIONDB_NON_COMMODITY_DATA row: {itemString: 5571,
      # minBuyout: "9C", numAuctions: "K1", marketValueRecent: "9C"} —
      # base-32 "9C" decodes to 300 (9*32 + 12).
      assert price.recent_value_copper == 300

      # AUCTIONDB_NON_COMMODITY_DATA only covers non-commodity items —
      # most of the region-wide price map's items (commodities like
      # cloth/ore bars) should have no recent value at all, never a
      # fabricated figure for an item TSM didn't actually track there.
      with_recent = Enum.count(snapshot.prices_by_item_id, fn {_id, p} -> p.recent_value_copper end)
      assert with_recent > 0
      assert with_recent < map_size(snapshot.prices_by_item_id)
    end

    test "parses the second real snapshot (captured a later session day)" do
      export = read_fixture!("snapshot_2.lua")

      assert {:ok, %PriceSnapshot{} = snapshot} = TsmExportParser.parse(export)
      assert map_size(snapshot.prices_by_item_id) > 0
    end

    test "parses the third real snapshot (captured for the Merchant's Favor analysis)" do
      export = read_fixture!("snapshot_3.lua")

      assert {:ok, %PriceSnapshot{} = snapshot} = TsmExportParser.parse(export)
      assert map_size(snapshot.prices_by_item_id) > 0
    end

    test "every decoded price has a non-negative copper value and a 0-100 confidence" do
      export = read_fixture!("snapshot_1.lua")
      assert {:ok, snapshot} = TsmExportParser.parse(export)

      for {_wowhead_id, price} <- snapshot.prices_by_item_id do
        assert price.price_copper >= 0
        assert price.sold_per_day >= 0.0
        assert price.sale_confidence_pct >= 0.0 and price.sale_confidence_pct <= 100.0
      end
    end
  end

  describe "parse/1 failure paths — fail loudly, per docs/ARCHITECTURE.md § 2" do
    test "a file with no LoadData lines at all is a specific, reported error" do
      export = read_fixture!("malformed_no_load_data.lua")

      assert {:error, {:no_load_data_lines_found}} = TsmExportParser.parse(export)
    end

    test "a syntactically valid export whose region-sale table has zero rows is its own specific error, not an empty-but-ok result" do
      export = read_fixture!("empty_region_sale.lua")

      assert {:error, {:no_usable_rows, "AUCTIONDB_REGION_SALE"}} = TsmExportParser.parse(export)
    end
  end
end
