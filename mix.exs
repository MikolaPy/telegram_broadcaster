defmodule TelegramBroadcaster.MixProject do
  use Mix.Project

  def project do
    [
      app: :telegram_broadcaster,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {TelegramBroadcaster.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:ecto_sql, "~> 3.10"},
      {:myxql, "~> 0.6"},
      {:redix, "~> 1.2"},
      {:jason, "~> 1.4"},
      {:finch, "~> 0.18"},
      {:plug_cowboy, "~> 2.7"},
      {:castore, "~> 1.0"}
    ]
  end
end
