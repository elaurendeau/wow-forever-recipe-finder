defmodule WowForeverRecipeFinder.Repo.Migrations.CreateCatalogTables do
  use Ecto.Migration

  @moduledoc """
  See docs/SCHEMA.md for the rationale behind this shape — in particular,
  why there is no table here for anything derived from a visitor's
  uploaded TSM export: these four tables are the shared, static
  profession-catalog reference data only.
  """

  def change do
    create table(:profession) do
      add :slug, :string, null: false
      add :display_name, :string, null: false
      add :catalog_built_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:profession, [:slug])

    create table(:item) do
      add :wowhead_id, :integer, null: false
      add :display_name, :string, null: false
      add :wiki_slug, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:item, [:wowhead_id])

    create table(:pattern) do
      add :profession_id, references(:profession, on_delete: :delete_all), null: false
      add :crafted_item_id, references(:item, on_delete: :restrict), null: false
      add :name, :string, null: false
      add :tier, :string, null: false
      add :skill, :integer, null: false
      # Nullable: Enchanting's formula table has no Source column at all
      # (see docs/DATA_SOURCES.md § Warcraft Wiki) — not every pattern has
      # a known source, and that's a real, expected state, not a gap.
      add :source, :string
      add :wiki_slug, :string, null: false
      # resolved | no_wiki_page | reagent_cost_incomplete — see docs/SCHEMA.md
      add :resolution_status, :string, null: false, default: "resolved"

      timestamps(type: :utc_datetime)
    end

    create index(:pattern, [:profession_id])
    create index(:pattern, [:crafted_item_id])

    create table(:pattern_reagent) do
      add :pattern_id, references(:pattern, on_delete: :delete_all), null: false
      add :item_id, references(:item, on_delete: :restrict), null: false
      add :quantity, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:pattern_reagent, [:pattern_id, :item_id])
  end
end
