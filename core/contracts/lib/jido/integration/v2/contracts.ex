defmodule Jido.Integration.V2.Contracts do
  @moduledoc """
  Shared public types and validation helpers for the greenfield integration platform.
  """

  @schema_version "1.0"
  @inference_contract_version "inference.v1"

  @type runtime_class :: :direct | :session | :stream
  @type runtime_kind :: :client | :task | :service
  @type management_mode :: :provider_managed | :jido_managed | :externally_managed
  @type inference_operation :: :generate_text | :stream_text
  @type inference_target_class :: :cloud_provider | :cli_endpoint | :self_hosted_endpoint
  @type inference_protocol :: :openai_chat_completions
  @type authority_source :: :jido_integration | :jido_os | :external
  @type inference_checkpoint_policy :: :summary | :artifact | :disabled
  @type inference_status :: :ok | :error | :cancelled
  @type sandbox_level :: :strict | :standard | :none
  @type approvals :: :none | :manual | :auto
  @type egress_policy :: :blocked | :restricted | :open
  @type run_status :: :accepted | :running | :completed | :failed | :denied | :shed
  @type attempt_status :: :accepted | :running | :completed | :failed
  @type trigger_source :: :webhook | :poll
  @type trigger_status :: :accepted | :rejected
  @type event_stream :: :assistant | :stdout | :stderr | :system | :control
  @type event_level :: :debug | :info | :warn | :error
  @type target_mode :: :local | :ssh | :beam | :bus | :http
  @type checksum :: String.t()
  @type artifact_type ::
          :event_log | :stdout | :stderr | :diff | :tarball | :tool_output | :log | :custom
  @type transport_mode :: :inline | :chunked | :object_store
  @type access_control :: :run_scoped | :tenant_scoped | :public_read
  @type target_health :: :healthy | :degraded | :unavailable
  @type zoi_schema :: term()
  @type payload_ref :: %{
          store: String.t(),
          key: String.t(),
          ttl_s: pos_integer(),
          access_control: access_control(),
          checksum: checksum(),
          size_bytes: non_neg_integer()
        }
  @type trace_context :: %{
          trace_id: String.t() | nil,
          span_id: String.t() | nil,
          correlation_id: String.t() | nil,
          causation_id: String.t() | nil
        }

  @checksum_regex ~r/\Asha256:[0-9a-f]{64}\z/

  @spec schema_version() :: String.t()
  def schema_version, do: @schema_version

  @spec inference_contract_version() :: String.t()
  def inference_contract_version, do: @inference_contract_version

  @spec now() :: DateTime.t()
  def now do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end

  @spec dump_json_safe!(term()) :: term()
  def dump_json_safe!(value)

  def dump_json_safe!(%DateTime{} = value), do: DateTime.to_iso8601(value)
  def dump_json_safe!(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  def dump_json_safe!(%Date{} = value), do: Date.to_iso8601(value)
  def dump_json_safe!(%Time{} = value), do: Time.to_iso8601(value)

  def dump_json_safe!(%_{} = value) do
    value
    |> Map.from_struct()
    |> dump_json_safe!()
  end

  def dump_json_safe!(value) when is_map(value) do
    Enum.into(value, %{}, fn {key, nested_value} ->
      {dump_json_key!(key), dump_json_safe!(nested_value)}
    end)
  end

  def dump_json_safe!(value) when is_list(value) do
    if value != [] and Keyword.keyword?(value) do
      Enum.into(value, %{}, fn {key, nested_value} ->
        {dump_json_key!(key), dump_json_safe!(nested_value)}
      end)
    else
      Enum.map(value, &dump_json_safe!/1)
    end
  end

  def dump_json_safe!(value) when is_atom(value) do
    if value in [nil, true, false], do: value, else: Atom.to_string(value)
  end

  def dump_json_safe!(value)
      when is_binary(value) or is_integer(value) or is_float(value) or is_boolean(value) or
             is_nil(value),
      do: value

  def dump_json_safe!(value) do
    raise ArgumentError, "value is not JSON-safe: #{inspect(value)}"
  end

  @spec next_id(String.t()) :: String.t()
  def next_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end

  @spec reference_uri(String.t(), atom(), String.t()) :: String.t()
  def reference_uri(namespace, kind, id)
      when is_binary(namespace) and is_atom(kind) and is_binary(id) do
    namespace = validate_non_empty_string!(namespace, "reference namespace")
    id = validate_non_empty_string!(id, "reference id")

    "jido://v2/#{namespace}/#{kind}/#{URI.encode_www_form(id)}"
  end

  @spec review_packet_ref(String.t(), String.t() | nil) :: String.t()
  def review_packet_ref(run_id, attempt_id \\ nil) when is_binary(run_id) do
    run_id = validate_non_empty_string!(run_id, "review_packet.run_id")
    base = "jido://v2/review_packet/run/#{URI.encode_www_form(run_id)}"

    case attempt_id do
      nil ->
        base

      attempt_id ->
        attempt_id = validate_non_empty_string!(attempt_id, "review_packet.attempt_id")
        base <> "?attempt_id=" <> URI.encode_www_form(attempt_id)
    end
  end

  @spec attempt_id(String.t(), pos_integer()) :: String.t()
  def attempt_id(run_id, attempt)
      when is_binary(run_id) and is_integer(attempt) and attempt > 0 do
    "#{run_id}:#{attempt}"
  end

  @spec attempt_from_id!(String.t(), String.t()) :: pos_integer()
  def attempt_from_id!(run_id, attempt_id)
      when is_binary(run_id) and is_binary(attempt_id) do
    prefix = run_id <> ":"

    with true <- String.starts_with?(attempt_id, prefix),
         suffix <- String.replace_prefix(attempt_id, prefix, ""),
         {attempt, ""} when attempt > 0 <- Integer.parse(suffix) do
      attempt
    else
      _ ->
        raise ArgumentError,
              "attempt_id must be derived from run_id and attempt: #{inspect({run_id, attempt_id})}"
    end
  end

  @spec normalize_trace(map()) :: trace_context()
  def normalize_trace(trace) when is_map(trace) do
    %{
      trace_id: get(trace, :trace_id),
      span_id: get(trace, :span_id),
      correlation_id: get(trace, :correlation_id),
      causation_id: get(trace, :causation_id)
    }
  end

  @spec get(map(), atom(), term()) :: term()
  def get(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  @spec fetch!(map(), atom()) :: term()
  def fetch!(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} ->
        value

      :error ->
        case Map.fetch(map, Atom.to_string(key)) do
          {:ok, value} -> value
          :error -> raise KeyError, key: key, term: map
        end
    end
  end

  @spec validate_non_empty_string!(term(), String.t()) :: String.t()
  def validate_non_empty_string!(value, field_name)
      when is_binary(value) do
    if byte_size(String.trim(value)) > 0 do
      value
    else
      raise ArgumentError, "#{field_name} must be a non-empty string, got: #{inspect(value)}"
    end
  end

  def validate_non_empty_string!(value, field_name) do
    raise ArgumentError, "#{field_name} must be a non-empty string, got: #{inspect(value)}"
  end

  defp dump_json_key!(key) when is_binary(key), do: key
  defp dump_json_key!(key) when is_atom(key), do: Atom.to_string(key)
  defp dump_json_key!(key) when is_integer(key), do: Integer.to_string(key)
  defp dump_json_key!(key) when is_float(key), do: Float.to_string(key)
  defp dump_json_key!(key) when is_boolean(key), do: to_string(key)

  defp dump_json_key!(_key) do
    raise ArgumentError, "JSON object keys must be strings, numbers, booleans, or atoms"
  end

  @spec validate_checksum!(checksum()) :: checksum()
  def validate_checksum!(checksum) when is_binary(checksum) do
    if checksum =~ @checksum_regex do
      checksum
    else
      raise ArgumentError,
            "checksum must use sha256:<hex_digest> format, got: #{inspect(checksum)}"
    end
  end

  def validate_checksum!(checksum) do
    raise ArgumentError, "checksum must be a string, got: #{inspect(checksum)}"
  end

  @spec normalize_payload_ref!(map()) :: payload_ref()
  def normalize_payload_ref!(payload_ref) when is_map(payload_ref) do
    store = validate_non_empty_string!(fetch!(payload_ref, :store), "payload_ref.store")
    key = validate_non_empty_string!(fetch!(payload_ref, :key), "payload_ref.key")
    ttl_s = fetch!(payload_ref, :ttl_s)
    access_control = validate_access_control!(fetch!(payload_ref, :access_control))
    checksum = validate_checksum!(fetch!(payload_ref, :checksum))

    size_bytes =
      validate_non_negative_integer!(fetch!(payload_ref, :size_bytes), "payload_ref.size_bytes")

    if local_payload_ref?(store, key) do
      raise ArgumentError, "payload_ref must not point at a local file path"
    end

    if not (is_integer(ttl_s) and ttl_s > 0) do
      raise ArgumentError, "payload_ref.ttl_s must be a positive integer"
    end

    %{
      store: store,
      key: key,
      ttl_s: ttl_s,
      access_control: access_control,
      checksum: checksum,
      size_bytes: size_bytes
    }
  end

  def normalize_payload_ref!(payload_ref) do
    raise ArgumentError, "payload_ref must be a map, got: #{inspect(payload_ref)}"
  end

  @spec validate_semver!(String.t(), String.t()) :: String.t()
  def validate_semver!(version, field_name \\ "version")

  def validate_semver!(version, field_name) when is_binary(version) do
    case Version.parse(version) do
      {:ok, _version} ->
        version

      :error ->
        raise ArgumentError, "#{field_name} must be a semantic version, got: #{inspect(version)}"
    end
  end

  def validate_semver!(version, field_name) do
    raise ArgumentError,
          "#{field_name} must be a semantic version string, got: #{inspect(version)}"
  end

  @spec validate_version_requirement!(String.t() | nil) :: String.t() | nil
  def validate_version_requirement!(nil), do: nil

  def validate_version_requirement!(requirement) when is_binary(requirement) do
    case Version.parse_requirement(requirement) do
      {:ok, _parsed} -> requirement
      :error -> raise ArgumentError, "version requirement is invalid: #{inspect(requirement)}"
    end
  end

  def validate_version_requirement!(requirement) do
    raise ArgumentError, "version requirement must be a string, got: #{inspect(requirement)}"
  end

  @spec normalize_string_list!(list(), String.t()) :: [String.t()]
  def normalize_string_list!(values, field_name) when is_list(values) do
    Enum.map(values, fn value ->
      value
      |> to_string()
      |> validate_non_empty_string!(field_name)
    end)
  end

  def normalize_string_list!(values, field_name) do
    raise ArgumentError, "#{field_name} must be a list, got: #{inspect(values)}"
  end

  @spec normalize_version_list!(list(), String.t()) :: [String.t()]
  def normalize_version_list!(versions, field_name) when is_list(versions) do
    Enum.map(versions, &validate_semver!(&1, field_name))
  end

  def normalize_version_list!(versions, field_name) do
    raise ArgumentError, "#{field_name} must be a list, got: #{inspect(versions)}"
  end

  @spec validate_runtime_class!(runtime_class()) :: runtime_class()
  def validate_runtime_class!(runtime_class) when runtime_class in [:direct, :session, :stream],
    do: runtime_class

  def validate_runtime_class!(runtime_class) when is_binary(runtime_class) do
    validate_enum_string!(runtime_class, [:direct, :session, :stream], "runtime_class")
  end

  def validate_runtime_class!(runtime_class) do
    raise ArgumentError, "invalid runtime_class: #{inspect(runtime_class)}"
  end

  @spec validate_runtime_kind!(runtime_kind()) :: runtime_kind()
  def validate_runtime_kind!(runtime_kind) when runtime_kind in [:client, :task, :service],
    do: runtime_kind

  def validate_runtime_kind!(runtime_kind) when is_binary(runtime_kind) do
    validate_enum_string!(runtime_kind, [:client, :task, :service], "runtime_kind")
  end

  def validate_runtime_kind!(runtime_kind) do
    raise ArgumentError, "invalid runtime_kind: #{inspect(runtime_kind)}"
  end

  @spec validate_management_mode!(management_mode()) :: management_mode()
  def validate_management_mode!(management_mode)
      when management_mode in [:provider_managed, :jido_managed, :externally_managed],
      do: management_mode

  def validate_management_mode!(management_mode) when is_binary(management_mode) do
    validate_enum_string!(
      management_mode,
      [:provider_managed, :jido_managed, :externally_managed],
      "management_mode"
    )
  end

  def validate_management_mode!(management_mode) do
    raise ArgumentError, "invalid management_mode: #{inspect(management_mode)}"
  end

  @spec validate_inference_operation!(inference_operation()) :: inference_operation()
  def validate_inference_operation!(operation) when operation in [:generate_text, :stream_text],
    do: operation

  def validate_inference_operation!(operation) when is_binary(operation) do
    validate_enum_string!(operation, [:generate_text, :stream_text], "inference operation")
  end

  def validate_inference_operation!(operation) do
    raise ArgumentError, "invalid inference operation: #{inspect(operation)}"
  end

  @spec validate_inference_target_class!(inference_target_class()) :: inference_target_class()
  def validate_inference_target_class!(target_class)
      when target_class in [:cloud_provider, :cli_endpoint, :self_hosted_endpoint],
      do: target_class

  def validate_inference_target_class!(target_class) when is_binary(target_class) do
    validate_enum_string!(
      target_class,
      [:cloud_provider, :cli_endpoint, :self_hosted_endpoint],
      "inference target_class"
    )
  end

  def validate_inference_target_class!(target_class) do
    raise ArgumentError, "invalid inference target_class: #{inspect(target_class)}"
  end

  @spec validate_inference_protocol!(inference_protocol()) :: inference_protocol()
  def validate_inference_protocol!(protocol) when protocol in [:openai_chat_completions],
    do: protocol

  def validate_inference_protocol!(protocol) when is_binary(protocol) do
    validate_enum_string!(protocol, [:openai_chat_completions], "inference protocol")
  end

  def validate_inference_protocol!(protocol) do
    raise ArgumentError, "invalid inference protocol: #{inspect(protocol)}"
  end

  @spec validate_authority_source!(authority_source()) :: authority_source()
  def validate_authority_source!(authority_source)
      when authority_source in [:jido_integration, :jido_os, :external],
      do: authority_source

  def validate_authority_source!(authority_source) when is_binary(authority_source) do
    validate_enum_string!(
      authority_source,
      [:jido_integration, :jido_os, :external],
      "authority_source"
    )
  end

  def validate_authority_source!(authority_source) do
    raise ArgumentError, "invalid authority_source: #{inspect(authority_source)}"
  end

  @spec validate_inference_checkpoint_policy!(inference_checkpoint_policy()) ::
          inference_checkpoint_policy()
  def validate_inference_checkpoint_policy!(policy)
      when policy in [:summary, :artifact, :disabled],
      do: policy

  def validate_inference_checkpoint_policy!(policy) when is_binary(policy) do
    validate_enum_string!(
      policy,
      [:summary, :artifact, :disabled],
      "inference checkpoint policy"
    )
  end

  def validate_inference_checkpoint_policy!(policy) do
    raise ArgumentError, "invalid inference checkpoint policy: #{inspect(policy)}"
  end

  @spec validate_inference_status!(inference_status()) :: inference_status()
  def validate_inference_status!(status) when status in [:ok, :error, :cancelled], do: status

  def validate_inference_status!(status) when is_binary(status) do
    validate_enum_string!(status, [:ok, :error, :cancelled], "inference status")
  end

  def validate_inference_status!(status) do
    raise ArgumentError, "invalid inference status: #{inspect(status)}"
  end

  @spec validate_inference_contract_version!(String.t()) :: String.t()
  def validate_inference_contract_version!(version) when version == @inference_contract_version,
    do: version

  def validate_inference_contract_version!(version) when is_binary(version) do
    raise ArgumentError,
          "invalid inference contract_version: #{inspect(version)}; expected #{@inference_contract_version}"
  end

  def validate_inference_contract_version!(version) do
    raise ArgumentError,
          "inference contract_version must be a string, got: #{inspect(version)}"
  end

  @spec normalize_atomish_list!(list(), String.t()) :: [atom()]
  def normalize_atomish_list!(values, field_name) when is_list(values) do
    Enum.map(values, &normalize_atomish!(&1, field_name))
  end

  def normalize_atomish_list!(values, field_name) do
    raise ArgumentError, "#{field_name} must be a list, got: #{inspect(values)}"
  end

  @spec validate_sandbox_level!(sandbox_level()) :: sandbox_level()
  def validate_sandbox_level!(sandbox_level) when sandbox_level in [:strict, :standard, :none],
    do: sandbox_level

  def validate_sandbox_level!(sandbox_level) when is_binary(sandbox_level) do
    validate_enum_string!(sandbox_level, [:strict, :standard, :none], "sandbox level")
  end

  def validate_sandbox_level!(sandbox_level) do
    raise ArgumentError, "invalid sandbox level: #{inspect(sandbox_level)}"
  end

  @spec validate_approvals!(approvals()) :: approvals()
  def validate_approvals!(approvals) when approvals in [:none, :manual, :auto], do: approvals

  def validate_approvals!(approvals) when is_binary(approvals) do
    validate_enum_string!(approvals, [:none, :manual, :auto], "approvals policy")
  end

  def validate_approvals!(approvals) do
    raise ArgumentError, "invalid approvals policy: #{inspect(approvals)}"
  end

  @spec validate_egress_policy!(egress_policy()) :: egress_policy()
  def validate_egress_policy!(egress_policy) when egress_policy in [:blocked, :restricted, :open],
    do: egress_policy

  def validate_egress_policy!(egress_policy) when is_binary(egress_policy) do
    validate_enum_string!(egress_policy, [:blocked, :restricted, :open], "egress policy")
  end

  def validate_egress_policy!(egress_policy) do
    raise ArgumentError, "invalid egress policy: #{inspect(egress_policy)}"
  end

  @spec validate_run_status!(run_status()) :: run_status()
  def validate_run_status!(status)
      when status in [:accepted, :running, :completed, :failed, :denied, :shed],
      do: status

  def validate_run_status!(status) do
    raise ArgumentError, "invalid run status: #{inspect(status)}"
  end

  @spec validate_attempt_status!(attempt_status()) :: attempt_status()
  def validate_attempt_status!(status) when status in [:accepted, :running, :completed, :failed],
    do: status

  def validate_attempt_status!(status) do
    raise ArgumentError, "invalid attempt status: #{inspect(status)}"
  end

  @spec validate_trigger_source!(trigger_source()) :: trigger_source()
  def validate_trigger_source!(source) when source in [:webhook, :poll], do: source

  def validate_trigger_source!(source) when is_binary(source) do
    validate_enum_string!(source, [:webhook, :poll], "trigger source")
  end

  def validate_trigger_source!(source) do
    raise ArgumentError, "invalid trigger source: #{inspect(source)}"
  end

  @spec validate_trigger_status!(trigger_status()) :: trigger_status()
  def validate_trigger_status!(status) when status in [:accepted, :rejected], do: status

  def validate_trigger_status!(status) when is_binary(status) do
    validate_enum_string!(status, [:accepted, :rejected], "trigger status")
  end

  def validate_trigger_status!(status) do
    raise ArgumentError, "invalid trigger status: #{inspect(status)}"
  end

  @spec validate_attempt!(pos_integer()) :: pos_integer()
  def validate_attempt!(attempt) when is_integer(attempt) and attempt > 0, do: attempt

  def validate_attempt!(attempt) do
    raise ArgumentError, "invalid attempt number: #{inspect(attempt)}"
  end

  @spec validate_aggregator_epoch!(pos_integer()) :: pos_integer()
  def validate_aggregator_epoch!(epoch) when is_integer(epoch) and epoch > 0, do: epoch

  def validate_aggregator_epoch!(epoch) do
    raise ArgumentError, "invalid aggregator epoch: #{inspect(epoch)}"
  end

  @spec validate_event_seq!(non_neg_integer()) :: non_neg_integer()
  def validate_event_seq!(seq) when is_integer(seq) and seq >= 0, do: seq

  def validate_event_seq!(seq) do
    raise ArgumentError, "invalid event seq: #{inspect(seq)}"
  end

  @spec validate_event_stream!(event_stream()) :: event_stream()
  def validate_event_stream!(stream)
      when stream in [:assistant, :stdout, :stderr, :system, :control],
      do: stream

  def validate_event_stream!(stream) do
    raise ArgumentError, "invalid event stream: #{inspect(stream)}"
  end

  @spec validate_event_level!(event_level()) :: event_level()
  def validate_event_level!(level) when level in [:debug, :info, :warn, :error], do: level

  def validate_event_level!(level) do
    raise ArgumentError, "invalid event level: #{inspect(level)}"
  end

  @spec validate_artifact_type!(artifact_type()) :: artifact_type()
  def validate_artifact_type!(artifact_type)
      when artifact_type in [
             :event_log,
             :stdout,
             :stderr,
             :diff,
             :tarball,
             :tool_output,
             :log,
             :custom
           ],
      do: artifact_type

  def validate_artifact_type!(artifact_type) when is_binary(artifact_type) do
    validate_enum_string!(
      artifact_type,
      [:event_log, :stdout, :stderr, :diff, :tarball, :tool_output, :log, :custom],
      "artifact_type"
    )
  end

  def validate_artifact_type!(artifact_type) do
    raise ArgumentError, "invalid artifact_type: #{inspect(artifact_type)}"
  end

  @spec validate_transport_mode!(transport_mode()) :: transport_mode()
  def validate_transport_mode!(transport_mode)
      when transport_mode in [:inline, :chunked, :object_store],
      do: transport_mode

  def validate_transport_mode!(transport_mode) when is_binary(transport_mode) do
    validate_enum_string!(transport_mode, [:inline, :chunked, :object_store], "transport_mode")
  end

  def validate_transport_mode!(transport_mode) do
    raise ArgumentError, "invalid transport_mode: #{inspect(transport_mode)}"
  end

  @spec validate_access_control!(access_control()) :: access_control()
  def validate_access_control!(access_control)
      when access_control in [:run_scoped, :tenant_scoped, :public_read],
      do: access_control

  def validate_access_control!(access_control) when is_binary(access_control) do
    validate_enum_string!(
      access_control,
      [:run_scoped, :tenant_scoped, :public_read],
      "payload_ref.access_control"
    )
  end

  def validate_access_control!(access_control) do
    raise ArgumentError, "invalid payload_ref.access_control: #{inspect(access_control)}"
  end

  @spec validate_target_health!(target_health()) :: target_health()
  def validate_target_health!(health) when health in [:healthy, :degraded, :unavailable],
    do: health

  def validate_target_health!(health) when is_binary(health) do
    validate_enum_string!(health, [:healthy, :degraded, :unavailable], "target health")
  end

  def validate_target_health!(health) do
    raise ArgumentError, "invalid target health: #{inspect(health)}"
  end

  @spec validate_target_mode!(target_mode()) :: target_mode()
  def validate_target_mode!(mode) when mode in [:local, :ssh, :beam, :bus, :http], do: mode

  def validate_target_mode!(mode) when is_binary(mode) do
    validate_enum_string!(mode, [:local, :ssh, :beam, :bus, :http], "target mode")
  end

  def validate_target_mode!(mode) do
    raise ArgumentError, "invalid target mode: #{inspect(mode)}"
  end

  @spec validate_module!(term(), String.t()) :: module()
  def validate_module!(value, _field_name) when is_atom(value) do
    value
  end

  def validate_module!(value, field_name) do
    raise ArgumentError, "#{field_name} must be a module, got: #{inspect(value)}"
  end

  @spec validate_map!(term(), String.t()) :: map()
  def validate_map!(value, _field_name) when is_map(value), do: value

  def validate_map!(value, field_name) do
    raise ArgumentError, "#{field_name} must be a map, got: #{inspect(value)}"
  end

  @spec validate_positive_integer!(term(), String.t()) :: pos_integer()
  def validate_positive_integer!(value, _field_name) when is_integer(value) and value > 0,
    do: value

  def validate_positive_integer!(value, field_name) do
    raise ArgumentError, "#{field_name} must be a positive integer, got: #{inspect(value)}"
  end

  @spec map_schema(String.t()) :: zoi_schema()
  def map_schema(field_name) when is_binary(field_name) do
    Zoi.any() |> Zoi.refine({__MODULE__, :validate_map_refine, [field_name]})
  end

  @spec positive_integer_schema(String.t()) :: zoi_schema()
  def positive_integer_schema(field_name) when is_binary(field_name) do
    Zoi.any() |> Zoi.refine({__MODULE__, :validate_positive_integer_refine, [field_name]})
  end

  @spec any_map_schema() :: zoi_schema()
  def any_map_schema do
    Zoi.map(Zoi.any(), Zoi.any(), [])
  end

  @spec non_empty_string_schema(String.t()) :: zoi_schema()
  def non_empty_string_schema(field_name) when is_binary(field_name) do
    Zoi.string() |> Zoi.refine({__MODULE__, :validate_non_empty_string_refine, [field_name]})
  end

  @spec string_list_schema(String.t()) :: zoi_schema()
  def string_list_schema(field_name) when is_binary(field_name) do
    Zoi.list(non_empty_string_schema(field_name))
  end

  @spec module_schema(String.t()) :: zoi_schema()
  def module_schema(field_name) when is_binary(field_name) do
    Zoi.atom() |> Zoi.refine({__MODULE__, :validate_module_refine, [field_name]})
  end

  @spec struct_schema(module(), String.t()) :: zoi_schema()
  def struct_schema(module, field_name) when is_atom(module) and is_binary(field_name) do
    Zoi.any() |> Zoi.refine({__MODULE__, :validate_struct_refine, [module, field_name]})
  end

  @spec datetime_schema(String.t()) :: zoi_schema()
  def datetime_schema(field_name) when is_binary(field_name) do
    Zoi.any() |> Zoi.refine({__MODULE__, :validate_datetime_refine, [field_name]})
  end

  @spec keyword_list_schema(String.t()) :: zoi_schema()
  def keyword_list_schema(field_name) when is_binary(field_name) do
    Zoi.any() |> Zoi.refine({__MODULE__, :validate_keyword_list_refine, [field_name]})
  end

  @spec payload_ref_schema(String.t()) :: zoi_schema()
  def payload_ref_schema(field_name) when is_binary(field_name) do
    Zoi.any() |> Zoi.refine({__MODULE__, :validate_payload_ref_refine, [field_name]})
  end

  @spec atomish_schema(String.t()) :: zoi_schema()
  def atomish_schema(field_name) when is_binary(field_name) do
    Zoi.union([Zoi.atom(), Zoi.string()])
    |> Zoi.transform({__MODULE__, :normalize_atomish_transform, [field_name]})
  end

  @spec enumish_schema([atom()], String.t()) :: zoi_schema()
  def enumish_schema(values, field_name) when is_list(values) and is_binary(field_name) do
    Zoi.union([Zoi.enum(values), Zoi.string()])
    |> Zoi.transform({__MODULE__, :normalize_enumish_transform, [values, field_name]})
  end

  @spec zoi_schema_schema(String.t()) :: zoi_schema()
  def zoi_schema_schema(field_name) when is_binary(field_name) do
    Zoi.any() |> Zoi.refine({__MODULE__, :validate_zoi_schema_refine, [field_name]})
  end

  @spec placeholder_zoi_schema?(term()) :: boolean()
  def placeholder_zoi_schema?(%Zoi.Types.Any{}), do: true

  def placeholder_zoi_schema?(%Zoi.Types.Map{fields: [], unrecognized_keys: mode})
      when mode != :error,
      do: true

  def placeholder_zoi_schema?(%Zoi.Types.Map{
        key_type: %Zoi.Types.Any{},
        value_type: %Zoi.Types.Any{}
      }),
      do: true

  def placeholder_zoi_schema?(_value), do: false

  @doc """
  Builds a `Zoi.object/2` schema from an ordered keyword list.

  `Zoi` preserves object field order. Using maps here makes the resulting schema
  order depend on map enumeration, which can diverge between compile-time
  generated modules and runtime manifest construction.
  """
  @spec ordered_object!(keyword(), keyword()) :: zoi_schema()
  def ordered_object!(fields, opts \\ [])

  def ordered_object!(fields, opts) when is_list(fields) do
    if Keyword.keyword?(fields) do
      opts =
        Zoi.Types.Map.opts()
        |> Zoi.parse!(opts)

      Zoi.Types.Map.new(fields, opts)
    else
      raise ArgumentError,
            "ordered object schema fields must be a keyword list, got: #{inspect(fields)}"
    end
  end

  def ordered_object!(fields, _opts) do
    raise ArgumentError,
          "ordered object schema fields must be a keyword list, got: #{inspect(fields)}"
  end

  @doc """
  Builds a strict `Zoi.object/2` schema from an ordered keyword list.
  """
  @spec strict_object!(keyword(), keyword()) :: zoi_schema()
  def strict_object!(fields, opts \\ []) do
    ordered_object!(fields, Keyword.merge([coerce: true, unrecognized_keys: :error], opts))
  end

  @spec validate_zoi_schema!(term(), String.t()) :: zoi_schema()
  def validate_zoi_schema!(value, field_name) do
    if zoi_schema?(value) do
      value
    else
      raise ArgumentError, "#{field_name} must be a Zoi schema, got: #{inspect(value)}"
    end
  end

  @spec zoi_schema?(term()) :: boolean()
  def zoi_schema?(value) do
    is_struct(value) and Zoi.Type.impl_for(value) != nil
  rescue
    _ -> false
  end

  @spec normalize_atomish!(term(), String.t()) :: atom()
  def normalize_atomish!(value, _field_name) when is_atom(value), do: value

  def normalize_atomish!(value, field_name) when is_binary(value) do
    value
    |> validate_non_empty_string!(field_name)
    |> String.to_atom()
  end

  def normalize_atomish!(value, field_name) do
    raise ArgumentError, "#{field_name} must be an atom or string, got: #{inspect(value)}"
  end

  defp validate_enum_string!(value, valid_values, field_name) when is_binary(value) do
    case Enum.find(valid_values, &(Atom.to_string(&1) == value)) do
      nil -> raise ArgumentError, "invalid #{field_name}: #{inspect(value)}"
      enum_value -> enum_value
    end
  end

  @doc false
  @spec validate_non_empty_string_refine(term(), String.t(), keyword()) ::
          :ok | {:error, String.t()}
  def validate_non_empty_string_refine(value, field_name, _opts) do
    validate_non_empty_string!(value, field_name)
    :ok
  rescue
    error in ArgumentError -> {:error, Exception.message(error)}
  end

  @doc false
  @spec validate_module_refine(term(), String.t(), keyword()) :: :ok | {:error, String.t()}
  def validate_module_refine(value, field_name, _opts) do
    validate_module!(value, field_name)
    :ok
  rescue
    error in ArgumentError -> {:error, Exception.message(error)}
  end

  @doc false
  @spec validate_map_refine(term(), String.t(), keyword()) :: :ok | {:error, String.t()}
  def validate_map_refine(value, field_name, _opts) do
    validate_map!(value, field_name)
    :ok
  rescue
    error in ArgumentError -> {:error, Exception.message(error)}
  end

  @doc false
  @spec validate_positive_integer_refine(term(), String.t(), keyword()) ::
          :ok | {:error, String.t()}
  def validate_positive_integer_refine(value, field_name, _opts) do
    validate_positive_integer!(value, field_name)
    :ok
  rescue
    error in ArgumentError -> {:error, Exception.message(error)}
  end

  @doc false
  @spec validate_struct_refine(term(), module(), String.t(), keyword()) ::
          :ok | {:error, String.t()}
  def validate_struct_refine(value, module, field_name, _opts) do
    validate_struct!(value, module, field_name)
    :ok
  rescue
    error in ArgumentError -> {:error, Exception.message(error)}
  end

  @doc false
  @spec validate_datetime_refine(term(), String.t(), keyword()) :: :ok | {:error, String.t()}
  def validate_datetime_refine(value, field_name, _opts) do
    validate_datetime!(value, field_name)
    :ok
  rescue
    error in ArgumentError -> {:error, Exception.message(error)}
  end

  @doc false
  @spec validate_keyword_list_refine(term(), String.t(), keyword()) :: :ok | {:error, String.t()}
  def validate_keyword_list_refine(value, field_name, _opts) do
    validate_keyword_list!(value, field_name)
    :ok
  rescue
    error in ArgumentError -> {:error, Exception.message(error)}
  end

  @doc false
  @spec validate_payload_ref_refine(term(), String.t(), keyword()) :: :ok | {:error, String.t()}
  def validate_payload_ref_refine(value, field_name, _opts) do
    validate_payload_ref!(value, field_name)
    :ok
  rescue
    error in ArgumentError -> {:error, Exception.message(error)}
  end

  @doc false
  @spec validate_zoi_schema_refine(term(), String.t(), keyword()) :: :ok | {:error, String.t()}
  def validate_zoi_schema_refine(value, field_name, _opts) do
    validate_zoi_schema!(value, field_name)
    :ok
  rescue
    error in ArgumentError -> {:error, Exception.message(error)}
  end

  @doc false
  @spec normalize_atomish_transform(term(), String.t(), keyword()) ::
          atom() | {:error, String.t()}
  def normalize_atomish_transform(value, field_name, _opts) do
    normalize_atomish!(value, field_name)
  rescue
    error in ArgumentError -> {:error, Exception.message(error)}
  end

  @doc false
  @spec normalize_enumish_transform(term(), [atom()], String.t(), keyword()) ::
          atom() | {:error, String.t()}
  def normalize_enumish_transform(value, values, field_name, _opts) do
    case value do
      atom when is_atom(atom) ->
        if Enum.member?(values, atom) do
          atom
        else
          {:error, "invalid #{field_name}: #{inspect(atom)}"}
        end

      binary when is_binary(binary) ->
        validate_enum_string!(binary, values, field_name)

      other ->
        {:error, "invalid #{field_name}: #{inspect(other)}"}
    end
  rescue
    error in ArgumentError -> {:error, Exception.message(error)}
  end

  defp validate_non_negative_integer!(value, _field_name)
       when is_integer(value) and value >= 0,
       do: value

  defp validate_non_negative_integer!(value, field_name) do
    raise ArgumentError, "#{field_name} must be a non-negative integer, got: #{inspect(value)}"
  end

  defp validate_struct!(%module{} = value, module, _field_name), do: value

  defp validate_struct!(value, module, field_name) do
    raise ArgumentError,
          "#{field_name} must be a #{inspect(module)} struct, got: #{inspect(value)}"
  end

  defp validate_datetime!(%DateTime{} = value, _field_name), do: value

  defp validate_datetime!(value, field_name) do
    raise ArgumentError, "#{field_name} must be a DateTime, got: #{inspect(value)}"
  end

  defp validate_keyword_list!(value, field_name) when is_list(value) do
    if Keyword.keyword?(value) do
      value
    else
      raise ArgumentError, "#{field_name} must be a keyword list, got: #{inspect(value)}"
    end
  end

  defp validate_keyword_list!(value, field_name) do
    raise ArgumentError, "#{field_name} must be a keyword list, got: #{inspect(value)}"
  end

  defp validate_payload_ref!(value, _field_name) do
    normalize_payload_ref!(value)
  end

  defp local_payload_ref?(store, key) do
    store in ["file", "filesystem", "local", "local_file"] or
      String.starts_with?(key, "/") or
      String.match?(key, ~r/\A[A-Za-z]:[\\\/]/)
  end
end
