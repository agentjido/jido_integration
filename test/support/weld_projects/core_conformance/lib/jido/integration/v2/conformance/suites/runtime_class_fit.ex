defmodule Jido.Integration.V2.Conformance.Suites.RuntimeClassFit do
  @moduledoc false

  alias Jido.Integration.V2.Conformance.SuiteResult
  alias Jido.Integration.V2.Conformance.SuiteSupport
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.RuntimeRouter

  @spec run(map()) :: SuiteResult.t()
  def run(%{manifest: manifest}) do
    checks =
      Enum.flat_map(Manifest.capabilities(manifest), fn capability ->
        handler = capability.handler
        loaded? = Code.ensure_loaded?(handler)
        runtime_driver_declared? = runtime_driver_declared?(capability)

        [
          SuiteSupport.check(
            "#{capability.id}.handler.loaded",
            loaded?,
            "handler #{inspect(handler)} could not be loaded"
          ),
          SuiteSupport.check(
            "#{capability.id}.runtime_driver_declared",
            runtime_driver_declared?,
            runtime_driver_error(capability)
          ),
          SuiteSupport.check(
            "#{capability.id}.runtime_contract",
            loaded? and runtime_handler_valid?(capability, handler),
            runtime_contract_error(capability, handler)
          )
        ]
      end)

    SuiteResult.from_checks(
      :runtime_class_fit,
      checks,
      "Handlers match the declared runtime family contract"
    )
  end

  defp runtime_handler_valid?(%{runtime_class: :direct}, handler),
    do: function_exported?(handler, :run, 2)

  defp runtime_handler_valid?(%{runtime_class: runtime_class} = capability, _handler)
       when runtime_class in [:session, :stream] do
    target_runtime_control_driver?(capability)
  end

  defp runtime_handler_valid?(%{runtime_class: :session}, handler) do
    function_exported?(handler, :reuse_key, 2) and
      function_exported?(handler, :open_session, 2) and
      function_exported?(handler, :execute, 4)
  end

  defp runtime_handler_valid?(%{runtime_class: :stream}, handler) do
    function_exported?(handler, :reuse_key, 3) and
      function_exported?(handler, :open_stream, 3) and
      function_exported?(handler, :pull, 4)
  end

  defp runtime_driver_declared?(%{runtime_class: :direct}), do: true

  defp runtime_driver_declared?(%{metadata: metadata}) when is_map(metadata) do
    case Map.get(metadata, :runtime) || Map.get(metadata, "runtime") do
      runtime when is_map(runtime) ->
        driver = Map.get(runtime, :driver) || Map.get(runtime, "driver")
        (is_binary(driver) and String.trim(driver) != "") or is_atom(driver)

      _other ->
        false
    end
  end

  defp runtime_driver_declared?(_capability), do: false

  defp runtime_contract_error(%{runtime_class: :direct}, handler) do
    "direct handlers must export run/2; #{inspect(handler)} does not"
  end

  defp runtime_contract_error(%{runtime_class: :session} = capability, handler) do
    if target_runtime_control_driver?(capability) do
      "session connectors targeting accepted Runtime Control drivers only need a loadable marker handler; #{inspect(handler)} could not be used"
    else
      "session providers must export reuse_key/2, open_session/2, and execute/4; #{inspect(handler)} does not"
    end
  end

  defp runtime_contract_error(%{runtime_class: :stream} = capability, handler) do
    if target_runtime_control_driver?(capability) do
      "stream connectors targeting accepted Runtime Control drivers only need a loadable marker handler; #{inspect(handler)} could not be used"
    else
      "stream providers must export reuse_key/3, open_stream/3, and pull/4; #{inspect(handler)} does not"
    end
  end

  defp runtime_driver_error(%{runtime_class: runtime_class, id: capability_id}) do
    "#{capability_id} declares #{runtime_class} work but does not expose metadata.runtime.driver"
  end

  defp target_runtime_control_driver?(capability) do
    case runtime_driver_id(capability) do
      driver_id when is_binary(driver_id) ->
        driver_id in RuntimeRouter.target_driver_ids()

      _other ->
        false
    end
  end

  defp runtime_driver_id(%{metadata: metadata}) when is_map(metadata) do
    case Map.get(metadata, :runtime) || Map.get(metadata, "runtime") do
      runtime when is_map(runtime) ->
        Map.get(runtime, :driver) || Map.get(runtime, "driver")

      _other ->
        nil
    end
  end

  defp runtime_driver_id(_capability), do: nil
end
