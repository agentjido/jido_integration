defmodule Jido.Integration.V2.StorePostgres.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_integration_v2_store_postgres,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: false,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "Jido Integration V2 Store Postgres",
      description: "Postgres durability package owning Repo, migrations, and sandbox posture"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ecto_sql, :crypto],
      mod: {Jido.Integration.V2.StorePostgres.Application, []}
    ]
  end

  defp deps do
    [
      {:jido_integration_v2_contracts, path: "../contracts"},
      {:jido_integration_v2_auth, path: "../auth"},
      {:jido_integration_v2_control_plane, path: "../control_plane"},
      {:ecto, "~> 3.13.4"},
      {:ecto_sql, "~> 3.13.4"},
      {:postgrex, "~> 0.21.1"},
      {:credo, "~> 1.7.17", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end

  defp dialyzer do
    [plt_add_deps: :apps_direct]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "../../guides/durability.md",
        "../../guides/architecture.md",
        "../../guides/observability.md"
      ],
      groups_for_extras: [
        Overview: ["README.md"],
        Guides: [
          "../../guides/durability.md",
          "../../guides/architecture.md",
          "../../guides/observability.md"
        ]
      ]
    ]
  end
end
