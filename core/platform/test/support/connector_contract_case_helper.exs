defmodule Jido.Integration.V2.ConnectorContractCase do
  use ExUnit.CaseTemplate
  import ExUnit.Assertions

  alias Jido.Integration.V2
  alias Jido.Integration.V2.Auth
  alias Jido.Integration.V2.Auth.Connection
  alias Jido.Integration.V2.Auth.Install
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Platform.DurableSupport

  using do
    quote do
      alias Jido.Integration.V2
      alias Jido.Integration.V2.Auth
      import Jido.Integration.V2.ConnectorContractCase
    end
  end

  setup_all do
    DurableSupport.setup_all!()
    :ok
  end

  setup do
    cleanup = DurableSupport.setup!()

    on_exit(cleanup)

    V2.reset!()
    :ok
  end

  def register_connector!(connector) do
    assert :ok = V2.register_connector(connector)
  end

  def install_connection!(connector_id, tenant_id, subject, scopes, secret) do
    now = Contracts.now()

    assert {:ok, %{install: %Install{} = install, connection: %Connection{} = connection}} =
             V2.start_install(connector_id, tenant_id, %{
               actor_id: "connector-contract",
               auth_type: auth_type_for(secret),
               subject: subject,
               requested_scopes: scopes,
               now: now
             })

    install_id = install.install_id
    connection_id = connection.connection_id

    assert {:ok,
            %{
              install: %Install{install_id: ^install_id},
              connection: %Connection{connection_id: ^connection_id},
              credential_ref: %Jido.Integration.V2.CredentialRef{}
            }} =
             V2.complete_install(install.install_id, %{
               subject: subject,
               granted_scopes: scopes,
               secret: secret,
               expires_at: expires_at_for(secret, now),
               now: now
             })

    connection_id
  end

  def invoke_opts(capability_id, connection_id, spec, overrides \\ []) do
    defaults = [
      connection_id: connection_id,
      actor_id: Keyword.get(overrides, :actor_id, "connector-contract"),
      tenant_id: spec.tenant_id,
      environment: spec.environment,
      allowed_operations: [capability_id],
      sandbox: spec.sandbox
    ]

    Keyword.merge(defaults, overrides)
  end

  def assert_review_surface!(result, spec, expected_lease_payload, secret_values) do
    assert {:ok, lease} = Auth.fetch_lease(result.attempt.credential_lease_id)
    assert lease.payload == expected_lease_payload

    events = V2.events(result.run.run_id)
    assert Enum.any?(events, &(&1.type == spec.event_type))
    assert Enum.any?(events, &(&1.type == "artifact.recorded"))

    assert [artifact] = V2.run_artifacts(result.run.run_id)
    assert artifact.attempt_id == result.attempt.attempt_id
    assert artifact.artifact_type == spec.artifact_type
    assert artifact.metadata.connector == spec.connector_id
    assert artifact.metadata.capability_id == spec.capability_id
    assert artifact.payload_ref.store == "connector_review"

    refute_secret_leaks!(result.run, secret_values)
    refute_secret_leaks!(result.attempt, secret_values)
    refute_secret_leaks!(result.output, secret_values)
    refute_secret_leaks!(events, secret_values)
  end

  def refute_secret_leaks!(term, secret_values) do
    inspected = inspect(term)

    Enum.each(secret_values, fn secret ->
      refute inspected =~ secret
    end)
  end

  defp auth_type_for(secret) do
    if Map.has_key?(secret, :api_key), do: :api_key, else: :oauth2
  end

  defp expires_at_for(secret, now) do
    if Map.has_key?(secret, :api_key), do: nil, else: DateTime.add(now, 7 * 24 * 3_600, :second)
  end
end
