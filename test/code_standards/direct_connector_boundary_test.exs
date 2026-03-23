defmodule Jido.Integration.Workspace.DirectConnectorBoundaryTest do
  use ExUnit.Case, async: true

  @direct_connectors [
    %{
      mix_path: Path.expand("../../connectors/github/mix.exs", __DIR__),
      test_root: Path.expand("../../connectors/github/test", __DIR__),
      catalog_path:
        Path.expand(
          "../../connectors/github/lib/jido/integration/v2/connectors/git_hub/operation_catalog.ex",
          __DIR__
        ),
      sdk_dep: "{:github_ex,"
    },
    %{
      mix_path: Path.expand("../../connectors/notion/mix.exs", __DIR__),
      test_root: Path.expand("../../connectors/notion/test", __DIR__),
      catalog_path:
        Path.expand(
          "../../connectors/notion/lib/jido/integration/v2/connectors/notion/operation_catalog.ex",
          __DIR__
        ),
      sdk_dep: "{:notion_sdk,"
    }
  ]

  test "direct connector packages depend on direct_runtime and provider SDKs only" do
    Enum.each(@direct_connectors, fn %{mix_path: mix_path, sdk_dep: sdk_dep} ->
      mix_exs = File.read!(mix_path)

      assert mix_exs =~ "{:jido_integration_v2_direct_runtime,",
             "#{mix_path} must depend on direct_runtime"

      assert mix_exs =~ sdk_dep, "#{mix_path} must depend on its provider SDK"
      refute mix_exs =~ ":jido_harness", "#{mix_path} must not depend on jido_harness"
      refute mix_exs =~ "agent_session_manager", "#{mix_path} must not depend on ASM directly"

      refute mix_exs =~ "cli_subprocess_core",
             "#{mix_path} must not depend on CLI subprocess core"

      refute mix_exs =~ "jido_session", "#{mix_path} must not depend on jido_session"
    end)
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
