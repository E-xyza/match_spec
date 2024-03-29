defmodule MatchSpec.MixProject do
  use Mix.Project

  def project do
    [
      app: :match_spec,
      version: "0.3.3",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "helper module for match specs",
      package: package(),
      source_url: "https://github.com/e-xyza/match_spec",
      docs: [
        main: "MatchSpec",
        extras: ["README.md"]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:mix_test_watch, "~> 1.1", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:ex_doc, "~> 0.29.1", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      # These are the default files included in the package
      files: ~w(lib .formatter.exs mix.exs README* LICENSE* CHANGELOG*),
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/e-xyza/match_spec",
        "Sponsor" => "https://github.com/sponsors/E-xyza"
      }
    ]
  end
end
