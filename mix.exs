defmodule EventStream.MixProject do
  use Mix.Project

  def project do
    [
      app: :event_stream,
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      package: package(),
      deps: deps(),
      source_url: "https://github.com/VoiceLayer/event_stream",
      homepage: "https://github.com/VoiceLayer/event_stream"
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
      {:ex_doc, "~> 0.21.3", only: :dev, runtime: false}
    ]
  end

  defp package() do
    [
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*),
      description: "Encoder/decoder for AWS Event Stream Encoding",
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/VoiceLayer/event_stream"}
    ]
  end
end
