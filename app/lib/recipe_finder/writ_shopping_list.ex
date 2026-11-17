defmodule WowForeverRecipeFinder.WritShoppingList do
  @moduledoc """
  Builds the shopping list for a visitor's selected writs — per
  docs/PRD.md § 7.9, one group per selected writ (writ item + its
  required item(s)), in selection order, numbered 1.. so each group
  can be identified back to the same number shown next to that writ's
  checkbox in the table. Pure functions, no I/O — see
  docs/ELIXIR_TEST_MANIFESTO.md § What Still Gets a Plain Unit Test.

  Deliberately **not** merged into one flat list by item name across
  writs (an earlier cut did this) — grouping by writ, each tagged with
  its selection number, is what the feature's own use case calls for:
  seeing which writ a given item is for.

  `to_auctionator_text/2` exports Auctionator's real Shopping List
  format, verified directly from its own Lua source
  (`Atr_ShpList_Export_GetText` / `Atr_SList_ImportCore` in
  `AuctionatorConfig.lua`) rather than assumed — a `*** <list name>`
  header line, then one plain item display name per line. That format
  has **no quantity field at all**, so quantities computed here are
  this app's own display concern and are dropped entirely on export;
  a name appearing in more than one group is deduplicated there too,
  since a repeated watch-list entry would be meaningless to it.
  """

  alias WowForeverRecipeFinder.{Writ, WritEfficiencyResult}

  @type line :: %{
          display_name: String.t(),
          quantity: pos_integer(),
          unit_price_copper: non_neg_integer() | nil,
          line_total_copper: non_neg_integer() | nil
        }

  @type group :: %{number: pos_integer(), writ: Writ.t(), lines: [line()]}

  @doc "One group per selected writ, in selection order, numbered 1.. — the writ item line first, then its required items."
  @spec build_groups([WritEfficiencyResult.t()], [pos_integer()]) :: [group()]
  def build_groups(results, selected_writ_ids_in_order) do
    results_by_writ_id = Map.new(results, &{&1.writ.id, &1})

    selected_writ_ids_in_order
    |> Enum.with_index(1)
    |> Enum.map(fn {writ_id, number} ->
      result = Map.fetch!(results_by_writ_id, writ_id)
      %{number: number, writ: result.writ, lines: writ_lines(result)}
    end)
  end

  @doc "Total reputation if every selected writ were turned in."
  @spec total_reputation([WritEfficiencyResult.t()], [pos_integer()]) :: non_neg_integer()
  def total_reputation(results, selected_writ_ids) do
    results
    |> Enum.filter(&(&1.writ.id in selected_writ_ids))
    |> Enum.map(& &1.total_reputation)
    |> Enum.sum()
  end

  @doc "Total cost in copper across every line, or nil if any line's cost is unknown — never a partial sum presented as the whole."
  @spec total_cost_copper([line()]) :: non_neg_integer() | nil
  def total_cost_copper([]), do: 0

  def total_cost_copper(lines) do
    if Enum.all?(lines, & &1.line_total_copper) do
      Enum.sum(Enum.map(lines, & &1.line_total_copper))
    end
  end

  @doc "Auctionator's real Shopping List import/export text — see the moduledoc for where this format was verified."
  @spec to_auctionator_text(String.t(), [line()]) :: String.t()
  def to_auctionator_text(list_name, lines) do
    names = lines |> Enum.uniq_by(& &1.display_name) |> Enum.map(& &1.display_name)
    "*** #{list_name}\n" <> Enum.join(names, "\n") <> "\n"
  end

  defp writ_lines(%WritEfficiencyResult{} = result) do
    writ = result.writ

    writ_item_line = %{
      display_name: writ.writ_item_display_name,
      quantity: 1,
      unit_price_copper: result.writ_item_cost_copper,
      line_total_copper: result.writ_item_cost_copper
    }

    [writ_item_line | result.required_item_breakdown]
  end
end
