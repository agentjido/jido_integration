defmodule Jido.Integration.V2.Conformance.Suites.RuntimeClassFit do
  @moduledoc false

  alias Jido.Integration.V2.Conformance.SuiteResult
  alias Jido.Integration.V2.Conformance.SuiteSupport

  @spec run(map()) :: SuiteResult.t()
  def run(%{manifest: manifest}) do
    checks =
      Enum.flat_map(manifest.capabilities, fn capability ->
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
            loaded? and runtime_handler_valid?(capability.runtime_class, handler),
            runtime_contract_error(capability.runtime_class, handler)
          )
        ]
      end)

    SuiteResult.from_checks(
      :runtime_class_fit,
      checks,
      "Handlers match the declared runtime family contract"
    )
  end

  defp runtime_handler_valid?(:direct, handler), do: function_exported?(handler, :run, 2)

  defp runtime_handler_valid?(:session, handler) do
    function_exported?(handler, :reuse_key, 2) and
      function_exported?(handler, :open_session, 2) and
      function_exported?(handler, :execute, 4)
  end

  defp runtime_handler_valid?(:stream, handler) do
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

  defp runtime_contract_error(:direct, handler) do
    "direct handlers must export run/2; #{inspect(handler)} does not"
  end

  defp runtime_contract_error(:session, handler) do
    "session providers must export reuse_key/2, open_session/2, and execute/4; #{inspect(handler)} does not"
  end

  defp runtime_contract_error(:stream, handler) do
    "stream providers must export reuse_key/3, open_stream/3, and pull/4; #{inspect(handler)} does not"
  end

  defp runtime_driver_error(%{runtime_class: runtime_class, id: capability_id}) do
    "#{capability_id} declares #{runtime_class} work but does not expose metadata.runtime.driver"
  end
end
