defmodule WowForeverRecipeFinder.CrateCatalogSeeder do
  @moduledoc """
  Loads the Waylaid Crate catalog from a Wowhead-sourced extraction
  JSON file (see docs/PRD.md § 7.11 and docs/SCHEMA.md § Waylaid
  Crate catalog for provenance and shape) into Postgres. Used by
  `priv/repo/seeds.exs` and safe to re-run: each run atomically
  replaces the whole crate catalog — same "replace atomically" rule
  as `CatalogSeeder`/`WritCatalogSeeder`.

  Only the `waylaid_crates` list is persisted. The extraction's
  `sealed_crates` and `hand_in_quests` aren't modeled yet — see
  docs/SCHEMA.md for why.
  """

  alias WowForeverRecipeFinder.Repo
  alias WowForeverRecipeFinder.Gateways.Schema.{WaylaidCrate, WaylaidCrateFillOption}

  @spec load_from_file!(Path.t()) :: :ok
  def load_from_file!(path) do
    path
    |> File.read!()
    |> Jason.decode!()
    |> load!()

    :ok
  end

  defp load!(%{"waylaid_crates" => crates}) do
    Repo.transaction(fn ->
      Repo.delete_all(WaylaidCrate)
      Enum.each(crates, &insert_crate!/1)
    end)
  end

  defp insert_crate!(attrs) do
    fill_options = attrs["fill_options"]

    crate =
      Repo.insert!(%WaylaidCrate{
        wowhead_id: attrs["wowhead_id"],
        name: attrs["name"],
        tier: attrs["tier"],
        category: attrs["category"],
        variant: attrs["variant"],
        quality: attrs["quality"],
        required_level: attrs["required_level"],
        fill_options_captured: fill_options != nil
      })

    Enum.each(fill_options || [], &insert_fill_option!(crate, &1))

    crate
  end

  defp insert_fill_option!(crate, option_attrs) do
    Repo.insert!(%WaylaidCrateFillOption{
      waylaid_crate_id: crate.id,
      display_name: option_attrs["display_name"],
      wowhead_id: option_attrs["wowhead_id"],
      quantity: option_attrs["quantity"]
    })
  end
end
