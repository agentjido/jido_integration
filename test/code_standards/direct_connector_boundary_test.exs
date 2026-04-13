defmodule Jido.Integration.Workspace.DirectConnectorBoundaryTest do
  use ExUnit.Case, async: true

  @direct_connectors [
    %{
      mix_path: Path.expand("../../connectors/github/mix.exs", __DIR__),
      resolver_path:
        Path.expand("../../connectors/github/build_support/dependency_resolver.exs", __DIR__),
      test_root: Path.expand("../../connectors/github/test", __DIR__),
      catalog_path:
        Path.expand(
          "../../connectors/github/lib/jido/integration/v2/connectors/git_hub/operation_catalog.ex",
          __DIR__
        ),
      sdk_resolver_call: "ConnectorDependencyResolver.github_ex()",
      sdk_hex_dep: "{:github_ex, \"~> 0.1.0\", opts}",
      forbidden_sdk_fallbacks: ["GITHUB_EX_PATH", "nshkrdotcom/github_ex"]
    },
    %{
      mix_path: Path.expand("../../connectors/notion/mix.exs", __DIR__),
      resolver_path:
        Path.expand("../../connectors/notion/build_support/dependency_resolver.exs", __DIR__),
      test_root: Path.expand("../../connectors/notion/test", __DIR__),
      catalog_path:
        Path.expand(
          "../../connectors/notion/lib/jido/integration/v2/connectors/notion/operation_catalog.ex",
          __DIR__
        ),
      sdk_resolver_call: "ConnectorDependencyResolver.notion_sdk()",
      sdk_hex_dep: "{:notion_sdk, \"~> 0.2.0\", opts}",
      forbidden_sdk_fallbacks: ["NOTION_SDK_PATH", "nshkrdotcom/notion_sdk"]
    },
    %{
      mix_path: Path.expand("../../connectors/linear/mix.exs", __DIR__),
      resolver_path:
        Path.expand("../../connectors/linear/build_support/dependency_resolver.exs", __DIR__),
      test_root: Path.expand("../../connectors/linear/test", __DIR__),
      catalog_path:
        Path.expand(
          "../../connectors/linear/lib/jido/integration/v2/connectors/linear/operation_catalog.ex",
          __DIR__
        ),
      sdk_resolver_call: "ConnectorDependencyResolver.linear_sdk()",
      sdk_hex_dep: "{:linear_sdk, \"~> 0.2.0\", opts}",
      forbidden_sdk_fallbacks: ["LINEAR_SDK_PATH", "nshkrdotcom/linear_sdk"]
    }
  ]

  test "direct connector packages depend on direct_runtime and published provider SDKs only" do
    Enum.each(
      @direct_connectors,
      fn %{
           mix_path: mix_path,
           sdk_resolver_call: sdk_resolver_call
         } ->
        mix_exs = File.read!(mix_path)

        assert mix_exs =~ "WorkspaceDependencyResolver.jido_integration_v2_direct_runtime()",
               "#{mix_path} must depend on direct_runtime"

        assert mix_exs =~
                 "Code.require_file(\"../../build_support/dependency_resolver.exs\", __DIR__)",
               "#{mix_path} must load the shared workspace dependency resolver"

        assert mix_exs =~ "Code.require_file(\"build_support/dependency_resolver.exs\", __DIR__)",
               "#{mix_path} must load its provider-specific dependency resolver"

        assert mix_exs =~ sdk_resolver_call,
               "#{mix_path} must resolve its provider SDK through DependencyResolver"

        refute mix_exs =~ "pristine_runtime(",
               "#{mix_path} must not carry a direct pristine runtime dependency"

        refute mix_exs =~ ":jido_runtime_control",
               "#{mix_path} must not depend on jido_runtime_control"

        refute mix_exs =~ "agent_session_manager", "#{mix_path} must not depend on ASM directly"

        refute mix_exs =~ "cli_subprocess_core",
               "#{mix_path} must not depend on CLI subprocess core"

        refute mix_exs =~ "jido_session", "#{mix_path} must not depend on jido_session"
      end
    )
  end

  test "direct connector packages resolve provider SDKs from sibling paths locally and Hex otherwise" do
    Enum.each(
      @direct_connectors,
      fn %{
           mix_path: mix_path,
           resolver_path: resolver_path,
           sdk_hex_dep: sdk_hex_dep,
           forbidden_sdk_fallbacks: forbidden_sdk_fallbacks
         } ->
        mix_exs = File.read!(mix_path)
        resolver = File.read!(resolver_path)

        refute mix_exs =~ "deps/github_ex",
               "#{mix_path} must not vendor provider SDKs under deps/"

        refute mix_exs =~ "deps/notion_sdk",
               "#{mix_path} must not vendor provider SDKs under deps/"

        refute mix_exs =~ "deps/linear_sdk",
               "#{mix_path} must not vendor provider SDKs under deps/"

        refute mix_exs =~ "deps/pristine",
               "#{mix_path} must not vendor pristine under deps/"

        refute mix_exs =~ "deps/prismatic",
               "#{mix_path} must not vendor prismatic under deps/"

        assert resolver =~ sdk_hex_dep,
               "#{resolver_path} must fall back to a Hex dependency for its provider SDK"

        Enum.each(forbidden_sdk_fallbacks, fn forbidden_sdk_fallback ->
          refute resolver =~ forbidden_sdk_fallback,
                 "#{resolver_path} must not carry non-Hex, non-local SDK fallback #{inspect(forbidden_sdk_fallback)}"
        end)
      end
    )
  end

  test "direct connector packages declare lower-repo auth dependencies honestly" do
    Enum.each(
      @direct_connectors,
      fn %{mix_path: mix_path} ->
        mix_exs = File.read!(mix_path)

        refute mix_exs =~ "WorkspaceDependencyResolver.pristine(",
               "#{mix_path} must rely on provider SDK transitive auth deps instead of declaring pristine directly"

        refute mix_exs =~ "ConnectorDependencyResolver.prismatic(",
               "#{mix_path} must rely on provider SDK transitive auth deps instead of declaring prismatic directly"
      end
    )
  end

  test "direct connector catalogs publish direct runtime classes only" do
    Enum.each(@direct_connectors, fn %{catalog_path: catalog_path} ->
      catalog = File.read!(catalog_path)

      assert catalog =~ "runtime_class: :direct",
             "#{catalog_path} must publish direct runtime classes"

      refute catalog =~ "runtime_class: :session",
             "#{catalog_path} must not publish session runtime classes"

      refute catalog =~ "runtime_class: :stream",
             "#{catalog_path} must not publish stream runtime classes"
    end)
  end

  test "direct connector proofs and example support do not mention removed bridge runtimes" do
    session_kernel_module = "Jido.Integration.V2." <> "SessionKernel"
    stream_runtime_module = "Jido.Integration.V2." <> "StreamRuntime"
    session_kernel_app = ":jido_integration_v2_" <> "session_kernel"
    stream_runtime_app = ":jido_integration_v2_" <> "stream_runtime"

    Enum.each(@direct_connectors, fn %{mix_path: mix_path, test_root: test_root} ->
      package_root = Path.dirname(mix_path)

      proof_suite =
        package_root
        |> Path.join("{test,examples}/**/*.{ex,exs}")
        |> Path.wildcard()
        |> Enum.map_join("\n", &File.read!/1)

      refute proof_suite =~ session_kernel_module,
             "#{package_root} must not mention SessionKernel in proofs or example support"

      refute proof_suite =~ stream_runtime_module,
             "#{package_root} must not mention StreamRuntime in proofs or example support"

      refute proof_suite =~ session_kernel_app,
             "#{package_root} must not boot the removed session bridge app"

      refute proof_suite =~ stream_runtime_app,
             "#{package_root} must not boot the removed stream bridge app"

      refute proof_suite =~ "Jido.RuntimeControl",
             "#{test_root} must not route direct connector proofs through Jido.RuntimeControl"

      refute proof_suite =~ "RuntimeRouter.SessionStore",
             "#{package_root} must not name RuntimeRouter.SessionStore in direct proofs or example support"
    end)
  end
end
