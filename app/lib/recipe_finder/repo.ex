defmodule WowForeverRecipeFinder.Repo do
  use Ecto.Repo,
    otp_app: :recipe_finder,
    adapter: Ecto.Adapters.Postgres
end
