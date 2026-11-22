defmodule WowForeverRecipeFinder.CrateShoppingList do
  @moduledoc """
  Builds the shopping list for a visitor's chosen crate quantities —
  per docs/PRD.md § 7.11, one group per crate with a non-zero chosen
  quantity: the crate itself (× quantity) and its cheapest fill
  option's materials (× quantity). Pure functions, no I/O — see
  docs/ELIXIR_TEST_MANIFESTO.md § What Still Gets a Plain Unit Test.

  Unlike the writ shopping list (one of each selected writ, in
  selection order), this is a **quantity** per crate — "I want 5 of
  these" — since the goal is buying enough crates to reach some
  number of Sealed Crates, not picking a distinct set once each.
  """

  alias WowForeverRecipeFinder.{AuctionatorExport, CrateEfficiencyResult, WaylaidCrate}

  @type line :: %{
          display_name: String.t(),
          quantity: pos_integer(),
          unit_price_copper: non_neg_integer() | nil,
          line_total_copper: non_neg_integer() | nil
        }

  @type group :: %{
          crate: WaylaidCrate.t(),
          quantity: pos_integer(),
          favor_amount: pos_integer(),
          lines: [line()]
        }

  @doc "One group per crate with a chosen quantity > 0, crate id order — the crate line first, then its cheapest fill material (if known)."
  @spec build_groups([CrateEfficiencyResult.t()], %{pos_integer() => non_neg_integer()}) :: [
          group()
        ]
  def build_groups(results, quantities) do
    results_by_crate_id = Map.new(results, &{&1.crate.id, &1})

    quantities
    |> Enum.filter(fn {_crate_id, quantity} -> quantity > 0 end)
    |> Enum.sort_by(fn {crate_id, _quantity} -> crate_id end)
    |> Enum.map(fn {crate_id, quantity} ->
      result = Map.fetch!(results_by_crate_id, crate_id)

      %{
        crate: result.crate,
        quantity: quantity,
        favor_amount: result.favor_amount,
        lines: crate_lines(result, quantity)
      }
    end)
  end

  @doc """
  Total Merchant's Favor earned if every chosen quantity is turned in
  — per crate's own `favor_amount` (see `MerchantFavorFormula`; an
  estimated, not Wowhead-confirmed, figure) times its quantity, summed.
  Reads every chosen crate regardless of the table's current filter,
  same "selection isn't scoped to what's visible" rule as the cost
  total.
  """
  @spec total_favor([CrateEfficiencyResult.t()], %{pos_integer() => non_neg_integer()}) ::
          non_neg_integer()
  def total_favor(results, quantities) do
    results_by_crate_id = Map.new(results, &{&1.crate.id, &1})

    quantities
    |> Enum.filter(fn {_crate_id, quantity} -> quantity > 0 end)
    |> Enum.map(fn {crate_id, quantity} ->
      Map.fetch!(results_by_crate_id, crate_id).favor_amount * quantity
    end)
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

  @doc "Auctionator's real Shopping List import/export text — see `AuctionatorExport` for where this format was verified."
  @spec to_auctionator_text(String.t(), [line()]) :: String.t()
  def to_auctionator_text(list_name, lines), do: AuctionatorExport.to_text(list_name, lines)

  defp crate_lines(%CrateEfficiencyResult{} = result, quantity) do
    crate_line = %{
      display_name: result.crate.name,
      quantity: quantity,
      unit_price_copper: result.crate_cost_copper,
      line_total_copper: result.crate_cost_copper && result.crate_cost_copper * quantity
    }

    [crate_line | fill_lines(result, quantity)]
  end

  # No best_fill_option means the extraction hasn't captured this
  # crate's fill options yet, or none of them could be priced — there
  # is genuinely no material name to list yet, so the group is just
  # the crate line, same "flagged, not fabricated" rule as elsewhere.
  defp fill_lines(%CrateEfficiencyResult{best_fill_option: nil}, _quantity), do: []

  defp fill_lines(%CrateEfficiencyResult{best_fill_option: option} = result, quantity) do
    [
      %{
        display_name: option.display_name,
        quantity: option.quantity * quantity,
        unit_price_copper: unit_price(result, option),
        line_total_copper: result.fill_cost_copper && result.fill_cost_copper * quantity
      }
    ]
  end

  defp unit_price(%CrateEfficiencyResult{fill_cost_copper: nil}, _option), do: nil

  defp unit_price(%CrateEfficiencyResult{fill_cost_copper: total}, option),
    do: div(total, option.quantity)
end
