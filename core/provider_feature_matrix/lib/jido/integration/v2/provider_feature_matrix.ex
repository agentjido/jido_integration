defmodule Jido.Integration.V2.ProviderFeatureMatrix do
  @moduledoc """
  Executable provider feature placement matrix.
  """

  alias Jido.Integration.V2.ConnectorRegistry

  @columns [
    :auth_source,
    :session,
    :streaming,
    :tool_call,
    :host_tool,
    :connector_tool,
    :file_access,
    :shell_execution,
    :permission,
    :model_selection,
    :rate_limit,
    :native_cli_login,
    :oauth,
    :token_file,
    :adc,
    :app_install,
    :telemetry,
    :receipt,
    :sandbox_attach
  ]

  @placements [
    :common,
    :provider_native,
    :sdk_native,
    :cli_native,
    :shimmed,
    :event_only,
    :unsupported,
    :forbidden
  ]

  @spec columns() :: [atom()]
  def columns, do: @columns

  @spec placements() :: [atom()]
  def placements, do: @placements

  @spec providers() :: [atom()]
  def providers, do: Enum.map(rows(), & &1.provider)

  @spec rows() :: [map()]
  def rows, do: provider_rows()

  @spec row(atom() | String.t()) :: {:ok, map()} | {:error, term()}
  def row(provider) do
    provider = normalize_provider(provider)

    case Enum.find(rows(), &(&1.provider == provider)) do
      nil -> {:error, {:unknown_provider, provider}}
      row -> {:ok, row}
    end
  end

  @spec placement(atom() | String.t(), atom() | String.t()) :: {:ok, atom()} | {:error, term()}
  def placement(provider, feature) do
    feature = normalize_feature(feature)

    with {:ok, row} <- row(provider),
         :ok <- validate_feature(feature) do
      {:ok, Map.fetch!(row.features, feature)}
    end
  end

  @spec authorize_feature(atom() | String.t(), atom() | String.t()) :: :ok | {:error, term()}
  def authorize_feature(provider, feature) do
    with {:ok, placement} <- placement(provider, feature) do
      case placement do
        :unsupported ->
          {:error,
           {:unsupported_feature, normalize_provider(provider), normalize_feature(feature)}}

        :forbidden ->
          {:error, {:forbidden_feature, normalize_provider(provider), normalize_feature(feature)}}

        _allowed ->
          :ok
      end
    end
  end

  @spec validate_registry_entry(ConnectorRegistry.entry()) :: :ok | {:error, term()}
  def validate_registry_entry(%ConnectorRegistry.Entry{} = entry) do
    with {:ok, row} <- row(provider_from_ref(entry.provider_ref)),
         :ok <- validate_connector_category(entry.connector_category) do
      validate_provider_family(entry.provider_family, row.family)
    end
  end

  @spec docs_rows() :: [map()]
  def docs_rows do
    Enum.map(rows(), fn row ->
      %{
        provider: Atom.to_string(row.provider),
        provider_ref: row.provider_ref,
        family: row.family,
        connector_category: row.connector_category,
        features: row.features
      }
    end)
  end

  defp provider_rows do
    [
      cli_provider(:codex, "provider://codex"),
      cli_provider(:claude, "provider://claude"),
      cli_provider(:gemini, "provider://gemini"),
      cli_provider(:amp, "provider://amp"),
      http_provider(:github, "provider://github", :official_connector),
      http_provider(:notion, "provider://notion", :official_connector),
      graphql_provider(:linear, "provider://linear", :official_connector),
      http_provider(:pristine, "provider://pristine", :generated_sdk_client),
      graphql_provider(:prismatic, "provider://prismatic", :generated_sdk_client),
      realtime_provider(:reqllm_next, "provider://reqllm-next"),
      inference_provider(:inference, "provider://inference"),
      inference_provider(:self_hosted_inference, "provider://self-hosted-inference"),
      http_provider(:gemini_ex, "provider://gemini-ex", :generated_sdk_client),
      inference_provider(:llama_cpp_sdk, "provider://llama-cpp-sdk")
    ]
  end

  defp cli_provider(provider, provider_ref) do
    %{
      provider: provider,
      provider_ref: provider_ref,
      family: "cli",
      connector_category: :provider_cli_adapter,
      features: %{
        auth_source: :cli_native,
        session: :provider_native,
        streaming: :provider_native,
        tool_call: :provider_native,
        host_tool: :provider_native,
        connector_tool: :shimmed,
        file_access: :provider_native,
        shell_execution: :provider_native,
        permission: :provider_native,
        model_selection: :provider_native,
        rate_limit: :event_only,
        native_cli_login: :cli_native,
        oauth: :provider_native,
        token_file: :provider_native,
        adc: :unsupported,
        app_install: :unsupported,
        telemetry: :event_only,
        receipt: :common,
        sandbox_attach: :common
      }
    }
  end

  defp http_provider(provider, provider_ref, category) do
    %{
      provider: provider,
      provider_ref: provider_ref,
      family: "http",
      connector_category: category,
      features: %{
        auth_source: :common,
        session: :sdk_native,
        streaming: :unsupported,
        tool_call: :unsupported,
        host_tool: :forbidden,
        connector_tool: :shimmed,
        file_access: :forbidden,
        shell_execution: :forbidden,
        permission: :common,
        model_selection: :unsupported,
        rate_limit: :common,
        native_cli_login: :unsupported,
        oauth: :provider_native,
        token_file: :provider_native,
        adc: :unsupported,
        app_install: :provider_native,
        telemetry: :event_only,
        receipt: :common,
        sandbox_attach: :common
      }
    }
  end

  defp graphql_provider(provider, provider_ref, category) do
    %{
      provider: provider,
      provider_ref: provider_ref,
      family: "graphql",
      connector_category: category,
      features: %{
        auth_source: :common,
        session: :sdk_native,
        streaming: :unsupported,
        tool_call: :unsupported,
        host_tool: :forbidden,
        connector_tool: :shimmed,
        file_access: :forbidden,
        shell_execution: :forbidden,
        permission: :common,
        model_selection: :unsupported,
        rate_limit: :common,
        native_cli_login: :unsupported,
        oauth: :provider_native,
        token_file: :provider_native,
        adc: :unsupported,
        app_install: :provider_native,
        telemetry: :event_only,
        receipt: :common,
        sandbox_attach: :common
      }
    }
  end

  defp realtime_provider(provider, provider_ref) do
    %{
      provider: provider,
      provider_ref: provider_ref,
      family: "realtime",
      connector_category: :generated_sdk_client,
      features: %{
        auth_source: :common,
        session: :sdk_native,
        streaming: :sdk_native,
        tool_call: :sdk_native,
        host_tool: :forbidden,
        connector_tool: :shimmed,
        file_access: :forbidden,
        shell_execution: :forbidden,
        permission: :common,
        model_selection: :provider_native,
        rate_limit: :common,
        native_cli_login: :unsupported,
        oauth: :unsupported,
        token_file: :provider_native,
        adc: :unsupported,
        app_install: :unsupported,
        telemetry: :event_only,
        receipt: :common,
        sandbox_attach: :common
      }
    }
  end

  defp inference_provider(provider, provider_ref) do
    %{
      provider: provider,
      provider_ref: provider_ref,
      family: "inference",
      connector_category: :generated_sdk_client,
      features: %{
        auth_source: :common,
        session: :sdk_native,
        streaming: :sdk_native,
        tool_call: :unsupported,
        host_tool: :forbidden,
        connector_tool: :shimmed,
        file_access: :unsupported,
        shell_execution: :forbidden,
        permission: :common,
        model_selection: :provider_native,
        rate_limit: :common,
        native_cli_login: :unsupported,
        oauth: :unsupported,
        token_file: :provider_native,
        adc: :unsupported,
        app_install: :unsupported,
        telemetry: :event_only,
        receipt: :common,
        sandbox_attach: :common
      }
    }
  end

  defp validate_feature(feature) do
    if feature in @columns, do: :ok, else: {:error, {:unknown_feature, feature}}
  end

  defp validate_connector_category(category) do
    if category in ConnectorRegistry.connector_categories() do
      :ok
    else
      {:error, {:unknown_connector_category, category}}
    end
  end

  defp validate_provider_family(left, right) do
    if left == right, do: :ok, else: {:error, {:provider_family_mismatch, left, right}}
  end

  defp provider_from_ref("provider://reqllm-next"), do: :reqllm_next
  defp provider_from_ref("provider://self-hosted-inference"), do: :self_hosted_inference
  defp provider_from_ref("provider://gemini-ex"), do: :gemini_ex
  defp provider_from_ref("provider://llama-cpp-sdk"), do: :llama_cpp_sdk

  defp provider_from_ref(provider_ref) when is_binary(provider_ref) do
    case String.split(provider_ref, "://", parts: 2) do
      ["provider", provider_name] -> normalize_provider(provider_name)
      _other -> provider_ref
    end
  end

  defp normalize_provider(provider) when is_atom(provider), do: provider

  defp normalize_provider(provider) when is_binary(provider) do
    case Enum.find(rows(), &(Atom.to_string(&1.provider) == provider)) do
      nil -> provider
      row -> row.provider
    end
  end

  defp normalize_feature(feature) when is_atom(feature), do: feature

  defp normalize_feature(feature) when is_binary(feature) do
    case Enum.find(@columns, &(Atom.to_string(&1) == feature)) do
      nil -> feature
      atom -> atom
    end
  end
end
