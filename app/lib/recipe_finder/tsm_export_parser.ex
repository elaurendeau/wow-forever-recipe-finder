defmodule WowForeverRecipeFinder.TsmExportParser do
  @moduledoc """
  Parses a TSM `AppData.lua` export into a `PriceSnapshot`. See
  docs/DATA_SOURCES.md § TSM Export Format for the verified contract
  this module implements — every numeric fact below (the base-32 digit
  set, the `/1000` and `/10` scaling) is cited there, not invented here.

  Reads only `AUCTIONDB_REGION_SALE` (region-wide), per docs/PRD.md §
  7.1: it's the only table carrying a sold-per-day figure at all.
  """

  alias WowForeverRecipeFinder.{ItemPrice, PriceSnapshot}

  @table_name "AUCTIONDB_REGION_SALE"

  # One `LoadData("TABLE","Region",[[return {...}]])` line.
  @load_data_regex ~r/LoadData\("([^"]+)","([^"]+)",\[\[return (.*?)\]\]\)\s*--</s

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
            {:ok, %PriceSnapshot{prices_by_item_id: prices_by_item_id}}
          end
        end
    end
  end

  # --- table extraction -------------------------------------------------

  defp find_table_body(export_text, table_name) do
    @load_data_regex
    |> Regex.scan(export_text, capture: :all_but_first)
    |> Enum.find_value(fn
      [^table_name, _region, body] -> body
      _other -> nil
    end)
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

  # A row's comma-separated tokens: a bare quoted string, a plain decimal
  # number (used as-is, no base-32 decoding), or a base-32-encoded
  # integer (every other numeric field, item IDs included) — see
  # docs/DATA_SOURCES.md § TSM Export Format.
  defp decode_row(row_str) do
    row_str
    |> String.split(",")
    |> Enum.map(&decode_token/1)
  end

  defp decode_token(token) do
    token = String.trim(token)

    cond do
      token == "" ->
        nil

      String.starts_with?(token, "\"") ->
        String.trim(token, "\"")

      decimal?(token) ->
        if String.contains?(token, "."), do: String.to_float(token), else: String.to_integer(token)

      true ->
        case Integer.parse(token, 32) do
          {int, ""} -> int
          _ -> token
        end
    end
  end

  defp decimal?(token), do: Regex.match?(~r/^\d+(\.\d+)?$/, token)

  # --- building the price map ---------------------------------------------

  defp build_price_map(fields, rows) do
    with {:ok, item_idx} <- field_index(fields, "itemString"),
         {:ok, sale_idx} <- field_index(fields, "regionSale"),
         {:ok, sold_idx} <- field_index(fields, "regionSoldPerDay"),
         {:ok, conf_idx} <- field_index(fields, "regionSalePercent") do
      prices =
        rows
        |> Enum.map(&decode_row/1)
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

  defp field_index(fields, name) do
    case Enum.find_index(fields, &(&1 == name)) do
      nil -> {:error, {:missing_field, name}}
      idx -> {:ok, idx}
    end
  end
end
