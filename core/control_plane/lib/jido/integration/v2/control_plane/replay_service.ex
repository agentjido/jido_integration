defmodule Jido.Integration.V2.ControlPlane.ReplayService do
  @moduledoc """
  Replay normalization and fixture-result helpers behind the facade.
  """

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.ControlPlane.ClaimCheck
  alias Jido.Integration.V2.ControlPlane.ReplayNormalizer
  alias Jido.Integration.V2.Run
  alias Jido.Integration.V2.RuntimeResult

  @replay_modes [
    :exact,
    :prompt_variant,
    :model_variant,
    :policy_variant,
    :guard_variant,
    :memory_variant
  ]
  @replay_support_classes [:fixture_only, :fixture_required, :not_replay_safe]

  @spec runtime_input(Run.t()) :: {:ok, map()} | {:error, term()}
  def runtime_input(%Run{} = run) do
    with {:ok, payload} <- ClaimCheck.resolve_json(run.input, Map.get(run, :input_payload_ref)) do
      {:ok, ReplayNormalizer.value(payload)}
    end
  end

  @spec replay_mode?(atom() | nil) :: boolean()
  def replay_mode?(replay_mode), do: replay_mode in @replay_modes

  @spec validate_submission(Capability.t(), keyword()) :: :ok | {:error, atom()}
  def validate_submission(capability, opts) do
    case Keyword.get(opts, :replay_mode) do
      nil ->
        :ok

      replay_mode when replay_mode in @replay_modes ->
        validate_support(support_class(capability, opts))

      _replay_mode ->
        {:error, :unknown_replay_mode}
    end
  end

  @spec support_class(Capability.t(), keyword()) :: atom()
  def support_class(capability, opts) do
    Keyword.get(opts, :replay_support_class) ||
      capability.metadata
      |> Contracts.get(:policy, %{})
      |> Contracts.get(:replay_support_class, :fixture_required)
  end

  @spec fixture_result(map()) :: {:ok, RuntimeResult.t()}
  def fixture_result(context) do
    {:ok,
     RuntimeResult.new!(%{
       output: %{
         replay_mode: context.replay_mode,
         replay_support_class: context.replay_support_class,
         fixture_ref: "replay-fixture://#{context.run_id}/#{context.attempt}",
         cost_class: :replay,
         cost_meter_ref: context.cost_meter_ref,
         budget_refs: context.budget_refs
       },
       runtime_ref_id: "replay-fixture-runtime://#{context.run_id}",
       events: [
         %{
           type: "replay.submission.accepted",
           stream: :control,
           payload: %{
             replay_mode: Atom.to_string(context.replay_mode),
             replay_support_class: Atom.to_string(context.replay_support_class),
             cost_class: "replay",
             cost_meter_ref: context.cost_meter_ref,
             budget_refs: context.budget_refs,
             side_effect_policy: "suppress"
           }
         },
         %{
           type: "cost.recorded",
           stream: :control,
           payload: %{
             cost_class: "replay",
             cost_meter_ref: context.cost_meter_ref,
             budget_refs: context.budget_refs
           }
         }
       ],
       artifacts: []
     })}
  end

  defp validate_support(:not_replay_safe), do: {:error, :connector_not_replay_safe}
  defp validate_support(class) when class in @replay_support_classes, do: :ok
  defp validate_support(_class), do: {:error, :unknown_replay_support_class}
end
