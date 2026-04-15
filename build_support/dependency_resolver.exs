defmodule Jido.Integration.Build.DependencyResolver do
  @moduledoc false

  @repo_root Path.expand("..", __DIR__)
  @repo_fallback [
    github: "agentjido/jido_integration",
    branch: "main"
  ]

  def jido_integration_v2(opts \\ []),
    do: resolve_internal(:jido_integration_v2, "core/platform", opts)

  def jido_integration_v2_auth(opts \\ []),
    do: resolve_internal(:jido_integration_v2_auth, "core/auth", opts)

  def jido_integration_v2_brain_ingress(opts \\ []),
    do: resolve_internal(:jido_integration_v2_brain_ingress, "core/brain_ingress", opts)

  def jido_integration_v2_conformance(opts \\ []),
    do: resolve_internal(:jido_integration_v2_conformance, "core/conformance", opts)

  def jido_integration_v2_consumer_surfaces(opts \\ []),
    do: resolve_internal(:jido_integration_v2_consumer_surfaces, "core/consumer_surfaces", opts)

  def jido_integration_v2_contracts(opts \\ []),
    do: resolve_internal(:jido_integration_v2_contracts, "core/contracts", opts)

  def jido_integration_v2_control_plane(opts \\ []),
    do: resolve_internal(:jido_integration_v2_control_plane, "core/control_plane", opts)

  def jido_integration_v2_direct_runtime(opts \\ []),
    do: resolve_internal(:jido_integration_v2_direct_runtime, "core/direct_runtime", opts)

  def jido_integration_v2_dispatch_runtime(opts \\ []),
    do: resolve_internal(:jido_integration_v2_dispatch_runtime, "core/dispatch_runtime", opts)

  def jido_integration_v2_ingress(opts \\ []),
    do: resolve_internal(:jido_integration_v2_ingress, "core/ingress", opts)

  def jido_integration_v2_policy(opts \\ []),
    do: resolve_internal(:jido_integration_v2_policy, "core/policy", opts)

  def jido_integration_v2_asm_runtime_bridge(opts \\ []),
    do: resolve_internal(:jido_integration_v2_asm_runtime_bridge, "core/asm_runtime_bridge", opts)

  def jido_runtime_control(opts \\ []),
    do: resolve_internal(:jido_runtime_control, "core/runtime_control", opts)

  def jido_integration_v2_store_local(opts \\ []),
    do: resolve_internal(:jido_integration_v2_store_local, "core/store_local", opts)

  def jido_integration_v2_store_postgres(opts \\ []),
    do: resolve_internal(:jido_integration_v2_store_postgres, "core/store_postgres", opts)

  def jido_integration_v2_webhook_router(opts \\ []),
    do: resolve_internal(:jido_integration_v2_webhook_router, "core/webhook_router", opts)

  def jido_session(opts \\ []),
    do: resolve_internal(:jido_session, "core/session_runtime", opts)

  def jido_integration_v2_codex_cli(opts \\ []),
    do: resolve_internal(:jido_integration_v2_codex_cli, "connectors/codex_cli", opts)

  def jido_integration_v2_github(opts \\ []),
    do: resolve_internal(:jido_integration_v2_github, "connectors/github", opts)

  def jido_integration_v2_linear(opts \\ []),
    do: resolve_internal(:jido_integration_v2_linear, "connectors/linear", opts)

  def jido_integration_v2_runtime_router(opts \\ []),
    do: resolve_internal(:jido_integration_v2_runtime_router, "core/runtime_router", opts)

  def jido_integration_v2_market_data(opts \\ []),
    do: resolve_internal(:jido_integration_v2_market_data, "connectors/market_data", opts)

  def jido_integration_v2_notion(opts \\ []),
    do: resolve_internal(:jido_integration_v2_notion, "connectors/notion", opts)

  def jido_integration_v2_devops_incident_response(opts \\ []),
    do:
      resolve_internal(
        :jido_integration_v2_devops_incident_response,
        "apps/devops_incident_response",
        opts
      )

  def jido_integration_v2_inference_ops(opts \\ []),
    do: resolve_internal(:jido_integration_v2_inference_ops, "apps/inference_ops", opts)

  def agent_session_manager(opts \\ []) do
    case local_root_path("AGENT_SESSION_MANAGER_PATH", "../agent_session_manager") do
      nil -> {:agent_session_manager, "~> 0.9.1", opts}
      path -> {:agent_session_manager, Keyword.merge([path: path], opts)}
    end
  end

  def cli_subprocess_core(opts \\ []) do
    case local_root_path("CLI_SUBPROCESS_CORE_PATH", "../cli_subprocess_core") do
      nil -> {:cli_subprocess_core, "~> 0.1.0", opts}
      path -> {:cli_subprocess_core, Keyword.merge([path: path, override: true], opts)}
    end
  end

  def jido_action(opts \\ []) do
    case local_root_path("JIDO_ACTION_PATH", "../jido_action") do
      nil -> {:jido_action, "~> 2.2", opts}
      path -> {:jido_action, Keyword.merge([path: path], opts)}
    end
  end

  def req_llm(opts \\ []) do
    {:req_llm, "~> 1.9", opts}
  end

  def splode(opts \\ []) do
    {:splode, "~> 0.3.0", opts}
  end

  def pristine(opts \\ []) do
    {:pristine, "~> 0.2.1", opts}
  end

  def self_hosted_inference_core(opts \\ []) do
    case local_root_path("SELF_HOSTED_INFERENCE_CORE_PATH", "../self_hosted_inference_core") do
      nil -> {:self_hosted_inference_core, "~> 0.1.0", opts}
      path -> {:self_hosted_inference_core, Keyword.merge([path: path, override: true], opts)}
    end
  end

  def llama_cpp_sdk(opts \\ []) do
    case local_root_path("LLAMA_CPP_SDK_PATH", "../llama_cpp_sdk") do
      nil -> {:llama_cpp_sdk, "~> 0.1.0", opts}
      path -> {:llama_cpp_sdk, Keyword.merge([path: path, override: true], opts)}
    end
  end

  def erlexec(opts \\ []) do
    {:erlexec, "~> 2.2", opts}
  end

  def repo_root, do: @repo_root

  defp resolve_internal(app, subdir, opts) do
    fallback_opts = Keyword.put(@repo_fallback, :subdir, subdir)

    case internal_workspace_path(subdir) do
      nil -> {app, Keyword.merge(fallback_opts, opts)}
      path -> {app, Keyword.merge([path: path], opts)}
    end
  end

  defp internal_workspace_path(subdir) do
    cond do
      root = env_root_path("JIDO_INTEGRATION_PATH") ->
        existing_path(Path.join(root, subdir))

      prefer_workspace_internal_paths?() ->
        existing_path(Path.join(@repo_root, subdir))

      true ->
        nil
    end
  end

  defp local_root_path(env_var, default_relative_path) do
    case System.get_env(env_var) do
      nil ->
        case default_relative_path do
          nil ->
            nil

          path ->
            path
            |> Path.expand(@repo_root)
            |> existing_path()
        end

      value when value in ["", "0", "false", "disabled"] ->
        nil

      value ->
        value
        |> Path.expand(@repo_root)
        |> existing_path()
    end
  end

  defp env_root_path(env_var) do
    case System.get_env(env_var) do
      nil -> nil
      value -> value |> Path.expand(@repo_root) |> existing_path()
    end
  end

  defp prefer_workspace_internal_paths? do
    not Enum.member?(Path.split(@repo_root), "deps")
  end

  defp existing_path(nil), do: nil

  defp existing_path(path) do
    expanded_path = Path.expand(path)

    if File.dir?(expanded_path) do
      expanded_path
    end
  end
end
