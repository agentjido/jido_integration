defmodule Mix.Tasks.Jido.Integration.New do
  use Mix.Task

  @moduledoc """
  Scaffold a new v2 connector package in the workspace root.

  ## Usage

      mix jido.integration.new github
      mix jido.integration.new codex_cli --runtime-class session
      mix jido.integration.new market_data --runtime-class stream
      mix jido.integration.new custom_ai --module MyApp.Connectors.CustomAi

  ## Options

  - `--runtime-class` - `direct`, `session`, or `stream` (default: `direct`)
  - `--module` - fully qualified connector module override
  - `--path` - package output path relative to the workspace root
  - `--package-name` - human-readable package name override used in docs and `mix.exs`
  """

  alias Jido.Integration.Workspace.ConnectorScaffold

  @shortdoc "Scaffold a new v2 connector package"

  @impl Mix.Task
  def run(args) do
    {opts, positional, invalid} =
      OptionParser.parse(args,
        strict: [
          runtime_class: :string,
          module: :string,
          path: :string,
          package_name: :string,
          workspace_root: :string
        ],
        aliases: [r: :runtime_class, m: :module, p: :path]
      )

    validate_invalid_options!(invalid)

    connector_name = resolve_connector_name!(positional)
    context = ConnectorScaffold.generate!(connector_name, opts)

    Mix.shell().info("""

    Connector #{context.connector_name} scaffolded successfully!

    Generated files:
    #{Enum.map_join(ConnectorScaffold.generated_relative_paths(context), "\n", &"  #{&1}")}

    Next steps:
      1. Replace the placeholder capability and provider logic with the real connector contract.
      2. Update #{Path.relative_to(Path.join(context.package_root, context.conformance_file), context.workspace_root)} so the deterministic fixture matches the real behavior.
      3. Run: cd #{context.package_root_relative} && mix deps.get
      4. Run: cd #{context.package_root_relative} && mix test
      5. Run: cd #{context.package_root_relative} && mix docs
      6. Run: mix jido.conformance #{context.connector_module}
    """)
  end

  defp validate_invalid_options!([]), do: :ok

  defp validate_invalid_options!(invalid) do
    formatted =
      invalid
      |> Enum.map(fn
        {option, nil} when is_atom(option) -> Atom.to_string(option)
        {option, nil} -> to_string(option)
        {option, value} -> "#{option}=#{value}"
      end)
      |> Enum.join(", ")

    Mix.raise("Invalid options: #{formatted}")
  end

  defp resolve_connector_name!([connector_name]), do: connector_name

  defp resolve_connector_name!([]) do
    Mix.raise("""
    No connector name specified.

    Usage: mix jido.integration.new <connector_name>
    """)
  end

  defp resolve_connector_name!(connectors) do
    Mix.raise("Expected exactly one connector name, got: #{Enum.join(connectors, ", ")}")
  end
end
