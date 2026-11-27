defmodule WowForeverRecipeFinder.Gateways.EctoCrateRepositoryGateway do
  @moduledoc """
  The real, Postgres-backed implementation of `CrateRepositoryGateway`.
  Converts `Gateways.Schema.*` rows into plain `WowForeverRecipeFinder.*`
  domain structs at this boundary — nothing past this module ever sees
  an `Ecto.Schema` struct for the crate catalog. See docs/CODE_STYLE.md
  § Clean Architecture.
  """

  @behaviour WowForeverRecipeFinder.Gateways.CrateRepositoryGateway

  alias WowForeverRecipeFinder.Repo
  alias WowForeverRecipeFinder.{FillOption, WaylaidCrate}
  alias WowForeverRecipeFinder.Gateways.Schema

  @impl true
  def list_crates do
    Schema.WaylaidCrate
    |> Repo.all()
    |> Repo.preload(:fill_options)
    |> Enum.map(&to_domain/1)
  end

  defp to_domain(%Schema.WaylaidCrate{} = row) do
    %WaylaidCrate{
      id: row.id,
      name: row.name,
      tier: parse_tier!(row.tier),
      category: row.category,
      variant: row.variant,
      quality: parse_quality!(row.quality),
      wowhead_id: row.wowhead_id,
      required_level: row.required_level,
      fill_options:
        if(row.fill_options_captured, do: Enum.map(row.fill_options, &to_fill_option/1))
    }
  end

  defp to_fill_option(%Schema.WaylaidCrateFillOption{} = row) do
    %FillOption{
      display_name: row.display_name,
      wowhead_id: row.wowhead_id,
      quantity: row.quantity
    }
  end

  defp parse_tier!("apprentice"), do: :apprentice
  defp parse_tier!("journeyman"), do: :journeyman
  defp parse_tier!("expert"), do: :expert
  defp parse_tier!("artisan"), do: :artisan
  defp parse_tier!(other), do: raise(ArgumentError, "unknown crate tier: #{inspect(other)}")

  defp parse_quality!("common"), do: :common
  defp parse_quality!("uncommon"), do: :uncommon
  defp parse_quality!(other), do: raise(ArgumentError, "unknown crate quality: #{inspect(other)}")
end
