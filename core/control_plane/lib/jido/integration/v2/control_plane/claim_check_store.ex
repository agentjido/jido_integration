defmodule Jido.Integration.V2.ControlPlane.ClaimCheckStore do
  @moduledoc false

  alias Jido.Integration.V2.Contracts

  @type stage_metadata :: %{
          required(:content_type) => String.t(),
          required(:redaction_class) => String.t(),
          optional(:payload_kind) => atom() | String.t(),
          optional(:trace_id) => String.t() | nil
        }

  @type reference_metadata :: %{
          required(:ledger_kind) => atom() | String.t(),
          required(:ledger_id) => String.t(),
          required(:payload_field) => atom() | String.t(),
          optional(:run_id) => String.t() | nil,
          optional(:attempt_id) => String.t() | nil,
          optional(:event_id) => String.t() | nil,
          optional(:trace_id) => String.t() | nil
        }

  @callback stage_blob(Contracts.payload_ref(), binary(), stage_metadata()) ::
              :ok | {:error, term()}
  @callback fetch_blob(Contracts.payload_ref()) :: {:ok, binary()} | :error | {:error, term()}
  @callback register_reference(Contracts.payload_ref(), reference_metadata()) ::
              :ok | {:error, term()}
  @callback fetch_blob_metadata(Contracts.payload_ref()) :: {:ok, map()} | :error
  @callback count_live_references(Contracts.payload_ref()) :: non_neg_integer()
  @callback sweep_staged_payloads(keyword()) :: {:ok, map()} | {:error, term()}
  @callback garbage_collect(keyword()) :: {:ok, map()} | {:error, term()}
end
