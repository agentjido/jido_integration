defmodule Jido.Integration.Build.DependencyResolver do
  @moduledoc false

  @repo_root Path.expand("..", __DIR__)
  @repo_fallback [
    github: "agentjido/jido_integration",
    branch: "feat/universal-contract-standards"
  ]

  def jido_integration_v2(opts \\ []),
    do: resolve_internal(:jido_integration_v2, "core/platform", opts)

  def jido_integration_v2_auth(opts \\ []),
    do: resolve_internal(:jido_integration_v2_auth, "core/auth", opts)

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

  def jido_integration_v2_runtime_asm_bridge(opts \\ []),
    do: resolve_internal(:jido_integration_v2_runtime_asm_bridge, "core/runtime_asm_bridge", opts)

  def jido_integration_v2_store_local(opts \\ []),
    do: resolve_internal(:jido_integration_v2_store_local, "core/store_local", opts)

  def jido_integration_v2_store_postgres(opts \\ []),
    do: resolve_internal(:jido_integration_v2_store_postgres, "core/store_postgres", opts)

  def jido_integration_v2_webhook_router(opts \\ []),
    do: resolve_internal(:jido_integration_v2_webhook_router, "core/webhook_router", opts)

  def jido_integration_v2_boundary_bridge(opts \\ []),
    do: resolve_internal(:jido_integration_v2_boundary_bridge, "bridges/boundary_bridge", opts)

  def jido_session(opts \\ []),
    do: resolve_internal(:jido_session, "core/session_runtime", opts)

  def jido_integration_v2_codex_cli(opts \\ []),
    do: resolve_internal(:jido_integration_v2_codex_cli, "connectors/codex_cli", opts)

  def jido_integration_v2_github(opts \\ []),
    do: resolve_internal(:jido_integration_v2_github, "connectors/github", opts)

  def jido_integration_v2_harness_runtime(opts \\ []),
    do: resolve_internal(:jido_integration_v2_harness_runtime, "core/harness_runtime", opts)

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

  def jido_integration_v2_trading_ops(opts \\ []),
    do: resolve_internal(:jido_integration_v2_trading_ops, "apps/trading_ops", opts)

  def jido_harness(opts \\ []) do
    resolve_external(
      :jido_harness,
      local_root_path("JIDO_HARNESS_PATH", "../jido_harness"),
      [github: "nshkrdotcom/jido_harness", branch: "main"],
      opts
    )
  end

  def agent_session_manager(opts \\ []) do
    resolve_external(
      :agent_session_manager,
      local_root_path("AGENT_SESSION_MANAGER_PATH", "../agent_session_manager"),
      [github: "nshkrdotcom/agent_session_manager", branch: "rebuild/foundation-v1"],
      opts
    )
  end

  def weld(opts \\ []) do
    resolve_external(
      :weld,
      local_root_path("WELD_PATH", "../weld"),
      [github: "nshkrdotcom/weld", ref: "67d6b7d58541ec8085f4d8e95d6d252b15bddff4"],
      opts
    )
  end

  def repo_root, do: @repo_root

  defp resolve_internal(app, subdir, opts) do
    fallback_opts = Keyword.put(@repo_fallback, :subdir, subdir)

    case internal_workspace_path(subdir) do
      nil -> {app, Keyword.merge(fallback_opts, opts)}
      path -> {app, Keyword.merge([path: path], opts)}
    end
  end

  defp resolve_external(app, path, fallback_opts, opts) do
    case existing_path(path) do
      nil -> {app, Keyword.merge(fallback_opts, opts)}
      resolved_path -> {app, Keyword.merge([path: resolved_path], opts)}
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
    env_var
    |> System.get_env(default_relative_path)
    |> Path.expand(@repo_root)
    |> existing_path()
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
