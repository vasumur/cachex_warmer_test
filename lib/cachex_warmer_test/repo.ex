defmodule CachexWarmerTest.Repo do
  use Ecto.Repo,
    otp_app: :cachex_warmer_test,
    adapter: Ecto.Adapters.Postgres
end
