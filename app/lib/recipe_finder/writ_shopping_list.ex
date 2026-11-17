defmodule WowForeverRecipeFinder.WritShoppingList do
  @moduledoc """
  Aggregates the writ item and every required item across a visitor's
  selected writs into one shopping list — per docs/PRD.md § 7.9, one
  line per distinct item name, quantities summed across every selected
  writ that needs it. Pure function, no I/O — see
  docs/ELIXIR_TEST_MANIFESTO.md § What Still Gets a Plain Unit Test.

  `to_auctionator_text/2` exports Auctionator's real Shopping List
  format, verified directly from its own Lua source
  (`Atr_ShpList_Export_GetText` / `Atr_SList_ImportCore` in
  `AuctionatorConfig.lua`) rather than assumed — a `*** <list name>`
  header line, then one plain item display name per line. That format
  has **no quantity field at all**, so quantities computed here are
  this app's own display concern and are dropped entirely on export.
  """

  alias WowForeverRecipeFinder.WritEfficiencyResult

  @type line :: %{
          display_name: String.t(),
          quantity: pos_integer(),
          unit_price_copper: non_neg_integer() | nil,
          line_total_copper: non_neg_integer() | nil
        }

  @doc "One line per distinct item name across every selected writ's writ item + required items, quantities summed."
  @spec build([WritEfficiencyResult.t()], MapSet.t()) :: [line()]
  def build(results, selected_writ_ids) do
    results
    |> Enum.filter(&MapSet.member?(selected_writ_ids, &1.writ.id))
    |> Enum.flat_map(&writ_lines/1)
    |> merge_by_name()
    |> Enum.sort_by(& &1.display_name)
  end

  @doc "Total reputation if every selected writ were turned in — nil selections contribute nothing, never a fabricated figure."
  @spec total_reputation([WritEfficiencyResult.t()], MapSet.t()) :: non_neg_integer()
  def total_reputation(results, selected_writ_ids) do
    results
    |> Enum.filter(&MapSet.member?(selected_writ_ids, &1.writ.id))
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
    "*** #{list_name}\n" <> Enum.map_join(lines, "\n", & &1.display_name) <> "\n"
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

  defp merge_by_name(lines) do
    lines
    |> Enum.group_by(& &1.display_name)
    |> Enum.map(fn {name, group} -> merge_group(name, group) end)
  end

  defp merge_group(name, group) do
    %{
      display_name: name,
      quantity: Enum.sum(Enum.map(group, & &1.quantity)),
      unit_price_copper: Enum.find_value(group, & &1.unit_price_copper),
      line_total_copper: total_cost_copper(group)
    }
  end
end
