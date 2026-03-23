defmodule Mix.Tasks.Jido.Integration.New do
  use Mix.Task

  @moduledoc """
  Scaffold a new v2 connector package in the workspace root.

  The generated package is a generated starting contract, not a finished
  connector package. The scaffold gives you package-local manifest, handler,
  companion-module, and test seams, but the real connector contract, package
  README, deterministic expectations, and any live proof code still must be
  authored by hand. Keep provider inventory connector-local unless you
  explicitly author it into the manifest, and keep target descriptors as
  compatibility plus location advertisements rather than runtime overrides.

  Connector proof code belongs in the generated connector package rather than
  the workspace root.

  ## Usage

      mix jido.integration.new github
      mix jido.integration.new custom_ai --module MyApp.Connectors.CustomAi
      mix jido.integration.new analyst_cli --runtime-class session --runtime-driver asm
      mix jido.integration.new market_feed --runtime-class stream --runtime-driver asm

  ## Options

  - `--runtime-class` - `direct`, `session`, or `stream` (default: `direct`)
  - `--runtime-driver` - required for `session` and `stream` scaffolds;
    accepted values are `asm` or `jido_session` for `session`, and `asm` for
    `stream`
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
          runtime_driver: :string,
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
      1. Treat the generated package as a starting contract, not the finished connector package.
      2. Replace the placeholder authored manifest entries and provider logic with the real connector contract.
         Keep provider inventory connector-local unless you explicitly author it into the manifest.
      3. Update #{Path.relative_to(Path.join(context.package_root, context.conformance_file), context.workspace_root)} so the deterministic fixture matches the real behavior.
      4. Update #{Path.join(context.package_root_relative, "README.md")} so it states the runtime family, auth posture, package-local verification commands, and live-proof status.
         Target descriptors only advertise compatibility and location; they do not override authored runtime posture.
      5. Keep connector-local proof code inside #{context.package_root_relative}; move hosted webhook or async composition into an app only when that behavior is not part of the connector contract.
      6. Run: cd #{context.package_root_relative} && mix deps.get
      7. Run: cd #{context.package_root_relative} && mix compile --warnings-as-errors
      8. Run: cd #{context.package_root_relative} && mix test
      9. Run: cd #{context.package_root_relative} && mix docs
      10. Run: mix jido.conformance #{context.connector_module}
      11. Run: mix ci
    """)
  end

  defp validate_invalid_options!([]), do: :ok

  defp validate_invalid_options!(invalid) do
    formatted =
      Enum.map_join(invalid, ", ", fn
        {option, nil} when is_atom(option) -> Atom.to_string(option)
        {option, nil} -> to_string(option)
        {option, value} -> "#{option}=#{value}"
      end)

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
