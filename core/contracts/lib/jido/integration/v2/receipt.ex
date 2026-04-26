defmodule Jido.Integration.V2.Receipt do
  @moduledoc """
  Durable lower-truth acknowledgement or completion receipt.
  """

  alias Jido.Integration.V2.{ArtifactRef, Attempt, Event, Run}
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @receipt_kinds [:handoff, :execution, :publication]
  @statuses [
    :accepted,
    :completed,
    :failed,
    :cancelled,
    :blocked,
    :input_required,
    :approval_required,
    :timeout,
    :rejected,
    :ambiguous
  ]
  @terminal_statuses [:completed, :failed, :cancelled, :timeout, :rejected]
  @non_terminal_wait_statuses [:blocked, :input_required, :approval_required]
  @execution_failure_kinds [
    :execution_failed,
    :semantic_failure,
    :malformed_protocol,
    :timeout,
    :rejected,
    :infrastructure_error,
    :auth_error,
    :fatal_error
  ]
  @provider_ref_keys [
    "provider_session_id",
    "provider_turn_id",
    "provider_request_id",
    "provider_item_id",
    "provider_tool_call_id",
    "provider_message_id",
    "tool_name",
    "approval_id"
  ]

  @schema Zoi.struct(
            __MODULE__,
            %{
              receipt_id:
                Contracts.non_empty_string_schema("receipt.receipt_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              run_id: Contracts.non_empty_string_schema("receipt.run_id"),
              attempt_id:
                Contracts.non_empty_string_schema("receipt.attempt_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              route_id:
                Contracts.non_empty_string_schema("receipt.route_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              receipt_kind: Contracts.enumish_schema(@receipt_kinds, "receipt.receipt_kind"),
              status: Contracts.enumish_schema(@statuses, "receipt.status"),
              observed_at:
                Contracts.datetime_schema("receipt.observed_at")
                |> Zoi.nullish()
                |> Zoi.optional(),
              metadata: Contracts.any_map_schema() |> Zoi.default(%{}),
              inserted_at:
                Contracts.datetime_schema("receipt.inserted_at")
                |> Zoi.nullish()
                |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = receipt), do: normalize(receipt)
  def new(attrs), do: __MODULE__ |> Schema.new(@schema, attrs) |> Schema.refine_new(&normalize/1)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = receipt), do: normalize(receipt) |> then(fn {:ok, value} -> value end)
  def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs) |> new!()

  @doc """
  Builds a receipt from durable lower run, attempt, event, and artifact records.

  The generated receipt carries only references and correlation IDs. Raw
  provider payloads remain in lower event/artifact storage and are not copied
  into the northbound receipt map.
  """
  @spec from_lower_records(Run.t(), Attempt.t() | nil, [Event.t()], [ArtifactRef.t()], keyword()) ::
          {:ok, t()} | {:error, Exception.t()}
  def from_lower_records(
        %Run{} = run,
        %Attempt{} = attempt,
        events,
        artifacts,
        opts
      )
      when is_list(events) and is_list(artifacts) and is_list(opts) do
    do_from_lower_records(run, attempt, events, artifacts, opts)
  end

  def from_lower_records(%Run{} = run, nil, events, artifacts, opts)
      when is_list(events) and is_list(artifacts) and is_list(opts) do
    do_from_lower_records(run, nil, events, artifacts, opts)
  end

  @spec from_lower_records!(Run.t(), Attempt.t() | nil, [Event.t()], [ArtifactRef.t()], keyword()) ::
          t()
  def from_lower_records!(%Run{} = run, attempt, events, artifacts, opts \\ []) do
    case from_lower_records(run, attempt, events, artifacts, opts) do
      {:ok, receipt} -> receipt
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  @spec terminal?(t()) :: boolean()
  def terminal?(%__MODULE__{status: status}), do: status in @terminal_statuses

  @doc """
  Projects a lower receipt into the map shape consumed by Mezzanine.

  The projection is intentionally normalized and string-keyed because it crosses
  the product/runtime boundary as durable receipt data, not as an Elixir struct.
  """
  @spec to_lower_receipt_map(t()) :: map()
  def to_lower_receipt_map(%__MODULE__{} = receipt) do
    %{
      "artifact_refs" => artifact_refs(receipt),
      "attempt_id" => receipt.attempt_id,
      "failure_kind" => failure_kind_string(receipt),
      "ji_submission_key" => metadata_value(receipt, "ji_submission_key"),
      "lifecycle_hints" => lifecycle_hints(receipt),
      "normalized_outcome_ref" => metadata_value(receipt, "normalized_outcome_ref"),
      "observed_at" => DateTime.to_iso8601(receipt.observed_at),
      "event_refs" => event_refs(receipt),
      "receipt_id" => receipt.receipt_id,
      "receipt_kind" => Atom.to_string(receipt.receipt_kind),
      "provider_refs" => provider_refs(receipt),
      "route_id" => receipt.route_id,
      "routing_facts" => routing_facts(receipt),
      "run_id" => receipt.run_id,
      "state" => Atom.to_string(receipt.status),
      "terminal?" => terminal?(receipt)
    }
  end

  @doc """
  Builds the execution outcome envelope expected by the northbound lower gateway.
  """
  @spec to_execution_outcome(t(), map()) ::
          {:ok, map()} | {:error, {:non_terminal_receipt, atom()}}
  def to_execution_outcome(%__MODULE__{} = receipt, normalized_outcome)
      when is_map(normalized_outcome) do
    if terminal?(receipt) do
      {:ok,
       %{
         receipt_id: receipt.receipt_id,
         status: execution_outcome_status(receipt),
         lower_receipt: to_lower_receipt_map(receipt),
         normalized_outcome: normalized_outcome,
         lifecycle_hints: lifecycle_hints(receipt),
         failure_kind: execution_failure_kind(receipt),
         artifact_refs: artifact_refs(receipt),
         observed_at: receipt.observed_at
       }}
    else
      {:error, {:non_terminal_receipt, receipt.status}}
    end
  end

  @doc """
  Projects this receipt into the map accepted by
  `Mezzanine.WorkflowReceiptSignal.v1`.
  """
  @spec to_workflow_receipt_signal_attrs(t(), map() | keyword()) :: map()
  def to_workflow_receipt_signal_attrs(%__MODULE__{} = receipt, attrs) when is_list(attrs) do
    to_workflow_receipt_signal_attrs(receipt, Map.new(attrs))
  end

  def to_workflow_receipt_signal_attrs(%__MODULE__{} = receipt, attrs) when is_map(attrs) do
    attrs
    |> maybe_put_new(:signal_id, "signal:#{receipt.receipt_id}")
    |> maybe_put_new(:signal_name, "lower_receipt")
    |> maybe_put_new(:signal_version, "v1")
    |> maybe_put_new(:lower_receipt_ref, receipt.receipt_id)
    |> maybe_put_new(:lower_run_ref, receipt.run_id)
    |> maybe_put_new(:lower_attempt_ref, receipt.attempt_id)
    |> maybe_put_new(:lower_event_ref, latest_event_ref(receipt))
    |> maybe_put_new(:idempotency_key, "receipt:#{receipt.receipt_id}:#{receipt.status}")
    |> maybe_put_new(:receipt_state, Atom.to_string(receipt.status))
    |> maybe_put_new(:terminal?, terminal?(receipt))
    |> maybe_put_new(:routing_facts, routing_facts(receipt))
  end

  defp normalize(%__MODULE__{} = receipt) do
    inserted_at = receipt.inserted_at || Contracts.now()
    attempt_id = receipt.attempt_id || "#{receipt.run_id}:run"

    receipt_id =
      receipt.receipt_id ||
        Contracts.receipt_id(receipt.run_id, attempt_id, Atom.to_string(receipt.receipt_kind))

    {:ok,
     %__MODULE__{
       receipt
       | receipt_id: receipt_id,
         attempt_id: attempt_id,
         observed_at: receipt.observed_at || inserted_at,
         inserted_at: inserted_at
     }}
  end

  defp do_from_lower_records(%Run{} = run, attempt, events, artifacts, opts) do
    latest_event = List.last(events)
    attempt_id = attempt_id(run, attempt)

    metadata =
      opts
      |> Keyword.get(:metadata, %{})
      |> Map.new()
      |> maybe_put(
        "ji_submission_key",
        Keyword.get(opts, :ji_submission_key) || ji_submission_key(run)
      )
      |> maybe_put("normalized_outcome_ref", Keyword.get(opts, :normalized_outcome_ref))
      |> maybe_put("artifact_refs", Enum.map(artifacts, & &1.artifact_id))
      |> maybe_put("event_refs", event_refs_from_events(events))
      |> maybe_put("provider_refs", provider_refs_from_events(events))
      |> maybe_put("lifecycle_hints", Keyword.get(opts, :lifecycle_hints, %{}))
      |> maybe_put(
        "failure_kind",
        Keyword.get(opts, :failure_kind) || lower_failure_kind(run, latest_event)
      )

    new(%{
      run_id: run.run_id,
      attempt_id: attempt_id,
      route_id: Keyword.get(opts, :route_id) || route_id(run, attempt),
      receipt_kind: Keyword.get(opts, :receipt_kind, :execution),
      status: Keyword.get(opts, :status) || lower_status(run, attempt, latest_event),
      observed_at: observed_at(run, attempt, latest_event),
      metadata: metadata
    })
  end

  defp execution_outcome_status(%__MODULE__{status: :completed}), do: :ok
  defp execution_outcome_status(%__MODULE__{status: :cancelled}), do: :cancelled
  defp execution_outcome_status(%__MODULE__{}), do: :error

  defp execution_failure_kind(%__MODULE__{status: status})
       when status in [:completed, :cancelled],
       do: nil

  defp execution_failure_kind(%__MODULE__{} = receipt) do
    receipt
    |> failure_kind_string()
    |> failure_kind_atom()
  end

  defp failure_kind_string(%__MODULE__{} = receipt) do
    case metadata_value(receipt, "failure_kind") do
      nil -> default_failure_kind(receipt.status)
      value when is_atom(value) -> Atom.to_string(value)
      value when is_binary(value) -> value
      _other -> default_failure_kind(receipt.status)
    end
  end

  defp default_failure_kind(:failed), do: "execution_failed"
  defp default_failure_kind(:timeout), do: "timeout"
  defp default_failure_kind(:cancelled), do: "cancelled"
  defp default_failure_kind(:rejected), do: "rejected"
  defp default_failure_kind(_status), do: nil

  defp failure_kind_atom(nil), do: nil

  defp failure_kind_atom(value) when is_binary(value) do
    Enum.find(@execution_failure_kinds, :execution_failed, &(Atom.to_string(&1) == value))
  end

  defp routing_facts(%__MODULE__{} = receipt) do
    if terminal?(receipt) do
      %{"terminal_class" => Atom.to_string(receipt.status)}
    else
      maybe_put(
        %{"terminal_class" => "non_terminal"},
        "waiting_on",
        waiting_on(receipt)
      )
    end
  end

  defp waiting_on(%__MODULE__{} = receipt) do
    case metadata_value(receipt, "waiting_on") do
      nil when receipt.status in @non_terminal_wait_statuses -> Atom.to_string(receipt.status)
      nil -> nil
      value when is_atom(value) -> Atom.to_string(value)
      value when is_binary(value) -> value
    end
  end

  defp lifecycle_hints(%__MODULE__{} = receipt) do
    case metadata_value(receipt, "lifecycle_hints") do
      value when is_map(value) -> value
      _other -> %{}
    end
  end

  defp artifact_refs(%__MODULE__{} = receipt) do
    case metadata_value(receipt, "artifact_refs") do
      value when is_list(value) -> Enum.map(value, &to_string/1)
      _other -> []
    end
  end

  defp event_refs(%__MODULE__{} = receipt) do
    case metadata_value(receipt, "event_refs") do
      value when is_list(value) -> value
      _other -> []
    end
  end

  defp provider_refs(%__MODULE__{} = receipt) do
    case metadata_value(receipt, "provider_refs") do
      value when is_map(value) -> value
      _other -> %{}
    end
  end

  defp latest_event_ref(%__MODULE__{} = receipt) do
    receipt
    |> event_refs()
    |> List.last()
    |> case do
      %{"event_id" => event_id} -> event_id
      _other -> nil
    end
  end

  defp metadata_value(%__MODULE__{metadata: metadata}, key) when is_binary(key) do
    Map.get(metadata, key) || Map.get(metadata, String.to_atom(key))
  end

  defp attempt_id(%Run{} = run, nil), do: "#{run.run_id}:run"
  defp attempt_id(%Run{}, %Attempt{} = attempt), do: attempt.attempt_id

  defp route_id(%Run{} = run, nil), do: run.target_id
  defp route_id(%Run{} = run, %Attempt{} = attempt), do: attempt.target_id || run.target_id

  defp lower_status(%Run{status: :completed}, %Attempt{status: :completed}, _event),
    do: :completed

  defp lower_status(%Run{status: :failed}, _attempt, %Event{} = event),
    do: event_failure_status(event)

  defp lower_status(%Run{status: :failed}, _attempt, _event), do: :failed

  defp lower_status(%Run{status: status}, _attempt, _event) when status in [:denied, :shed],
    do: :rejected

  defp lower_status(_run, _attempt, %Event{} = event), do: event_progress_status(event)
  defp lower_status(_run, _attempt, _event), do: :accepted

  defp event_failure_status(%Event{} = event) do
    case payload_value(event.payload, "failure_kind") || payload_value(event.payload, "kind") do
      value when value in ["timeout", :timeout] ->
        :timeout

      value when value in ["cancelled", :cancelled, "user_cancelled", :user_cancelled] ->
        :cancelled

      value when value in ["approval_required", :approval_required] ->
        :approval_required

      value when value in ["input_required", :input_required] ->
        :input_required

      value when value in ["blocked", :blocked] ->
        :blocked

      _other ->
        :failed
    end
  end

  defp event_progress_status(%Event{} = event) do
    case payload_value(event.payload, "status") || payload_value(event.payload, "kind") do
      value when value in ["approval_required", :approval_required] -> :approval_required
      value when value in ["input_required", :input_required] -> :input_required
      value when value in ["blocked", :blocked] -> :blocked
      _other -> :accepted
    end
  end

  defp lower_failure_kind(%Run{status: :failed}, %Event{} = event) do
    payload_value(event.payload, "failure_kind") || payload_value(event.payload, "kind") ||
      "execution_failed"
  end

  defp lower_failure_kind(%Run{status: status}, _event) when status in [:denied, :shed],
    do: "rejected"

  defp lower_failure_kind(_run, _event), do: nil

  defp observed_at(_run, _attempt, %Event{} = event), do: event.ts
  defp observed_at(_run, %Attempt{} = attempt, _event), do: attempt.updated_at
  defp observed_at(%Run{} = run, _attempt, _event), do: run.updated_at

  defp ji_submission_key(%Run{} = run) do
    first_present([
      fetch_path(run.input, [:metadata, :ji_submission_key]),
      fetch_path(run.input, ["metadata", "ji_submission_key"]),
      fetch_path(run.input, [:request, :metadata, :ji_submission_key]),
      fetch_path(run.input, ["request", "metadata", "ji_submission_key"])
    ])
  end

  defp event_refs_from_events(events) do
    Enum.map(events, fn %Event{} = event ->
      event
      |> provider_refs_from_event()
      |> Map.merge(%{
        "event_id" => event.event_id,
        "type" => event.type,
        "seq" => event.seq,
        "attempt_id" => event.attempt_id
      })
      |> drop_nil_values()
    end)
  end

  defp provider_refs_from_events(events) do
    events
    |> Enum.reduce(%{}, fn %Event{} = event, acc ->
      Map.merge(acc, provider_refs_from_event(event), fn _key, left, right -> right || left end)
    end)
    |> drop_nil_values()
  end

  defp provider_refs_from_event(%Event{} = event) do
    Map.new(@provider_ref_keys, fn key ->
      {key, event_provider_value(event, key)}
    end)
    |> drop_nil_values()
  end

  defp event_provider_value(%Event{} = event, key) do
    payload_value(event.payload, key) || payload_value(event.trace, key)
  end

  defp payload_value(value, key) when is_map(value) and is_binary(key) do
    Map.get(value, key) || Map.get(value, String.to_atom(key))
  end

  defp payload_value(_value, _key), do: nil

  defp fetch_path(value, []), do: present_value(value)

  defp fetch_path(value, [key | rest]) when is_map(value) do
    value
    |> payload_value(to_string(key))
    |> fetch_path(rest)
  end

  defp fetch_path(_value, _path), do: nil

  defp first_present(values), do: Enum.find_value(values, &present_value/1)

  defp present_value(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp present_value(value), do: value

  defp drop_nil_values(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end

  defp maybe_put_new(map, key, value), do: Map.put_new(map, key, value)
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
