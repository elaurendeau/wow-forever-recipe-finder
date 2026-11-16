defmodule WowForeverRecipeFinder.Repo.Migrations.CreateWritTables do
  use Ecto.Migration

  @moduledoc """
  See docs/SCHEMA.md § Craftsman's Writ catalog for the rationale —
  in particular, why this is a separate set of tables rather than an
  extension of `item`/`pattern`: a writ's items are Wowhead-sourced
  AH-tradeable items, not Warcraft-Wiki-resolved crafting-catalog
  entries. Static, shared reference data only, same as the profession
  catalog tables in the init migration.
  """

  def change do
    create table(:faction) do
      add :wowhead_faction_id, :integer, null: false
      add :display_name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:faction, [:wowhead_faction_id])

    create table(:writ) do
      add :name, :string, null: false
      add :wowhead_quest_id, :integer, null: false
      add :writ_item_wowhead_id, :integer, null: false
      add :writ_item_display_name, :string, null: false
      add :profession_slugs, {:array, :string}, null: false
      add :tier, :string, null: false
      # Only a literal "daily" is trusted — null means "not yet
      # confirmed", never "one-time". See docs/SCHEMA.md.
      add :repeat, :string
      add :hand_in_npc_name, :string
      add :hand_in_zone, :string
      add :reward_money_copper, :integer, null: false, default: 0
      # complete | pending_quest_page — mirrors the extraction's own
      # data_status. A pending writ is still a row here, never dropped.
      add :resolution_status, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:writ, [:wowhead_quest_id])

    create table(:writ_required_item) do
      add :writ_id, references(:writ, on_delete: :delete_all), null: false
      add :wowhead_id, :integer, null: false
      add :display_name, :string, null: false
      add :quantity, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:writ_required_item, [:writ_id, :wowhead_id])

    create table(:writ_reputation_reward) do
      add :writ_id, references(:writ, on_delete: :delete_all), null: false
      add :faction_id, references(:faction, on_delete: :restrict), null: false
      add :amount, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:writ_reputation_reward, [:writ_id, :faction_id])
  end
end
