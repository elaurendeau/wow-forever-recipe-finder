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
      with_recent =
        Enum.count(snapshot.prices_by_item_id, fn {_id, p} -> p.recent_value_copper end)

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

    test "when an export carries more than one realm's AUCTIONDB_NON_COMMODITY_DATA, the most recently scanned realm's recent value wins, not whichever realm happened to be written last in the file" do
      # Regression test: TSM keeps history for every realm it has ever
      # scanned, not just the one currently played, so a real export
      # can carry several AUCTIONDB_NON_COMMODITY_DATA blocks. The
      # fixture lists the OLDER-timestamped realm FIRST and the NEWER
      # one SECOND — happens to match file order here on purpose, so
      # this test isolates the timestamp-based tie-break itself rather
      # than also exercising the separate base-32-ambiguity bug below
      # (every token in this fixture contains a letter).
      export = read_fixture!("multi_realm.lua")

      assert {:ok, snapshot} = TsmExportParser.parse(export)
      assert {:ok, price} = PriceSnapshot.fetch_price(snapshot, 4625)
      assert price.recent_value_copper == 1544
    end

    test "the snapshot defaults to the most recently scanned realm and lists every realm available to switch to" do
      # The user's own real question: there's no way to tell (or
      # choose) which realm's prices are being shown. The fixture
      # carries two realms' AUCTIONDB_NON_COMMODITY_DATA — the
      # snapshot must default to the more recently scanned one and
      # list both so a visitor can pick via the realm selector.
      export = read_fixture!("multi_realm.lua")

      assert {:ok, snapshot} = TsmExportParser.parse(export)
      assert snapshot.realm == "PvP-Horde"
      assert snapshot.available_realms == ["PvP-Horde", "Stale-OldRealm"]
    end

    test "PriceSnapshot.for_realm/2 switches to another realm's figures without blending them" do
      export = read_fixture!("multi_realm.lua")
      assert {:ok, snapshot} = TsmExportParser.parse(export)

      switched = PriceSnapshot.for_realm(snapshot, "Stale-OldRealm")
      assert switched.realm == "Stale-OldRealm"
      assert {:ok, price} = PriceSnapshot.fetch_price(switched, 4625)
      assert price.recent_value_copper == 109
    end

    test "a single-realm export reports that realm as the only one available" do
      export = read_fixture!("snapshot_1.lua")

      assert {:ok, snapshot} = TsmExportParser.parse(export)
      assert snapshot.realm == "PvP-Horde"
      assert snapshot.available_realms == ["PvP-Horde"]
    end

    test "a base-32 price whose digits all happen to be 0-9 is still read as base-32, not misread as decimal" do
      # Regression test for the actual bug behind a real user report:
      # a price of 1033 copper is "109" in TSM's base-32 encoding (no
      # A-V letters needed for that particular value) — decode_token/2
      # used to guess a token's base from its own shape ("all digits"
      # meant decimal), which silently misread this as decimal 109
      # instead of base-32 1033. A ~9.5x understatement, confirmed
      # against the real screenshot that reported it. Deciding by the
      # field's name (itemString is the one genuinely-decimal field;
      # everything else is always base-32) has no such ambiguity.
      export = read_fixture!("ambiguous_base32_token.lua")

      assert {:ok, snapshot} = TsmExportParser.parse(export)
      assert {:ok, price} = PriceSnapshot.fetch_price(snapshot, 4625)
      assert price.recent_value_copper == 1033
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
