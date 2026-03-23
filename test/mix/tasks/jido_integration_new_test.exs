defmodule Mix.Tasks.Jido.Integration.NewTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Jido.Integration.TestTmpDir
  alias Mix.Tasks.Jido.Integration.New, as: NewTask

  @mix_sandbox_boot """
  :code.purge(Mix.Sync.PubSub)
  :code.delete(Mix.Sync.PubSub)
  :code.load_abs(~c"/tmp/mix_override/Elixir.Mix.Sync.PubSub")
  Mix.CLI.main()
  """

  test "generates a direct connector package under connectors/<name> by default" do
    workspace_root = temp_workspace!("default")

    output = run_task(["acme_crm", "--workspace-root", workspace_root])
    package_root = Path.join(workspace_root, "connectors/acme_crm")

    assert output =~ "Connector acme_crm scaffolded successfully"

    assert File.exists?(Path.join(package_root, ".formatter.exs"))
    assert File.exists?(Path.join(package_root, ".gitignore"))
    assert File.exists?(Path.join(package_root, "README.md"))
    assert File.exists?(Path.join(package_root, "mix.exs"))
    assert File.exists?(Path.join(package_root, "test/test_helper.exs"))

    assert File.exists?(Path.join(package_root, "lib/jido/integration/v2/connectors/acme_crm.ex"))

    assert File.exists?(
             Path.join(
               package_root,
               "lib/jido/integration/v2/connectors/acme_crm/actions/perform.ex"
             )
           )

    assert File.exists?(
             Path.join(package_root, "lib/jido/integration/v2/connectors/acme_crm/conformance.ex")
           )

    assert File.exists?(
             Path.join(package_root, "test/jido/integration/v2/connectors/acme_crm_test.exs")
           )

    assert File.exists?(
             Path.join(
               package_root,
               "test/jido/integration/v2/connectors/acme_crm_conformance_test.exs"
             )
           )

    mix_content = File.read!(Path.join(package_root, "mix.exs"))

    assert mix_content =~
             "{:jido_integration_v2_contracts, path: \"../../core/contracts\", override: true}"

    assert mix_content =~ "{:zoi, \"~> 0.17\"}"

    assert mix_content =~
             "{:jido_integration_v2_direct_runtime, path: \"../../core/direct_runtime\", override: true}"

    assert mix_content =~
             "{:jido_integration_v2_conformance, path: \"../../core/conformance\", only: :test, runtime: false}"

    assert mix_content =~ "{:jido, \"~> 2.1\"}"
    assert mix_content =~ "{:jido_action, \"~> 2.1\"}"
    assert mix_content =~ ~s(elixir: "~> 1.18")
    assert mix_content =~ "dialyzer: dialyzer()"
    assert mix_content =~ "defp dialyzer do"
    assert mix_content =~ "docs: docs()"
    assert mix_content =~ "defp docs do"
    assert mix_content =~ "{:credo,"
    assert mix_content =~ "{:dialyxir,"
    assert mix_content =~ "{:ex_doc,"
    assert mix_content =~ "name:"
    assert mix_content =~ "description:"
    refute mix_content =~ "jido_integration_workspace"

    connector_content =
      File.read!(Path.join(package_root, "lib/jido/integration/v2/connectors/acme_crm.ex"))

    assert connector_content =~ "defmodule Jido.Integration.V2.Connectors.AcmeCrm do"
    assert connector_content =~ "Manifest.new!("
    assert connector_content =~ "AuthSpec.new!("
    assert connector_content =~ "CatalogSpec.new!("
    assert connector_content =~ "OperationSpec.new!("
    assert connector_content =~ "runtime_families: [:direct]"
    assert Regex.match?(~r/input_schema:\s+Zoi\.object/s, connector_content)
    assert Regex.match?(~r/output_schema:\s+Zoi\.object/s, connector_content)
    refute connector_content =~ "Capability.new!("
  end

  test "requires explicit runtime-driver selection for non-direct scaffolds" do
    session_workspace_root = temp_workspace!("session")

    assert_raise Mix.Error,
                 ~r/Session connector scaffolds require --runtime-driver/,
                 fn ->
                   run_task([
                     "assistant_cli",
                     "--workspace-root",
                     session_workspace_root,
                     "--runtime-class",
                     "session",
                     "--module",
                     "Generated.Connectors.AssistantCli"
                   ])
                 end

    refute File.exists?(Path.join(session_workspace_root, "connectors/assistant_cli"))

    stream_workspace_root = temp_workspace!("stream")

    assert_raise Mix.Error,
                 ~r/Stream connector scaffolds require --runtime-driver/,
                 fn ->
                   run_task([
                     "price_feed",
                     "--workspace-root",
                     stream_workspace_root,
                     "--runtime-class",
                     "stream"
                   ])
                 end

    refute File.exists?(Path.join(stream_workspace_root, "connectors/price_feed"))
  end

  test "generates non-direct connector packages only when an explicit Harness runtime-driver is selected" do
    workspace_root = temp_workspace!("non_direct")

    run_task([
      "assistant_cli",
      "--workspace-root",
      workspace_root,
      "--runtime-class",
      "session",
      "--runtime-driver",
      "jido_session"
    ])

    run_task([
      "price_feed",
      "--workspace-root",
      workspace_root,
      "--runtime-class",
      "stream",
      "--runtime-driver",
      "asm"
    ])

    session_package_root = Path.join(workspace_root, "connectors/assistant_cli")
    stream_package_root = Path.join(workspace_root, "connectors/price_feed")

    session_connector =
      File.read!(
        Path.join(
          session_package_root,
          "lib/jido/integration/v2/connectors/assistant_cli.ex"
        )
      )

    stream_connector =
      File.read!(
        Path.join(
          stream_package_root,
          "lib/jido/integration/v2/connectors/price_feed.ex"
        )
      )

    session_mix = File.read!(Path.join(session_package_root, "mix.exs"))
    stream_mix = File.read!(Path.join(stream_package_root, "mix.exs"))

    assert session_connector =~ ~s(driver: "jido_session")
    assert stream_connector =~ ~s(driver: "asm")
    assert session_connector =~ "mode: :connector_local"
    assert stream_connector =~ "mode: :connector_local"
    refute session_connector =~ "integration_session_bridge"
    refute stream_connector =~ "integration_stream_bridge"

    assert File.exists?(
             Path.join(
               session_package_root,
               "lib/jido/integration/v2/connectors/assistant_cli/conformance_harness_driver.ex"
             )
           )

    assert File.exists?(
             Path.join(
               stream_package_root,
               "lib/jido/integration/v2/connectors/price_feed/conformance_harness_driver.ex"
             )
           )

    refute session_mix =~ ~s(["lib", "test_support"])
    refute stream_mix =~ ~s(["lib", "test_support"])
    assert session_mix =~ "{:jido_harness,"
    assert stream_mix =~ "{:jido_harness,"
  end

  @tag timeout: 180_000
  test "generated packages compile, test, build docs, and pass baseline conformance" do
    workspace_root = temp_workspace!("validation")

    run_task(["acme_direct", "--workspace-root", workspace_root, "--runtime-class", "direct"])
    package_root = Path.join(workspace_root, "connectors/acme_direct")

    assert_mix!(workspace_root, package_root, ["deps.get"])
    assert_mix!(workspace_root, package_root, ["compile", "--warnings-as-errors"])
    assert_mix!(workspace_root, package_root, ["test"])

    assert_mix!(workspace_root, package_root, ["docs"])
  end

  @tag timeout: 180_000
  test "generated non-direct packages compile, test, build docs, and pass baseline conformance" do
    workspace_root = temp_workspace!("validation_non_direct")

    run_task([
      "acme_session",
      "--workspace-root",
      workspace_root,
      "--runtime-class",
      "session",
      "--runtime-driver",
      "jido_session"
    ])

    run_task([
      "acme_stream",
      "--workspace-root",
      workspace_root,
      "--runtime-class",
      "stream",
      "--runtime-driver",
      "asm"
    ])

    Enum.each(["acme_session", "acme_stream"], fn connector_name ->
      package_root = Path.join(workspace_root, "connectors/#{connector_name}")

      assert_mix!(workspace_root, package_root, ["deps.get"])
      assert_mix!(workspace_root, package_root, ["compile", "--warnings-as-errors"])
      assert_mix!(workspace_root, package_root, ["test"])
      assert_mix!(workspace_root, package_root, ["docs"])
    end)
  end

  defp run_task(args) do
    reload_module!(Jido.Integration.Workspace.ConnectorScaffold)
    reload_module!(Mix.Tasks.Jido.Integration.New)
    Mix.Task.reenable("jido.integration.new")

    capture_io(fn ->
      NewTask.run(args)
    end)
  end

  defp reload_module!(module) do
    :code.purge(module)
    :code.delete(module)
    Code.ensure_loaded(module)
    :ok
  end

  defp temp_workspace!(label) do
    root = TestTmpDir.create!("jido_integration_new_#{label}")
    source_hex_home = Path.expand("~/.hex")
    hex_home = Path.join(root, ".hex")

    on_exit(fn -> TestTmpDir.cleanup!(root) end)
    File.mkdir_p!(Path.join(root, "connectors"))
    File.ln_s!(Path.join(Blitz.MixWorkspace.root_dir(), "core"), Path.join(root, "core"))
    File.ln_s!(Path.join(Blitz.MixWorkspace.root_dir(), "mix.lock"), Path.join(root, "mix.lock"))
    File.mkdir_p!(hex_home)

    if File.exists?(Path.join(source_hex_home, "cache.ets")) do
      File.cp!(Path.join(source_hex_home, "cache.ets"), Path.join(hex_home, "cache.ets"))
    end

    if File.exists?(Path.join(source_hex_home, "packages")) do
      File.ln_s!(Path.join(source_hex_home, "packages"), Path.join(hex_home, "packages"))
    end

    root
  end

  defp assert_mix!(workspace_root, project_root, args) do
    project_lockfile = Path.join(project_root, "mix.lock")

    lockfile_path =
      if File.exists?(project_lockfile) do
        project_lockfile
      else
        Path.join(workspace_root, "mix.lock")
      end

    env = [
      {"MIX_DEPS_PATH", Path.join(Blitz.MixWorkspace.root_dir(), "deps")},
      {"MIX_BUILD_PATH", Path.join(workspace_root, "_build")},
      {"MIX_LOCKFILE", lockfile_path},
      {"HEX_HOME", Path.join(workspace_root, ".hex")},
      {"HEX_API_KEY", nil},
      {"MIX_OS_CONCURRENCY_LOCK", "0"}
    ]

    case System.cmd("elixir", ["-e", @mix_sandbox_boot, "--" | args],
           cd: project_root,
           env: env,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        output

      {output, exit_code} ->
        flunk("""
        mix #{Enum.join(args, " ")} failed in #{project_root} with exit code #{exit_code}

        #{output}
        """)
    end
  end
end
