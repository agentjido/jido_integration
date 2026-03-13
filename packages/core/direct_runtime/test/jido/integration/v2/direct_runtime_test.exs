defmodule Jido.Integration.V2.DirectRuntimeTest do
  use ExUnit.Case

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.CredentialRef
  alias Jido.Integration.V2.DirectRuntime
  alias Jido.Integration.V2.RuntimeResult

  defmodule EchoAction do
    use Jido.Action,
      name: "echo_action",
      schema: [message: [type: :string, required: true]]

    @impl true
    def run(params, context) do
      {:ok,
       RuntimeResult.new!(%{
         output: %{echo: params.message},
         events: [
           %{
             type: "connector.test.echoed",
             payload: %{run_id: context.run_id, message: params.message}
           }
         ]
       })}
    end
  end

  test "executes a direct capability through a Jido.Action handler and preserves connector events" do
    capability =
      Capability.new!(%{
        id: "test.echo",
        connector: "test",
        runtime_class: :direct,
        kind: :operation,
        transport_profile: :action,
        handler: EchoAction
      })

    context = %{
      run_id: "run-1",
      attempt_id: "attempt-1",
      credential_ref: CredentialRef.new!(%{id: "cred-1", subject: "tester"})
    }

    assert {:ok, result} = DirectRuntime.execute(capability, %{message: "hello"}, context)
    assert result.output == %{echo: "hello"}

    assert Enum.map(result.events, & &1.type) == [
             "attempt.started",
             "connector.test.echoed",
             "attempt.completed"
           ]
  end
end
