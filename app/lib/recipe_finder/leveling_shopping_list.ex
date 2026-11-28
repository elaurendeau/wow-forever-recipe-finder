defmodule WowForeverRecipeFinder.LevelingShoppingList do
  @moduledoc """
  The per-segment shopping list behind docs/PRD.md § 7.13's "copy for
  Auctionator" popup: for one path segment's recipe, how much of
  everything a visitor needs to buy to craft it `crafts_needed` times —
  the recipe's own one-time purchase item (if it has one) plus every
  reagent, each scaled by `crafts_needed`. `crafts_needed` is the
  visitor-facing, rounded-up form of `LevelingResult.expected_crafts/3`
  (an estimate — see `SkillUpCurve`'s own doc); this module only turns
  a chosen craft count into a priced list, it doesn't estimate one
  itself.
  """

  alias WowForeverRecipeFinder.{AuctionatorExport, LevelingResult}

  @type line :: %{
          display_name: String.t(),
          quantity: pos_integer(),
          unit_price_copper: non_neg_integer() | nil,
          line_total_copper: non_neg_integer() | nil
        }

  @doc "The recipe's own purchase item (quantity 1, if it has one — never for a trainer recipe) followed by every reagent at `crafts_needed` times its per-craft quantity."
  @spec build_lines(LevelingResult.t(), pos_integer()) :: [line()]
  def build_lines(%LevelingResult{} = result, crafts_needed) do
    recipe_item_line(result) ++ reagent_lines(result, crafts_needed)
  end

  @doc "Total cost across every line, or `nil` if any line's cost is unknown — never a partial sum presented as the whole."
  @spec total_cost_copper([line()]) :: non_neg_integer() | nil
  def total_cost_copper(lines) do
    if Enum.all?(lines, & &1.line_total_copper) do
      Enum.sum(Enum.map(lines, & &1.line_total_copper))
    end
  end

  @doc "Auctionator's real Shopping List import/export text — see `AuctionatorExport` for where this format was verified."
  @spec to_auctionator_text(String.t(), [line()]) :: String.t()
  def to_auctionator_text(list_name, lines), do: AuctionatorExport.to_text(list_name, lines)

  defp recipe_item_line(%LevelingResult{pattern: %{recipe_cost_item: nil}}), do: []

  defp recipe_item_line(%LevelingResult{pattern: %{recipe_cost_item: item}} = result) do
    [
      %{
        display_name: item.display_name,
        quantity: 1,
        unit_price_copper: result.recipe_cost_copper,
        line_total_copper: result.recipe_cost_copper
      }
    ]
  end

  defp reagent_lines(
         %LevelingResult{profit_result: %{reagent_breakdown: breakdown}},
         crafts_needed
       ) do
    Enum.map(breakdown, fn reagent ->
      quantity = reagent.quantity * crafts_needed

      %{
        display_name: reagent.display_name,
        quantity: quantity,
        unit_price_copper: reagent.unit_price_copper,
        line_total_copper: reagent.unit_price_copper && reagent.unit_price_copper * quantity
      }
    end)
  end
end
