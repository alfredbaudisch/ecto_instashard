defmodule Ecto.InstaShard.Mixfile do
  use Mix.Project

  def project do
    [app: :ecto_instashard,
     version: "0.5.0",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     docs: [source_ref: "v0.2.1", main: "readme", extras: ["README.md"]],
     description: description(),
     package: package(),
     deps: deps()]
  end

  def application do
    [applications: [:logger]]
  end

  defp deps do
    [{:postgrex, "~> 0.13"},
     {:ecto, "~> 2.2"},
     {:ex_doc, "~> 0.19.0", only: :dev},
     {:earmark, ">= 0.0.0"}]
  end

  defp description do
    """
    Dynamic Instagram-like PostgreSQL sharding with Ecto
    """
  end

  defp package do
    [name: :ecto_instashard,
     maintainers: ["Alfred Reinold Baudisch"],
     licenses: ["Apache 2.0"],
     links: %{"GitHub" => "https://github.com/alfredbaudisch/ecto_instashard"},
     files: ~w(mix.exs README.md lib LICENSE)]
  end
end
