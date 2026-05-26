defmodule TelegramBroadcaster.TestRedis do
  @moduledoc false
  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def stub(command, response) do
    Agent.update(__MODULE__, &Map.put(&1, command, {:ok, response}))
  end

  def command(_name, command) do
    Agent.get(__MODULE__, &Map.get(&1, command, {:ok, []}))
  end

  def pipeline(_name, commands) do
    Agent.get(__MODULE__, fn state ->
      results = Enum.map(commands, fn cmd ->
        Map.get(state, cmd, :ok)
      end)
      {:ok, results}
    end)
  end

  def reset do
    Agent.update(__MODULE__, fn _ -> %{} end)
  end
end
