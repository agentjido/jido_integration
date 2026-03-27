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
      sdk_resolver_call: "DependencyResolver.github_ex()",
      sdk_local_path: "[\"../../../github_ex\"]",
      sdk_fallback:
        "[github: \"nshkrdotcom/github_ex\", branch: \"pristine/generated-runtime-and-auth-migration\"]",
      pristine_resolver_call:
        "DependencyResolver.pristine_runtime(runtime: false, override: true)",
      pristine_local_path: "[\"../../../pristine/apps/pristine_runtime\"]",
      pristine_fallback:
        "[github: \"nshkrdotcom/pristine\", branch: \"master\", subdir: \"apps/pristine_runtime\"]"
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
      sdk_resolver_call: "DependencyResolver.notion_sdk()",
      sdk_local_path: "[\"../../../notion_sdk\"]",
      sdk_fallback:
        "[github: \"nshkrdotcom/notion_sdk\", branch: \"pristine/generated-surface-migration\"]",
      pristine_resolver_call:
        "DependencyResolver.pristine_runtime(runtime: false, override: true)",
      pristine_local_path: "[\"../../../pristine/apps/pristine_runtime\"]",
      pristine_fallback:
        "[github: \"nshkrdotcom/pristine\", branch: \"master\", subdir: \"apps/pristine_runtime\"]"
    }
  ]

  test "direct connector packages depend on direct_runtime and provider SDKs only" do
    Enum.each(
      @direct_connectors,
      fn %{
           mix_path: mix_path,
           sdk_resolver_call: sdk_resolver_call,
           pristine_resolver_call: pristine_resolver_call
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

        assert mix_exs =~ pristine_resolver_call,
               "#{mix_path} must resolve pristine through DependencyResolver"

        refute mix_exs =~ ":jido_harness", "#{mix_path} must not depend on jido_harness"
        refute mix_exs =~ "agent_session_manager", "#{mix_path} must not depend on ASM directly"

        refute mix_exs =~ "cli_subprocess_core",
               "#{mix_path} must not depend on CLI subprocess core"

        refute mix_exs =~ "jido_session", "#{mix_path} must not depend on jido_session"
      end
    )
  end

  test "direct connector packages resolve provider stacks from sibling paths or hard-coded git branches" do
    Enum.each(
      @direct_connectors,
      fn %{
           mix_path: mix_path,
           resolver_path: resolver_path,
           sdk_local_path: sdk_local_path,
           sdk_fallback: sdk_fallback,
           pristine_local_path: pristine_local_path,
           pristine_fallback: pristine_fallback
         } ->
        mix_exs = File.read!(mix_path)
        resolver = File.read!(resolver_path)

        refute mix_exs =~ "deps/github_ex",
               "#{mix_path} must not vendor provider SDKs under deps/"

        refute mix_exs =~ "deps/notion_sdk",
               "#{mix_path} must not vendor provider SDKs under deps/"

        refute mix_exs =~ "deps/pristine",
               "#{mix_path} must not vendor pristine under deps/"

        assert resolver =~ sdk_local_path,
               "#{resolver_path} must check for a sibling provider SDK checkout first"

        assert resolver =~ sdk_fallback,
               "#{resolver_path} must resolve its provider SDK fallback through the hard-coded branch"

        assert resolver =~ pristine_local_path,
               "#{resolver_path} must check for a sibling pristine checkout first"

        assert resolver =~ pristine_fallback,
               "#{resolver_path} must resolve pristine fallback through the hard-coded branch and subdir"
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

      refute proof_suite =~ "Jido.Harness",
             "#{test_root} must not route direct connector proofs through Jido.Harness"

      refute proof_suite =~ "HarnessRuntime.SessionStore",
             "#{package_root} must not name HarnessRuntime.SessionStore in direct proofs or example support"
    end)
  end
end
