defmodule WowForeverRecipeFinder.Repo.Migrations.CreateCrateTables do
  use Ecto.Migration

  @moduledoc """
  See docs/SCHEMA.md § Waylaid Crate catalog for the rationale.
  Static, shared reference data only, same as the writ catalog tables.
  """

  def change do
    create table(:waylaid_crate) do
      add :wowhead_id, :integer, null: false
      add :name, :string, null: false
      add :tier, :string, null: false
      add :category, :string, null: false
      add :variant, :string
      add :quality, :string, null: false
      add :required_level, :integer, null: false
      # false means the extraction hasn't read this crate's tooltip
      # yet (Wowhead rate-limited the session) — not that it has no
      # fill options. See docs/SCHEMA.md and WaylaidCrate's moduledoc.
      add :fill_options_captured, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:waylaid_crate, [:wowhead_id])

    create table(:waylaid_crate_fill_option) do
      add :waylaid_crate_id, references(:waylaid_crate, on_delete: :delete_all), null: false
      add :display_name, :string, null: false
      # Null when this app's catalog has no item-ID resolution for the
      # material (e.g. raw Ore — Mining was never scraped, it has no
      # crafted output). See docs/DATA_SOURCES.md.
      add :wowhead_id, :integer
      add :quantity, :integer, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
