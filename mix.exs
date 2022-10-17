defmodule PyCell.MixProject do
  use Mix.Project

  def project do
    [
      app: :py_cell,
      version: "0.1.1",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {PyCell.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:kino, "~> 0.7.0"},
      {:jason, "~> 1.4"}
    ]
  end
end
