defmodule Mix.Tasks.Jido.Integration.New do
  @moduledoc """
  Scaffold a new connector.

  ## Usage

      mix jido.integration.new github
      mix jido.integration.new my_saas --module MyApp.Connectors.MySaas
      mix jido.integration.new my_saas --layout core

  ## Options

  - `--module` — fully qualified module name (default: derived from provider name)
  - `--path` — output path. For `package` layout this is the package root directory.
    For `core` layout this is the adapter file or directory.
  - `--domain` — connector domain: `saas`, `protocol`, `ai`, `devtools`, `infra` (default: `saas`)
  - `--layout` — `package` or `core` (default: `package`)

  ## Generated Files

  Package layout:

  - `packages/connectors/<provider>/mix.exs`
  - `packages/connectors/<provider>/README.md`
  - `packages/connectors/<provider>/lib/.../<provider>.ex`
  - `packages/connectors/<provider>/priv/.../manifest.json`
  - `packages/connectors/<provider>/test/...`
  - `packages/connectors/<provider>/test/fixtures/<provider>/`

  Core layout:

  - `lib/.../adapter.ex`
  - `priv/.../manifest.json`
  - `test/...`
  - `test/fixtures/<provider>/`
  """

  use Mix.Task

  @shortdoc "Scaffold a new integration connector"

  @valid_domains ~w(saas protocol ai devtools infra)
  @valid_layouts ~w(package core)

  @impl Mix.Task
  def run(args) do
    {opts, positional, _} =
      OptionParser.parse(args,
        strict: [module: :string, path: :string, domain: :string, layout: :string],
        aliases: [m: :module, p: :path, d: :domain]
      )

    provider = resolve_provider(positional)
    module_name = resolve_module(provider, opts)
    domain = resolve_domain(opts)
    layout = resolve_layout(opts)
    paths = resolve_paths(provider, opts, layout)

    context = %{
      provider: provider,
      provider_display: provider_display(provider),
      module_name: module_name,
      module_alias: module_alias(module_name),
      project_module_name: "#{module_name}.MixProject",
      domain: domain,
      layout: layout,
      connector_id: provider,
      package_app: "jido_integration_#{provider}",
      paths: paths,
      manifest_relative_path: Path.relative_to(paths.manifest, Path.dirname(paths.adapter)),
      core_dep_path:
        if(layout == "package", do: package_root_to_project_root(paths.package_root), else: nil)
    }

    generate(context)
    print_summary(context)
  end

  defp resolve_provider([]),
    do: Mix.raise("Provider name required. Usage: mix jido.integration.new <provider>")

  defp resolve_provider([provider | _]), do: provider

  defp resolve_module(provider, opts) do
    case Keyword.get(opts, :module) do
      nil ->
        camelized =
          provider
          |> String.split("_")
          |> Enum.map_join(&String.capitalize/1)

        "Jido.Integration.Connectors.#{camelized}"

      module ->
        module
    end
  end

  defp resolve_domain(opts) do
    domain = Keyword.get(opts, :domain, "saas")

    unless domain in @valid_domains do
      Mix.raise("Invalid domain: #{domain}. Must be one of: #{Enum.join(@valid_domains, ", ")}")
    end

    domain
  end

  defp resolve_layout(opts) do
    layout = Keyword.get(opts, :layout, "package")

    unless layout in @valid_layouts do
      Mix.raise("Invalid layout: #{layout}. Must be one of: #{Enum.join(@valid_layouts, ", ")}")
    end

    layout
  end

  defp resolve_paths(provider, opts, "core") do
    base_path = Keyword.get(opts, :path, "lib/jido/integration/connectors/#{provider}")

    adapter_path =
      if Path.extname(base_path) == ".ex" do
        base_path
      else
        Path.join(base_path, "adapter.ex")
      end

    %{
      adapter: adapter_path,
      manifest: "priv/jido/integration/connectors/#{provider}/manifest.json",
      adapter_test: "test/jido/integration/connectors/#{provider}_test.exs",
      conformance_test: "test/jido/integration/connectors/#{provider}_conformance_test.exs",
      fixture_dir: "test/fixtures/#{provider}"
    }
  end

  defp resolve_paths(provider, opts, "package") do
    package_root = Keyword.get(opts, :path, "packages/connectors/#{provider}")

    if Path.extname(package_root) == ".ex" do
      Mix.raise("--path must point to a package directory when --layout package is used")
    end

    %{
      package_root: package_root,
      mix_exs: Path.join(package_root, "mix.exs"),
      readme: Path.join(package_root, "README.md"),
      test_helper: Path.join(package_root, "test/test_helper.exs"),
      adapter: Path.join(package_root, "lib/jido/integration/connectors/#{provider}.ex"),
      manifest:
        Path.join(package_root, "priv/jido/integration/connectors/#{provider}/manifest.json"),
      adapter_test:
        Path.join(package_root, "test/jido/integration/connectors/#{provider}_test.exs"),
      conformance_test:
        Path.join(
          package_root,
          "test/jido/integration/connectors/#{provider}_conformance_test.exs"
        ),
      fixture_dir: Path.join(package_root, "test/fixtures/#{provider}")
    }
  end

  defp module_alias(module_name) do
    module_name |> String.split(".") |> List.last()
  end

  defp generate(%{layout: "package"} = context) do
    write_file(context.paths.mix_exs, package_mix_template(context))
    write_file(context.paths.readme, package_readme_template(context))
    write_file(context.paths.test_helper, test_helper_template())
    generate_common_files(context)
  end

  defp generate(context) do
    generate_common_files(context)
  end

  defp generate_common_files(context) do
    write_file(context.paths.manifest, manifest_template(context))
    write_file(context.paths.adapter, adapter_template(context))
    write_file(context.paths.adapter_test, adapter_test_template(context))
    write_file(context.paths.conformance_test, conformance_test_template(context))
    write_file(Path.join(context.paths.fixture_dir, "success.json"), fixture_template(context))
  end

  defp write_file(path, content) do
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, content)
    Mix.shell().info("  * creating #{path}")
  end

  defp print_summary(context) do
    files =
      generated_files(context)
      |> Enum.map_join("\n", &"  #{&1}")

    next_steps =
      case context.layout do
        "package" ->
          """
          1. Define operations in the manifest
          2. Implement run/3 for each operation
          3. Add fixtures for determinism testing
          4. Run: cd #{context.paths.package_root} && mix test
          5. Run: cd #{context.paths.package_root} && mix jido.conformance #{context.module_name} --profile bronze
          """

        _ ->
          """
          1. Define operations in the manifest
          2. Implement run/3 for each operation
          3. Add fixtures for determinism testing
          4. Run: mix test #{context.paths.adapter_test}
          5. Run: mix jido.conformance #{context.module_name} --profile bronze
          """
      end

    Mix.shell().info("""

    Connector #{context.provider} scaffolded successfully!

    Generated files:
    #{files}

    Next steps:
    #{next_steps}
    """)
  end

  defp generated_files(%{layout: "package", paths: paths}) do
    [
      paths.mix_exs,
      paths.readme,
      paths.test_helper,
      paths.adapter,
      paths.manifest,
      paths.adapter_test,
      paths.conformance_test,
      Path.join(paths.fixture_dir, "success.json")
    ]
  end

  defp generated_files(%{paths: paths}) do
    [
      paths.adapter,
      paths.manifest,
      paths.adapter_test,
      paths.conformance_test,
      Path.join(paths.fixture_dir, "success.json")
    ]
  end

  defp package_mix_template(context) do
    """
    defmodule #{context.project_module_name} do
      use Mix.Project

      def project do
        [
          app: :#{context.package_app},
          version: "0.1.0",
          elixir: "~> 1.17",
          start_permanent: Mix.env() == :prod,
          deps: deps(),
          preferred_cli_env: [conformance: :test]
        ]
      end

      def application do
        [
          extra_applications: [:logger, :crypto]
        ]
      end

      defp deps do
        [
          {:jido_integration, path: "#{context.core_dep_path}"},
          {:jason, "~> 1.4"}
        ]
      end
    end
    """
  end

  defp package_readme_template(context) do
    """
    # #{context.provider_display}

    `#{context.package_app}` is a first-party connector package for `jido_integration`.

    ## Connector Module

    - `#{context.module_name}`

    ## Development

    ```bash
    mix test
    mix jido.conformance #{context.module_name} --profile bronze
    ```
    """
  end

  defp test_helper_template do
    "ExUnit.start(exclude: [:skip])\n"
  end

  defp adapter_template(context) do
    """
    defmodule #{context.module_name} do
      @moduledoc \"\"\"
      #{context.provider_display} connector.

      ## Operations

      - `#{context.connector_id}.hello` — placeholder operation

      ## Auth

      Configure authentication in the manifest's auth descriptors.
      \"\"\"

      @behaviour Jido.Integration.Adapter

      alias Jido.Integration.{Error, Manifest}

      @manifest_path Path.expand("#{context.manifest_relative_path}", __DIR__)

      @impl true
      def id, do: "#{context.connector_id}"

      @impl true
      def manifest do
        @manifest_path
        |> File.read!()
        |> Jason.decode!()
        |> Manifest.new!()
      end

      @impl true
      def validate_config(config) when is_map(config), do: {:ok, config}
      def validate_config(_), do: {:error, Error.new(:invalid_request, "config must be a map")}

      @impl true
      def health(_opts), do: {:ok, %{status: :healthy}}

      @impl true
      def run("#{context.connector_id}.hello", %{"message" => message}, _opts) do
        {:ok, %{"reply" => message, "connector_id" => id()}}
      end

      def run(operation_id, _args, _opts) do
        {:error, Error.new(:unsupported, "Unknown operation: \#{operation_id}")}
      end
    end
    """
  end

  defp adapter_test_template(context) do
    """
    defmodule #{context.module_name}Test do
      use ExUnit.Case

      alias #{context.module_name}
      alias Jido.Integration.Operation

      describe "adapter contract" do
        test "id/0 returns connector id" do
          assert #{context.module_alias}.id() == "#{context.connector_id}"
        end

        test "manifest/0 returns valid manifest" do
          manifest = #{context.module_alias}.manifest()
          assert manifest.id == "#{context.connector_id}"
          assert is_list(manifest.operations)
        end

        test "validate_config/1 accepts maps" do
          assert {:ok, _} = #{context.module_alias}.validate_config(%{})
        end

        test "health/1 returns healthy" do
          assert {:ok, %{status: :healthy}} = #{context.module_alias}.health([])
        end
      end

      describe "operations" do
        test "hello operation echoes message" do
          assert {:ok, result} =
                   #{context.module_alias}.run("#{context.connector_id}.hello", %{"message" => "test"}, [])

          assert result["reply"] == "test"
          assert result["connector_id"] == "#{context.connector_id}"
        end

        test "unknown operation returns error" do
          assert {:error, _} = #{context.module_alias}.run("unknown", %{}, [])
        end
      end

      describe "execute through control plane" do
        test "hello via execute/3" do
          envelope = Operation.Envelope.new("#{context.connector_id}.hello", %{"message" => "integration"})
          assert {:ok, result} = Jido.Integration.execute(#{context.module_alias}, envelope)
          assert result.result["reply"] == "integration"
        end
      end
    end
    """
  end

  defp conformance_test_template(context) do
    """
    defmodule #{context.module_name}ConformanceTest do
      use ExUnit.Case

      alias #{context.module_name}

      @moduletag :conformance
      @fixture_dir "test/fixtures/#{context.provider}"

      describe "conformance" do
        test "passes mvp_foundation profile" do
          report = Jido.Integration.Conformance.run(#{context.module_alias}, profile: :mvp_foundation)
          assert report.pass_fail == :pass, inspect_failures(report)
        end

        test "passes bronze profile" do
          report = Jido.Integration.Conformance.run(#{context.module_alias}, profile: :bronze)
          assert report.pass_fail == :pass, inspect_failures(report)
        end

        test "passes silver profile with fixtures" do
          report =
            Jido.Integration.Conformance.run(#{context.module_alias},
              profile: :silver,
              fixture_dir: @fixture_dir
            )

          assert report.pass_fail == :pass, inspect_failures(report)
        end
      end

      defp inspect_failures(report) do
        report
        |> Jido.Integration.Conformance.failures()
        |> Enum.map(& &1.name)
        |> Enum.join(", ")
      end
    end
    """
  end

  defp fixture_template(context) do
    Jason.encode!(
      %{
        "operation_id" => "#{context.connector_id}.hello",
        "input" => %{"message" => "fixture_test"},
        "expected" => %{
          "reply" => "fixture_test",
          "connector_id" => context.connector_id
        }
      },
      pretty: true
    )
  end

  defp manifest_template(context) do
    Jason.encode!(
      %{
        "id" => context.connector_id,
        "display_name" => context.provider_display,
        "vendor" => context.provider_display,
        "domain" => context.domain,
        "version" => "0.1.0",
        "quality_tier" => "bronze",
        "telemetry_namespace" => "jido.integration.#{context.connector_id}",
        "auth" => [
          %{
            "id" => "none",
            "type" => "none",
            "display_name" => "No Auth",
            "secret_refs" => [],
            "scopes" => [],
            "rotation_policy" => %{"required" => false, "interval_days" => nil},
            "tenant_binding" => "tenant_only",
            "health_check" => %{"enabled" => false, "interval_s" => 0}
          }
        ],
        "operations" => [
          %{
            "id" => "#{context.connector_id}.hello",
            "summary" => "Placeholder operation",
            "input_schema" => %{
              "type" => "object",
              "required" => ["message"],
              "properties" => %{"message" => %{"type" => "string"}}
            },
            "output_schema" => %{
              "type" => "object",
              "properties" => %{
                "reply" => %{"type" => "string"},
                "connector_id" => %{"type" => "string"}
              }
            },
            "errors" => [],
            "idempotency" => "none",
            "timeout_ms" => 5_000,
            "rate_limit" => "gateway_default",
            "required_scopes" => []
          }
        ],
        "capabilities" => %{}
      },
      pretty: true
    )
  end

  defp provider_display(provider) do
    provider
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp package_root_to_project_root(package_root) do
    package_root
    |> Path.split()
    |> then(fn segments ->
      List.duplicate("..", length(segments))
    end)
    |> Path.join()
  end
end
