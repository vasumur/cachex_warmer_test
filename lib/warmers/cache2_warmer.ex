defmodule CachexWarmerTest.Warmers.Cachex2Warmer do
  use Cachex.Warmer

  def interval(), do: :timer.minutes(30)

  def execute(_connection) do
    {:ok, data()}
  end

  def data() do
    Process.sleep(:timer.minutes(2))
    [{1, "hello"}, {2, "world"}]
  end
end
