defmodule Jido.Integration.V2.Contracts do
  @moduledoc """
  Shared public types and validation helpers for the greenfield integration platform.
  """

  @schema_version "1.0"

  @type runtime_class :: :direct | :session | :stream
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

  @spec now() :: DateTime.t()
  def now do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end

  @spec next_id(String.t()) :: String.t()
  def next_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
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

  defp validate_non_negative_integer!(value, _field_name)
       when is_integer(value) and value >= 0,
       do: value

  defp validate_non_negative_integer!(value, field_name) do
    raise ArgumentError, "#{field_name} must be a non-negative integer, got: #{inspect(value)}"
  end

  defp local_payload_ref?(store, key) do
    store in ["file", "filesystem", "local", "local_file"] or
      String.starts_with?(key, "/") or
      String.match?(key, ~r/\A[A-Za-z]:[\\\/]/)
  end
end
