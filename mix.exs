defmodule Ecto.InstaShard.Mixfile do
  use Mix.Project

  def project do
    [app: :ecto_instashard,
     version: "0.1.1",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     docs: [source_ref: "v0.1.1", main: "readme", extras: ["README.md"]],
     description: description(),
     package: package(),
     deps: deps()]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [applications: [:logger]]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [{:postgrex, ">= 0.0.0"},
     {:ecto, "~> 2.0.0"},
     {:ex_doc, "~> 0.11.0", only: :dev},
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
