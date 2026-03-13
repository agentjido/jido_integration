defmodule Mix.Tasks.Jido.Integration.NewTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Jido.Integration.Workspace.Monorepo
  alias Mix.Tasks.Jido.Integration.New, as: NewTask

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

    assert mix_content =~
             "{:jido_integration_v2_direct_runtime, path: \"../../core/direct_runtime\", override: true}"

    assert mix_content =~
             "{:jido_integration_v2_conformance, path: \"../../core/conformance\", only: :test, runtime: false}"

    assert mix_content =~ "{:jido_action, path: \"../../jido_action\", override: true}"
    refute mix_content =~ "jido_integration_workspace"

    connector_content =
      File.read!(Path.join(package_root, "lib/jido/integration/v2/connectors/acme_crm.ex"))

    assert connector_content =~ "defmodule Jido.Integration.V2.Connectors.AcmeCrm do"
    assert connector_content =~ "runtime_class: :direct"
    assert connector_content =~ "kind: :operation"
    assert connector_content =~ "transport_profile: :action"
    assert connector_content =~ "handler: Perform"
    assert connector_content =~ "Capability.new!("
    assert connector_content =~ "Manifest.new!("
  end

  test "supports session and stream runtime scaffolds, including module overrides" do
    session_workspace_root = temp_workspace!("session")

    run_task([
      "assistant_cli",
      "--workspace-root",
      session_workspace_root,
      "--runtime-class",
      "session",
      "--module",
      "Generated.Connectors.AssistantCli"
    ])

    session_package_root = Path.join(session_workspace_root, "connectors/assistant_cli")

    session_mix = File.read!(Path.join(session_package_root, "mix.exs"))

    assert session_mix =~
             "{:jido_integration_v2_session_kernel, path: \"../../core/session_kernel\", override: true}"

    refute session_mix =~ "jido_integration_v2_direct_runtime"
    refute session_mix =~ "jido_integration_v2_stream_runtime"
    refute session_mix =~ "{:jido_action"

    assert File.exists?(
             Path.join(session_package_root, "lib/generated/connectors/assistant_cli.ex")
           )

    assert File.exists?(
             Path.join(session_package_root, "lib/generated/connectors/assistant_cli/provider.ex")
           )

    session_connector =
      File.read!(Path.join(session_package_root, "lib/generated/connectors/assistant_cli.ex"))

    assert session_connector =~ "defmodule Generated.Connectors.AssistantCli do"
    assert session_connector =~ "runtime_class: :session"
    assert session_connector =~ "kind: :session_operation"
    assert session_connector =~ "transport_profile: :stdio"
    assert session_connector =~ "handler: Provider"
    assert session_connector =~ "file_scope: \"/workspaces/assistant_cli\""

    stream_workspace_root = temp_workspace!("stream")

    run_task([
      "price_feed",
      "--workspace-root",
      stream_workspace_root,
      "--runtime-class",
      "stream"
    ])

    stream_package_root = Path.join(stream_workspace_root, "connectors/price_feed")
    stream_mix = File.read!(Path.join(stream_package_root, "mix.exs"))

    assert stream_mix =~
             "{:jido_integration_v2_stream_runtime, path: \"../../core/stream_runtime\", override: true}"

    refute stream_mix =~ "jido_integration_v2_direct_runtime"
    refute stream_mix =~ "jido_integration_v2_session_kernel"
    refute stream_mix =~ "{:jido_action"

    stream_connector =
      File.read!(
        Path.join(stream_package_root, "lib/jido/integration/v2/connectors/price_feed.ex")
      )

    assert stream_connector =~ "runtime_class: :stream"
    assert stream_connector =~ "kind: :stream_read"
    assert stream_connector =~ "transport_profile: :poll"
    assert stream_connector =~ "handler: Provider"

    stream_provider =
      File.read!(
        Path.join(
          stream_package_root,
          "lib/jido/integration/v2/connectors/price_feed/provider.ex"
        )
      )

    assert stream_provider =~ "@behaviour Jido.Integration.V2.StreamRuntime.Provider"
    assert stream_provider =~ "def reuse_key"
    assert stream_provider =~ "def open_stream"
    assert stream_provider =~ "def pull"
  end

  @tag timeout: 180_000
  test "generated packages compile, test, build docs, and pass baseline conformance" do
    workspace_root = temp_workspace!("validation")

    for {name, runtime_class} <- [
          {"acme_direct", "direct"},
          {"acme_session", "session"},
          {"acme_stream", "stream"}
        ] do
      run_task([name, "--workspace-root", workspace_root, "--runtime-class", runtime_class])
      package_root = Path.join(workspace_root, "connectors/#{name}")

      assert_mix!(package_root, ["deps.get"])
      assert_mix!(package_root, ["compile", "--warnings-as-errors"])
      assert_mix!(package_root, ["test"])
    end

    assert_mix!(Path.join(workspace_root, "connectors/acme_direct"), ["docs"])
  end

  defp run_task(args) do
    Mix.Task.reenable("jido.integration.new")

    capture_io(fn ->
      NewTask.run(args)
    end)
  end

  defp temp_workspace!(label) do
    root =
      Path.join(
        System.tmp_dir!(),
        "jido_integration_new_#{label}_#{System.unique_integer([:positive, :monotonic])}"
      )

    File.rm_rf!(root)
    File.mkdir_p!(Path.join(root, "connectors"))
    File.ln_s!(Path.join(Monorepo.root_dir(), "core"), Path.join(root, "core"))
    File.ln_s!(Path.expand("../jido_action", Monorepo.root_dir()), Path.join(root, "jido_action"))
    File.ln_s!(Path.expand("../jido_signal", Monorepo.root_dir()), Path.join(root, "jido_signal"))

    root
  end

  defp assert_mix!(project_root, args) do
    env = [{"MIX_BUILD_PATH", Path.join(project_root, "_build")}]

    case System.cmd("mix", args, cd: project_root, env: env, stderr_to_stdout: true) do
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
