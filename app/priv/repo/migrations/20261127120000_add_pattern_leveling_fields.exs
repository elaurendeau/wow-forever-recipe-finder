defmodule WowForeverRecipeFinder.Repo.Migrations.AddPatternLevelingFields do
  use Ecto.Migration

  # See docs/PRD.md § 7.13 and docs/DATA_SOURCES.md for provenance —
  # both fields come from a real Wowhead data capture (not Classic-
  # formula assumptions), merged into the existing catalog_seeds JSON
  # files rather than re-scraped from scratch.
  def change do
    alter table(:pattern) do
      # [orange, yellow, green, grey] skill thresholds, as Wowhead's own
      # `g_listviews.spells.data[].colors` reports them — a leading 0
      # means that band is skipped for this recipe (see
      # ProfessionLeveling's own doc), never a literal skill-0
      # threshold. `null` for the handful of recipes Wowhead has no
      # color data for at all.
      add :skill_up_colors, {:array, :integer}

      # The recipe/pattern's own purchasable item (a "Pattern: X" /
      # "Plans: X" / etc. item), for recipes that must be bought rather
      # than trained — `null` for trainer-taught recipes (no AH cost
      # applies) and for the small number of non-trainer recipes this
      # capture couldn't match to a specific item.
      add :recipe_cost_item, :map
    end
  end
end
