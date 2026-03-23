defmodule Jido.Integration.Workspace.DirectConnectorBoundaryTest do
  use ExUnit.Case, async: true

  @direct_connectors [
    %{
      mix_path: Path.expand("../../connectors/github/mix.exs", __DIR__),
      catalog_path:
        Path.expand(
          "../../connectors/github/lib/jido/integration/v2/connectors/git_hub/operation_catalog.ex",
          __DIR__
        ),
      sdk_dep: "{:github_ex,"
    },
    %{
      mix_path: Path.expand("../../connectors/notion/mix.exs", __DIR__),
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
end
