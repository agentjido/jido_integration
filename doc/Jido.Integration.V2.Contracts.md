# `Jido.Integration.V2.Contracts`

Shared public types and validation helpers for the greenfield integration platform.

# `access_control`

```elixir
@type access_control() :: :run_scoped | :tenant_scoped | :public_read
```

# `approvals`

```elixir
@type approvals() :: :none | :manual | :auto
```

# `artifact_type`

```elixir
@type artifact_type() ::
  :event_log
  | :stdout
  | :stderr
  | :diff
  | :tarball
  | :tool_output
  | :log
  | :custom
```

# `attempt_status`

```elixir
@type attempt_status() :: :accepted | :running | :completed | :failed
```

# `authority_source`

```elixir
@type authority_source() :: :jido_integration | :jido_os | :external
```

# `checksum`

```elixir
@type checksum() :: String.t()
```

# `egress_policy`

```elixir
@type egress_policy() :: :blocked | :restricted | :open
```

# `event_level`

```elixir
@type event_level() :: :debug | :info | :warn | :error
```

# `event_stream`

```elixir
@type event_stream() :: :assistant | :stdout | :stderr | :system | :control
```

# `inference_checkpoint_policy`

```elixir
@type inference_checkpoint_policy() :: :summary | :artifact | :disabled
```

# `inference_operation`

```elixir
@type inference_operation() :: :generate_text | :stream_text
```

# `inference_protocol`

```elixir
@type inference_protocol() :: :openai_chat_completions
```

# `inference_status`

```elixir
@type inference_status() :: :ok | :error | :cancelled
```

# `inference_target_class`

```elixir
@type inference_target_class() ::
  :cloud_provider | :cli_endpoint | :self_hosted_endpoint
```

# `management_mode`

```elixir
@type management_mode() :: :provider_managed | :jido_managed | :externally_managed
```

# `payload_ref`

```elixir
@type payload_ref() :: %{
  store: String.t(),
  key: String.t(),
  ttl_s: pos_integer(),
  access_control: access_control(),
  checksum: checksum(),
  size_bytes: non_neg_integer()
}
```

# `run_status`

```elixir
@type run_status() :: :accepted | :running | :completed | :failed | :denied | :shed
```

# `runtime_class`

```elixir
@type runtime_class() :: :direct | :session | :stream
```

# `runtime_kind`

```elixir
@type runtime_kind() :: :client | :task | :service
```

# `sandbox_level`

```elixir
@type sandbox_level() :: :strict | :standard | :none
```

# `target_health`

```elixir
@type target_health() :: :healthy | :degraded | :unavailable
```

# `target_mode`

```elixir
@type target_mode() :: :local | :ssh | :beam | :bus | :http
```

# `trace_context`

```elixir
@type trace_context() :: %{
  trace_id: String.t() | nil,
  span_id: String.t() | nil,
  correlation_id: String.t() | nil,
  causation_id: String.t() | nil
}
```

# `transport_mode`

```elixir
@type transport_mode() :: :inline | :chunked | :object_store
```

# `trigger_source`

```elixir
@type trigger_source() :: :webhook | :poll
```

# `trigger_status`

```elixir
@type trigger_status() :: :accepted | :rejected
```

# `zoi_schema`

```elixir
@type zoi_schema() :: term()
```

# `any_map_schema`

```elixir
@spec any_map_schema() :: zoi_schema()
```

# `atomish_schema`

```elixir
@spec atomish_schema(String.t()) :: zoi_schema()
```

# `attempt_from_id!`

```elixir
@spec attempt_from_id!(String.t(), String.t()) :: pos_integer()
```

# `attempt_id`

```elixir
@spec attempt_id(String.t(), pos_integer()) :: String.t()
```

# `boundary_metadata_contract_keys`

```elixir
@spec boundary_metadata_contract_keys() :: [String.t(), ...]
```

# `datetime_schema`

```elixir
@spec datetime_schema(String.t()) :: zoi_schema()
```

# `dump_json_safe!`

```elixir
@spec dump_json_safe!(term()) :: term()
```

# `enumish_schema`

```elixir
@spec enumish_schema([atom()], String.t()) :: zoi_schema()
```

# `event_id`

```elixir
@spec event_id(String.t(), String.t() | nil, non_neg_integer()) :: String.t()
```

# `execution_plane_contract_packet`

```elixir
@spec execution_plane_contract_packet() :: [String.t(), ...]
```

# `fetch!`

```elixir
@spec fetch!(map(), atom()) :: term()
```

# `fetch_required!`

```elixir
@spec fetch_required!(map(), atom(), String.t()) :: term()
```

# `get`

```elixir
@spec get(map(), atom(), term()) :: term()
```

# `inference_contract_version`

```elixir
@spec inference_contract_version() :: String.t()
```

# `keyword_list_schema`

```elixir
@spec keyword_list_schema(String.t()) :: zoi_schema()
```

# `lower_restart_authority_contracts`

```elixir
@spec lower_restart_authority_contracts() :: [String.t(), ...]
```

# `map_schema`

```elixir
@spec map_schema(String.t()) :: zoi_schema()
```

# `module_schema`

```elixir
@spec module_schema(String.t()) :: zoi_schema()
```

# `next_id`

```elixir
@spec next_id(String.t()) :: String.t()
```

# `non_empty_string_schema`

```elixir
@spec non_empty_string_schema(String.t()) :: zoi_schema()
```

# `normalize_atomish!`

```elixir
@spec normalize_atomish!(term(), String.t()) :: atom()
```

# `normalize_atomish_list!`

```elixir
@spec normalize_atomish_list!(list(), String.t()) :: [atom()]
```

# `normalize_payload_ref!`

```elixir
@spec normalize_payload_ref!(map()) :: payload_ref()
```

# `normalize_string_list!`

```elixir
@spec normalize_string_list!(list(), String.t()) :: [String.t()]
```

# `normalize_trace`

```elixir
@spec normalize_trace(map()) :: trace_context()
```

# `normalize_version_list!`

```elixir
@spec normalize_version_list!(list(), String.t()) :: [String.t()]
```

# `now`

```elixir
@spec now() :: DateTime.t()
```

# `operator_read_contracts`

```elixir
@spec operator_read_contracts() :: [String.t(), ...]
```

# `ordered_object!`

```elixir
@spec ordered_object!(keyword(), keyword()) :: zoi_schema()
```

Builds a `Zoi.object/2` schema from an ordered keyword list.

`Zoi` preserves object field order. Using maps here makes the resulting schema
order depend on map enumeration, which can diverge between compile-time
generated modules and runtime manifest construction.

# `payload_ref_schema`

```elixir
@spec payload_ref_schema(String.t()) :: zoi_schema()
```

# `placeholder_zoi_schema?`

```elixir
@spec placeholder_zoi_schema?(term()) :: boolean()
```

# `positive_integer_schema`

```elixir
@spec positive_integer_schema(String.t()) :: zoi_schema()
```

# `provisional_minimal_lane_contracts`

```elixir
@spec provisional_minimal_lane_contracts() :: [String.t(), ...]
```

# `receipt_id`

```elixir
@spec receipt_id(String.t(), String.t(), String.t()) :: String.t()
```

# `recovery_task_id`

```elixir
@spec recovery_task_id(String.t(), String.t()) :: String.t()
```

# `reference_uri`

```elixir
@spec reference_uri(String.t(), atom(), String.t()) :: String.t()
```

# `review_packet_ref`

```elixir
@spec review_packet_ref(String.t(), String.t() | nil) :: String.t()
```

# `schema_version`

```elixir
@spec schema_version() :: String.t()
```

# `strict_object!`

```elixir
@spec strict_object!(keyword(), keyword()) :: zoi_schema()
```

Builds a strict `Zoi.object/2` schema from an ordered keyword list.

# `string_list_schema`

```elixir
@spec string_list_schema(String.t()) :: zoi_schema()
```

# `struct_schema`

```elixir
@spec struct_schema(module(), String.t()) :: zoi_schema()
```

# `validate_access_control!`

```elixir
@spec validate_access_control!(access_control()) :: access_control()
```

# `validate_aggregator_epoch!`

```elixir
@spec validate_aggregator_epoch!(pos_integer()) :: pos_integer()
```

# `validate_approvals!`

```elixir
@spec validate_approvals!(approvals()) :: approvals()
```

# `validate_artifact_type!`

```elixir
@spec validate_artifact_type!(artifact_type()) :: artifact_type()
```

# `validate_attempt!`

```elixir
@spec validate_attempt!(pos_integer()) :: pos_integer()
```

# `validate_attempt_status!`

```elixir
@spec validate_attempt_status!(attempt_status()) :: attempt_status()
```

# `validate_authority_source!`

```elixir
@spec validate_authority_source!(authority_source()) :: authority_source()
```

# `validate_checksum!`

```elixir
@spec validate_checksum!(checksum()) :: checksum()
```

# `validate_egress_policy!`

```elixir
@spec validate_egress_policy!(egress_policy()) :: egress_policy()
```

# `validate_enum_atomish!`

```elixir
@spec validate_enum_atomish!(term(), [atom()], String.t()) :: atom()
```

# `validate_event_level!`

```elixir
@spec validate_event_level!(event_level()) :: event_level()
```

# `validate_event_seq!`

```elixir
@spec validate_event_seq!(non_neg_integer()) :: non_neg_integer()
```

# `validate_event_stream!`

```elixir
@spec validate_event_stream!(event_stream()) :: event_stream()
```

# `validate_inference_checkpoint_policy!`

```elixir
@spec validate_inference_checkpoint_policy!(inference_checkpoint_policy()) ::
  inference_checkpoint_policy()
```

# `validate_inference_contract_version!`

```elixir
@spec validate_inference_contract_version!(String.t()) :: String.t()
```

# `validate_inference_operation!`

```elixir
@spec validate_inference_operation!(inference_operation()) :: inference_operation()
```

# `validate_inference_protocol!`

```elixir
@spec validate_inference_protocol!(inference_protocol()) :: inference_protocol()
```

# `validate_inference_status!`

```elixir
@spec validate_inference_status!(inference_status()) :: inference_status()
```

# `validate_inference_target_class!`

```elixir
@spec validate_inference_target_class!(inference_target_class()) ::
  inference_target_class()
```

# `validate_management_mode!`

```elixir
@spec validate_management_mode!(management_mode()) :: management_mode()
```

# `validate_map!`

```elixir
@spec validate_map!(term(), String.t()) :: map()
```

# `validate_module!`

```elixir
@spec validate_module!(term(), String.t()) :: module()
```

# `validate_non_empty_string!`

```elixir
@spec validate_non_empty_string!(term(), String.t()) :: String.t()
```

# `validate_positive_integer!`

```elixir
@spec validate_positive_integer!(term(), String.t()) :: pos_integer()
```

# `validate_run_status!`

```elixir
@spec validate_run_status!(run_status()) :: run_status()
```

# `validate_runtime_class!`

```elixir
@spec validate_runtime_class!(runtime_class()) :: runtime_class()
```

# `validate_runtime_kind!`

```elixir
@spec validate_runtime_kind!(runtime_kind()) :: runtime_kind()
```

# `validate_sandbox_level!`

```elixir
@spec validate_sandbox_level!(sandbox_level()) :: sandbox_level()
```

# `validate_semver!`

```elixir
@spec validate_semver!(String.t(), String.t()) :: String.t()
```

# `validate_target_health!`

```elixir
@spec validate_target_health!(target_health()) :: target_health()
```

# `validate_target_mode!`

```elixir
@spec validate_target_mode!(target_mode()) :: target_mode()
```

# `validate_transport_mode!`

```elixir
@spec validate_transport_mode!(transport_mode()) :: transport_mode()
```

# `validate_trigger_source!`

```elixir
@spec validate_trigger_source!(trigger_source()) :: trigger_source()
```

# `validate_trigger_status!`

```elixir
@spec validate_trigger_status!(trigger_status()) :: trigger_status()
```

# `validate_version_requirement!`

```elixir
@spec validate_version_requirement!(String.t() | nil) :: String.t() | nil
```

# `validate_zoi_schema!`

```elixir
@spec validate_zoi_schema!(term(), String.t()) :: zoi_schema()
```

# `zoi_schema?`

```elixir
@spec zoi_schema?(term()) :: boolean()
```

# `zoi_schema_schema`

```elixir
@spec zoi_schema_schema(String.t()) :: zoi_schema()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
