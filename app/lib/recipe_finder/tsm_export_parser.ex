defmodule WowForeverRecipeFinder.TsmExportParser do
  @moduledoc """
  Parses a TSM `AppData.lua` export into a `PriceSnapshot`. See
  docs/DATA_SOURCES.md § TSM Export Format for the verified contract
  this module implements — every numeric fact below (the base-32 digit
  set, the `/1000` and `/10` scaling) is cited there, not invented here.

  Reads `AUCTIONDB_REGION_SALE` (region-wide) as the primary, required
  table, per docs/PRD.md § 7.1: it's the only table carrying a
  sold-per-day figure at all. Also reads every `AUCTIONDB_NON_COMMODITY_DATA`
  block present (realm-level) to fill in `ItemPrice.recent_value_copper`
  ("Recent Value" in TSM's own tooltip) — optional, since that table
  only covers non-commodity items and a visitor's export might have
  none, or several (TSM keeps history for every realm it has ever
  scanned, not just the one currently played). Every realm's figures
  are kept separately on the returned `PriceSnapshot`
  (`recent_values_by_realm`) rather than silently merged or guessed at
  — which realm's prices actually apply is a choice the visitor makes
  via the realm selector, never this parser's to make. The snapshot
  defaults to the most-recently-scanned realm (`PriceSnapshot.for_realm/2`
  switches it).
  """

  alias WowForeverRecipeFinder.{ItemPrice, PriceSnapshot}

  @table_name "AUCTIONDB_REGION_SALE"
  @recent_value_table "AUCTIONDB_NON_COMMODITY_DATA"

  # One `LoadData("TABLE","Region",[[return {...}]]) --<TABLE,Region,timestamp[,count]>`
  # line. The trailing comment's timestamp (a Unix epoch second) is what
  # `find_all_table_bodies/2` uses to pick the most-recently-scanned
  # realm when a visitor's export has more than one — see its own doc.
  @load_data_regex ~r/LoadData\("([^"]+)","([^"]+)",\[\[return (.*?)\]\]\)\s*--<[^,]+,[^,]+,(\d+)(?:,\d+)?>/s

  @type error ::
          {:no_load_data_lines_found}
          | {:table_not_found, String.t()}
          | {:no_usable_rows, String.t()}

  @spec parse(binary()) :: {:ok, PriceSnapshot.t()} | {:error, error()}
  def parse(export_text) when is_binary(export_text) do
    case find_table_body(export_text, @table_name) do
      nil ->
        if Regex.run(@load_data_regex, export_text) do
          {:error, {:table_not_found, @table_name}}
        else
          {:error, {:no_load_data_lines_found}}
        end

      body ->
        with {:ok, fields, rows} <- parse_table_body(body),
             {:ok, prices_by_item_id} <- build_price_map(fields, rows) do
          if map_size(prices_by_item_id) == 0 do
            {:error, {:no_usable_rows, @table_name}}
          else
            {recent_values_by_realm, default_realm} = collect_recent_values(export_text)

            snapshot =
              PriceSnapshot.for_realm(
                %PriceSnapshot{
                  prices_by_item_id: prices_by_item_id,
                  available_realms: recent_values_by_realm |> Map.keys() |> Enum.sort(),
                  recent_values_by_realm: recent_values_by_realm
                },
                default_realm
              )

            {:ok, snapshot}
          end
        end
    end
  end

  # --- table extraction -------------------------------------------------

  defp find_table_body(export_text, table_name) do
    @load_data_regex
    |> Regex.scan(export_text, capture: :all_but_first)
    |> Enum.find_value(fn
      [^table_name, _region, body, _timestamp] -> body
      _other -> nil
    end)
  end

  # Unlike find_table_body/2, returns every match — a visitor's export
  # can carry one AUCTIONDB_NON_COMMODITY_DATA table per realm they've
  # ever scanned with TSM (it keeps history for every realm, not just
  # the one currently played), not just one. Sorted oldest-to-newest by
  # each block's own capture timestamp, so a caller that merges them by
  # reducing left-to-right has the most-recently-scanned realm's prices
  # win on any item both realms have — never an arbitrary, undefined
  # "whichever realm happened to be written last in the file" ordering
  # (confirmed as the actual prior bug: a stale/alt-realm price for an
  # item silently overwrote the correct, current-realm one). Each entry
  # carries its realm name too, so the caller can report which realm
  # won and which were ignored — per docs/PRD.md, a visitor playing
  # several realms should be able to see that, not have it decided
  # invisibly.
  defp find_all_table_bodies(export_text, table_name) do
    @load_data_regex
    |> Regex.scan(export_text, capture: :all_but_first)
    |> Enum.filter(fn [name, _region, _body, _timestamp] -> name == table_name end)
    |> Enum.map(fn [_name, region, body, timestamp] ->
      {region, body, String.to_integer(timestamp)}
    end)
    |> Enum.sort_by(fn {_region, _body, timestamp} -> timestamp end)
  end

  defp parse_table_body(body) do
    with {:ok, fields} <- extract_fields(body),
         {:ok, data_str} <- extract_data_literal(body) do
      {:ok, fields, split_top_level_rows(data_str)}
    end
  end

  defp extract_fields(body) do
    case Regex.run(~r/fields=\{([^}]*)\}/, body) do
      [_, fields_str] ->
        fields =
          fields_str
          |> String.split(",")
          |> Enum.map(&String.trim(&1, "\""))

        {:ok, fields}

      nil ->
        {:error, {:missing_fields_literal}}
    end
  end

  defp extract_data_literal(body) do
    case Regex.run(~r/data=\{(.*)\}\s*$/s, body) do
      [_, data_str] -> {:ok, data_str}
      nil -> {:error, {:missing_data_literal}}
    end
  end

  # Splits `{a,b,c},{d,e,f},...` into ["a,b,c", "d,e,f", ...], respecting
  # nested braces (a row can itself contain nested `{}`, e.g. a nil-hole
  # placeholder) rather than naively splitting on every `},{`.
  defp split_top_level_rows(data_str) do
    data_str
    |> String.to_charlist()
    |> Enum.reduce({0, [], []}, fn
      ?{, {0, _cur, rows} -> {1, [], rows}
      ?{, {depth, cur, rows} -> {depth + 1, [?{ | cur], rows}
      ?}, {1, cur, rows} -> {0, [], [cur |> Enum.reverse() |> List.to_string() | rows]}
      ?}, {depth, cur, rows} -> {depth - 1, [?} | cur], rows}
      _ch, {0, cur, rows} -> {0, cur, rows}
      ch, {depth, cur, rows} -> {depth, [ch | cur], rows}
    end)
    |> elem(2)
    |> Enum.reverse()
  end

  # --- value decoding -----------------------------------------------------

  # `itemString` is the one field TSM writes as a plain decimal integer,
  # never base-32 — confirmed directly against real captured exports
  # (e.g. item 14175 appears literally as "14175", not as its base-32
  # digits, which would decode to a nonsense six-figure number). Every
  # other numeric field is base-32. docs/DATA_SOURCES.md previously
  # claimed item IDs were base-32 "like everything else" — that was
  # wrong, caught only once this field-aware decode replaced a
  # per-token heuristic (see decode_token/2's own comment for why that
  # heuristic was a real, silent correctness bug, not just imprecise).
  @decimal_field "itemString"

  # A row's comma-separated tokens, decoded one per field by name so a
  # price-like field is always read as base-32 even when its digits
  # happen to need no A-V letters (see decode_token/2) — never guessed
  # from the token's own shape.
  defp decode_row(row_str, fields) do
    row_str
    |> String.split(",")
    |> Enum.zip(fields)
    |> Enum.map(fn {token, field_name} -> decode_token(token, field_name) end)
  end

  # The previous implementation guessed a token's base from its own
  # shape alone: "every character is 0-9" meant decimal, anything else
  # meant base-32. That's wrong whenever a base-32 number's digits all
  # happen to land in 0-9 by chance (no A-V needed) — common enough to
  # matter: e.g. a price of 1033 copper is "109" in base-32, which the
  # old heuristic silently misread as decimal 109 — a ~9.5x understated
  # price, confirmed against a real reported case (see
  # tsm_export_parser_test.exs's multi-realm regression test and
  # docs/DATA_SOURCES.md). Deciding by the field's own name instead of
  # the token's shape has no such ambiguity.
  defp decode_token(token, field_name) do
    token = String.trim(token)

    cond do
      token == "" ->
        nil

      String.starts_with?(token, "\"") ->
        String.trim(token, "\"")

      field_name == @decimal_field ->
        case Integer.parse(token) do
          {int, ""} -> int
          _ -> token
        end

      true ->
        case Integer.parse(token, 32) do
          {int, ""} -> int
          _ -> token
        end
    end
  end

  # --- building the price map ---------------------------------------------

  defp build_price_map(fields, rows) do
    with {:ok, item_idx} <- field_index(fields, "itemString"),
         {:ok, sale_idx} <- field_index(fields, "regionSale"),
         {:ok, sold_idx} <- field_index(fields, "regionSoldPerDay"),
         {:ok, conf_idx} <- field_index(fields, "regionSalePercent") do
      prices =
        rows
        |> Enum.map(&decode_row(&1, fields))
        |> Enum.reduce(%{}, fn values, acc ->
          with wowhead_id when is_integer(wowhead_id) <- Enum.at(values, item_idx),
               price when is_integer(price) <- Enum.at(values, sale_idx),
               raw_sold when is_integer(raw_sold) <- Enum.at(values, sold_idx),
               raw_conf when is_integer(raw_conf) <- Enum.at(values, conf_idx) do
            price_struct = %ItemPrice{
              wowhead_id: wowhead_id,
              price_copper: price,
              # docs/DATA_SOURCES.md: regionSoldPerDay is raw/1000.
              sold_per_day: raw_sold / 1000.0,
              # docs/DATA_SOURCES.md: regionSalePercent is raw/10.
              sale_confidence_pct: raw_conf / 10.0
            }

            Map.put(acc, wowhead_id, price_struct)
          else
            _incomplete_row -> acc
          end
        end)

      {:ok, prices}
    end
  end

  # Best-effort: a missing/malformed AUCTIONDB_NON_COMMODITY_DATA table
  # just means no recent-value figures for that realm, never a parse
  # failure — it's an optional enrichment of the required region table.
  #
  # Returns `{recent_values_by_realm, default_realm}` — every realm's
  # own itemID→recent_value_copper map, kept separate (never merged
  # into one; see PriceSnapshot's own doc for why a visitor playing
  # several realms needs them distinguishable, not blended), plus
  # which realm to select by default (the most recently scanned one
  # that actually parsed) until the visitor picks one via the realm
  # selector.
  defp collect_recent_values(export_text) do
    parsed =
      export_text
      |> find_all_table_bodies(@recent_value_table)
      |> Enum.flat_map(fn {region, body, timestamp} ->
        case parse_table_body(body) do
          {:ok, fields, rows} -> [{region, recent_values_from_rows(fields, rows), timestamp}]
          {:error, _reason} -> []
        end
      end)

    recent_values_by_realm =
      Enum.reduce(parsed, %{}, fn {region, values, _timestamp}, acc ->
        Map.update(acc, region, values, &Map.merge(&1, values))
      end)

    default_realm =
      case List.last(parsed) do
        {region, _values, _timestamp} -> region
        nil -> nil
      end

    {recent_values_by_realm, default_realm}
  end

  defp recent_values_from_rows(fields, rows) do
    with {:ok, item_idx} <- field_index(fields, "itemString"),
         {:ok, recent_idx} <- field_index(fields, "marketValueRecent") do
      rows
      |> Enum.map(&decode_row(&1, fields))
      |> Enum.reduce(%{}, fn values, acc ->
        with wowhead_id when is_integer(wowhead_id) <- Enum.at(values, item_idx),
             recent when is_integer(recent) <- Enum.at(values, recent_idx) do
          Map.put(acc, wowhead_id, recent)
        else
          _incomplete_row -> acc
        end
      end)
    else
      {:error, _reason} -> %{}
    end
  end

  defp field_index(fields, name) do
    case Enum.find_index(fields, &(&1 == name)) do
      nil -> {:error, {:missing_field, name}}
      idx -> {:ok, idx}
    end
  end
end
