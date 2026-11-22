defmodule WowForeverRecipeFinder.MerchantFavorFormulaTest do
  use ExUnit.Case, async: true

  alias WowForeverRecipeFinder.MerchantFavorFormula

  # Pins the formula against all 8 real Favor amounts the source
  # extraction's hand-in quests actually captured (5, 10, 15, 20, 10,
  # 20, 30, 40) — see MerchantFavorFormula's own moduledoc for how
  # these were matched to tier/quality. Every tier/quality combination
  # this app's real 30-crate catalog has is covered here, with zero
  # extrapolation beyond what's directly checked.
  test "matches every one of the 8 real captured hand-in quest Favor amounts" do
    assert MerchantFavorFormula.favor_amount(:apprentice, :common) == 5
    assert MerchantFavorFormula.favor_amount(:journeyman, :common) == 10
    assert MerchantFavorFormula.favor_amount(:expert, :common) == 15
    assert MerchantFavorFormula.favor_amount(:artisan, :common) == 20
    assert MerchantFavorFormula.favor_amount(:apprentice, :uncommon) == 10
    assert MerchantFavorFormula.favor_amount(:journeyman, :uncommon) == 20
    assert MerchantFavorFormula.favor_amount(:expert, :uncommon) == 30
    assert MerchantFavorFormula.favor_amount(:artisan, :uncommon) == 40
  end

  test "uncommon always pays exactly double common at the same tier" do
    for tier <- [:apprentice, :journeyman, :expert, :artisan] do
      common = MerchantFavorFormula.favor_amount(tier, :common)
      uncommon = MerchantFavorFormula.favor_amount(tier, :uncommon)
      assert uncommon == common * 2
    end
  end
end
