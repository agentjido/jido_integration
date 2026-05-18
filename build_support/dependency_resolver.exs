defmodule Jido.Integration.Build.DependencyResolver do
  @moduledoc false

  unless Code.ensure_loaded?(DependencySources) do
    Code.require_file("dependency_sources.exs", __DIR__)
  end

  @repo_root Path.expand("..", __DIR__)
  @repo_fallback [
    github: "nshkrdotcom/jido_integration",
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

  def jido_integration_conformance_contracts(opts \\ []),
    do:
      resolve_internal(
        :jido_integration_conformance_contracts,
        "core/conformance_contracts",
        opts
      )

  def jido_integration_connector_admission_engine(opts \\ []),
    do:
      resolve_internal(
        :jido_integration_connector_admission_engine,
        "core/connector_admission_engine",
        opts
      )

  def jido_integration_connector_generator(opts \\ []),
    do:
      resolve_internal(
        :jido_integration_connector_generator,
        "scaffolds/connector_generator",
        opts
      )

  def jido_integration_v2_connector_registry(opts \\ []),
    do: resolve_internal(:jido_integration_v2_connector_registry, "core/connector_registry", opts)

  def jido_model_provider_registry(opts \\ []),
    do: resolve_internal(:jido_model_provider_registry, "core/model_provider_registry", opts)

  def jido_inference_operation_policy(opts \\ []),
    do:
      resolve_internal(
        :jido_inference_operation_policy,
        "core/inference_operation_policy",
        opts
      )

  def jido_integration_v2_provider_feature_matrix(opts \\ []),
    do:
      resolve_internal(
        :jido_integration_v2_provider_feature_matrix,
        "core/provider_feature_matrix",
        opts
      )

  def jido_integration_v2_tool_contracts(opts \\ []),
    do: resolve_internal(:jido_integration_v2_tool_contracts, "core/tool_contracts", opts)

  def jido_integration_v2_consumer_surfaces(opts \\ []),
    do: resolve_internal(:jido_integration_v2_consumer_surfaces, "core/consumer_surfaces", opts)

  def jido_integration_contracts(opts \\ []),
    do: resolve_internal(:jido_integration_contracts, "core/contracts", opts)

  def jido_integration_provider_classification(opts \\ []),
    do:
      resolve_internal(
        :jido_integration_provider_classification,
        "core/provider_classification",
        opts
      )

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

  def jido_integration_v2_platform_cluster_runtime(opts \\ []),
    do:
      resolve_internal(
        :jido_integration_v2_platform_cluster_runtime,
        "core/platform_cluster_runtime",
        opts
      )

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

  def jido_integration_v2_amp(opts \\ []),
    do: resolve_internal(:jido_integration_v2_amp, "connectors/amp", opts)

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

  def agent_session_manager(opts \\ []), do: external_dep(:agent_session_manager, opts)

  def amp_sdk(opts \\ []), do: external_dep(:amp_sdk, opts)

  def cli_subprocess_core(opts \\ []), do: external_dep(:cli_subprocess_core, opts)

  def jido_action(opts \\ []), do: external_dep(:jido_action, opts)

  def req_llm(opts \\ []), do: external_dep(:req_llm, opts)

  def inference(opts \\ []), do: external_dep(:inference, opts)

  def execution_plane(opts \\ []), do: external_dep(:execution_plane, opts)

  def execution_plane_jsonrpc(opts \\ []), do: external_dep(:execution_plane_jsonrpc, opts)

  def execution_plane_process(opts \\ []), do: external_dep(:execution_plane_process, opts)

  def ground_plane_persistence_policy(opts \\ []),
    do: external_dep(:ground_plane_persistence_policy, opts)

  def splode(opts \\ []), do: external_dep(:splode, opts)

  def pristine(opts \\ []), do: external_dep(:pristine, opts)

  def self_hosted_inference_core(opts \\ []), do: external_dep(:self_hosted_inference_core, opts)

  def llama_cpp_sdk(opts \\ []), do: external_dep(:llama_cpp_sdk, opts)

  def repo_root, do: @repo_root

  defp resolve_internal(app, subdir, opts) do
    fallback_opts = Keyword.put(@repo_fallback, :subdir, subdir)

    case internal_workspace_path(subdir) do
      nil -> {app, Keyword.merge(fallback_opts, opts)}
      path -> {app, Keyword.merge([path: path], opts)}
    end
  end

  defp internal_workspace_path(subdir) do
    if prefer_workspace_internal_paths?() do
      existing_path(Path.join(@repo_root, subdir))
    end
  end

  defp external_dep(app, opts) do
    app
    |> DependencySources.dep(@repo_root, opts)
    |> expand_path_dep()
  end

  defp expand_path_dep({app, opts}) when is_list(opts) do
    case Keyword.fetch(opts, :path) do
      {:ok, path} -> {app, Keyword.put(opts, :path, Path.expand(path, @repo_root))}
      :error -> {app, opts}
    end
  end

  defp expand_path_dep(dep), do: dep

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
