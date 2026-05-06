defmodule Jido.Integration.ConnectorGenerator do
  @moduledoc """
  Connector SDK skeleton generator.
  """

  @spec external_companion_files(String.t(), keyword()) :: [{String.t(), String.t()}]
  def external_companion_files(connector_name, opts \\ []) when is_binary(connector_name) do
    context = context!(connector_name, opts)

    [
      {".formatter.exs", formatter()},
      {"README.md", readme(context)},
      {"mix.exs", mix_project(context)},
      {"lib/#{context.module_file}.ex", connector_module(context)},
      {"test/#{context.module_file}_conformance_test.exs", conformance_test(context)},
      {"test/test_helper.exs", "ExUnit.start()\n"}
    ]
  end

  @spec generate!(String.t(), keyword()) :: map()
  def generate!(connector_name, opts \\ []) do
    workspace_root = opts |> Keyword.get(:workspace_root, File.cwd!()) |> Path.expand()
    context = context!(connector_name, Keyword.put(opts, :workspace_root, workspace_root))

    package_root =
      opts
      |> Keyword.get(:path, "companions/#{context.connector_name}")
      |> Path.expand(workspace_root)

    files = external_companion_files(connector_name, opts)

    Enum.each(files, fn {relative_path, content} ->
      target_path = Path.join(package_root, relative_path)
      File.mkdir_p!(Path.dirname(target_path))
      File.write!(target_path, content)
    end)

    generated_relative_paths =
      Enum.map(files, fn {relative_path, _content} ->
        package_root
        |> Path.join(relative_path)
        |> Path.relative_to(workspace_root)
      end)

    context
    |> Map.put(:package_root, package_root)
    |> Map.put(:generated_relative_paths, generated_relative_paths)
  end

  defp context!(connector_name, opts) do
    connector_name = normalize_connector_name!(connector_name)

    module_name =
      Keyword.get(opts, :module, "ExternalCompanions.#{Macro.camelize(connector_name)}")

    module_file = module_name |> module_file()

    %{
      connector_name: connector_name,
      module_name: module_name,
      module_file: module_file,
      app_name: "#{connector_name}_companion",
      package_name:
        Keyword.get(opts, :package_name, "#{Macro.camelize(connector_name)} Companion")
    }
  end

  defp normalize_connector_name!(connector_name) do
    normalized =
      connector_name
      |> String.trim()
      |> String.downcase()
      |> String.replace("-", "_")

    cond do
      normalized == "" ->
        raise ArgumentError, "connector name is required"

      not valid_identifier?(normalized) ->
        raise ArgumentError, "connector name must use lowercase letters, digits, and underscores"

      true ->
        normalized
    end
  end

  defp valid_identifier?(value) do
    value
    |> String.to_charlist()
    |> Enum.all?(&valid_identifier_char?/1)
  end

  defp valid_identifier_char?(char) when char in ?a..?z, do: true
  defp valid_identifier_char?(char) when char in ?0..?9, do: true
  defp valid_identifier_char?(?_), do: true
  defp valid_identifier_char?(_char), do: false

  defp module_file(module_name) do
    module_name
    |> String.split(".")
    |> Enum.map(&Macro.underscore/1)
    |> Path.join()
  end

  defp formatter do
    """
    [
      inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
    ]
    """
  end

  defp readme(context) do
    """
    # #{context.package_name}

    External companion connector skeleton for `#{context.connector_name}`.

    ## Boundary

    This package compiles against `:jido_integration_contracts` and runs
    lightweight conformance through `:jido_integration_conformance_contracts`.
    Platform admission still requires explicit host app config, connector
    admission records, tenant authority, credential handles, guard posture,
    budget refs, and trace refs.

    No provider token, auth header, raw provider payload, prompt body, or memory
    body belongs in this package's manifest or conformance fixtures.

    ## Verification

    ```bash
    mix test
    ```
    """
  end

  defp mix_project(context) do
    """
    defmodule #{context.module_name}.MixProject do
      use Mix.Project

      def project do
        [
          app: :#{context.app_name},
          version: "0.1.0",
          elixir: "~> 1.19",
          start_permanent: Mix.env() == :prod,
          deps: deps(),
          name: "#{context.package_name}",
          description: "External companion connector skeleton for #{context.connector_name}"
        ]
      end

      def application do
        [extra_applications: [:logger]]
      end

      defp deps do
        [
          {:jido_integration_contracts, path: "../../core/contracts"},
          {:jido_integration_conformance_contracts, path: "../../core/conformance_contracts"},
          {:zoi, "~> 0.17"},
          {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
        ]
      end
    end
    """
  end

  defp connector_module(context) do
    """
    defmodule #{context.module_name} do
      @behaviour Jido.Integration.V2.Connector

      alias Jido.Integration.V2.AuthSpec
      alias Jido.Integration.V2.CatalogSpec
      alias Jido.Integration.V2.Manifest
      alias Jido.Integration.V2.OperationSpec

      defmodule Handler do
        def run(_input, _context), do: {:ok, %{}}
      end

      @impl true
      def manifest do
        Manifest.new!(%{
          connector: "#{context.connector_name}",
          auth:
            AuthSpec.new!(%{
              binding_kind: :connection_id,
              supported_profiles: [
                %{
                  id: "default_manual_secret",
                  auth_type: :api_token,
                  subject_kind: :user,
                  install_required: false,
                  durable_secret_fields: ["api_token"],
                  lease_fields: ["api_token"],
                  management_modes: [:external_secret, :manual],
                  required_scopes: ["#{context.connector_name}:run"],
                  grant_types: [:manual_token],
                  callback_required: false,
                  pkce_required: false,
                  refresh_supported: false,
                  revoke_supported: false,
                  reauth_supported: false,
                  external_secret_supported: true,
                  external_secret_lease_fields: [],
                  docs_refs: [],
                  metadata: %{}
                }
              ],
              default_profile: "default_manual_secret",
              install: %{required: false},
              reauth: %{supported: false},
              management_modes: [:external_secret, :manual],
              requested_scopes: ["#{context.connector_name}:run"],
              durable_secret_fields: ["api_token"],
              lease_fields: ["api_token"],
              secret_names: []
            }),
          catalog:
            CatalogSpec.new!(%{
              display_name: "#{context.package_name}",
              description: "External companion connector",
              category: "external_companion",
              tags: ["#{context.connector_name}"],
              docs_refs: [],
              maturity: :experimental,
              publication: :public
            }),
          operations: [
            OperationSpec.new!(%{
              operation_id: "#{context.connector_name}.sample.perform",
              name: "sample_perform",
              runtime_class: :direct,
              transport_mode: :sdk,
              handler: Handler,
              input_schema: Zoi.object(%{message: Zoi.string()}),
              output_schema: Zoi.object(%{message: Zoi.string()}),
              permissions: %{required_scopes: ["#{context.connector_name}:run"]},
              policy: %{
                environment: %{allowed: [:dev, :test]},
                sandbox: %{level: :standard, egress: :restricted, approvals: :auto, allowed_tools: []}
              },
              upstream: %{transport: :sdk},
              consumer_surface: %{mode: :connector_local, reason: "External companion surface"},
              schema_policy: %{input: :defined, output: :defined},
              jido: %{},
              metadata: %{scope_posture: %{tenant_scope: :tenant_scoped}}
            })
          ],
          triggers: [],
          runtime_families: [:direct],
          metadata: %{contract_version: "connector-sdk.v1"}
        })
      end
    end
    """
  end

  defp conformance_test(context) do
    """
    defmodule #{context.module_name}ConformanceTest do
      use Jido.Integration.ConformanceContracts.Case, connector: #{context.module_name}
    end
    """
  end
end
