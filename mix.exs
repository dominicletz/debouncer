defmodule Debouncer.MixProject do
  use Mix.Project

  def project do
    [
      app: :debouncer,
      version: "0.1.10",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Hex
      description: "Debouncer is a flexible function call debouncer.",
      package: [
        licenses: ["Apache-2.0"],
        maintainers: ["Dominic Letz"],
        links: %{"GitHub" => "https://github.com/dominicletz/debouncer"}
      ],
      # Docs
      name: "Debouncer",
      source_url: "https://github.com/dominicletz/debouncer",
      docs: [
        # The main page in the docs
        main: "Debouncer",
        extras: ["README.md"]
      ],
      aliases: [
        lint: ["format --check-formatted", "credo --strict", "dialyzer"]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Debouncer, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.3", only: [:dev, :test], runtime: false}
    ]
  end
end
