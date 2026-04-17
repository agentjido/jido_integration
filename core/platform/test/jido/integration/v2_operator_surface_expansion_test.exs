defmodule Jido.Integration.V2OperatorSurfaceExpansionTest do
  use Jido.Integration.V2.Platform.DurableCase

  alias Jido.Integration.V2
  alias Jido.Integration.V2.Attempt
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.ControlPlane.Stores
  alias Jido.Integration.V2.CredentialRef
  alias Jido.Integration.V2.Run

  setup do
    ControlPlane.reset!()
    :ok
  end

  test "runs/1 lists durable runs in deterministic order and supports filtering" do
    first = put_run!("run-a", :accepted, "tenant-1")
    second = put_run!("run-b", :completed, "tenant-2")

    assert Enum.map(V2.runs(%{}), & &1.run_id) == [first.run_id, second.run_id]
    assert Enum.map(V2.runs(%{status: :completed}), & &1.run_id) == [second.run_id]
    assert Enum.map(V2.runs(%{tenant_id: "tenant-1"}), & &1.run_id) == [first.run_id]
  end

  test "boundary sessions and attach grants are projected from durable attempt metadata" do
    run = put_run!("run-session", :completed, "tenant-1")
    attempt = put_attempt!(run, "boundary-1")

    assert [boundary_session] = V2.boundary_sessions(%{})
    assert boundary_session.boundary_session_id == "boundary-1"
    assert boundary_session.route_id == "route-1"
    assert boundary_session.attach_grant_id == "attach_grant:boundary-1:#{attempt.attempt_id}"
    assert boundary_session.target_id == "target-1"
    assert boundary_session.tenant_id == "tenant-1"
    assert boundary_session.status == :attached
    assert boundary_session.metadata["run_id"] == run.run_id

    assert {:ok, fetched_boundary} = V2.fetch_boundary_session("boundary-1")
    assert fetched_boundary.boundary_session_id == boundary_session.boundary_session_id

    assert [attach_grant] = V2.attach_grants(%{})
    assert attach_grant.boundary_session_id == "boundary-1"
    assert attach_grant.route_id == "route-1"
    assert attach_grant.subject_id == run.run_id
    assert attach_grant.status == :issued

    assert {:ok, issued_attach_grant} =
             V2.issue_attach_grant(run.run_id, %{attempt_id: attempt.attempt_id})

    assert issued_attach_grant.attach_grant_id == attach_grant.attach_grant_id

    assert {:ok, fetched_attach_grant} = V2.fetch_attach_grant(attach_grant.attach_grant_id)
    assert fetched_attach_grant.boundary_session_id == attach_grant.boundary_session_id

    assert V2.boundary_sessions(%{tenant_id: "tenant-1"}) == [boundary_session]
    assert V2.attach_grants(%{subject_id: run.run_id}) == [attach_grant]
  end

  test "issue_attach_grant/2 returns a boundary unavailable error when the attempt has no boundary metadata" do
    run = put_run!("run-no-boundary", :completed, "tenant-1")
    _attempt = put_attempt_without_boundary!(run)

    assert {:error, :boundary_session_unavailable} = V2.issue_attach_grant(run.run_id, %{})
  end

  defp put_run!(run_id, status, tenant_id) do
    run =
      Run.new!(%{
        run_id: run_id,
        capability_id: "test.capability",
        runtime_class: :session,
        status: status,
        input: %{"value" => run_id},
        credential_ref:
          CredentialRef.new!(%{
            id: "credential-#{run_id}",
            subject: "operator-#{run_id}",
            scopes: ["test:read"],
            metadata: %{tenant_id: tenant_id}
          }),
        target_id: "target-1"
      })

    :ok = Stores.run_store().put_run(run)
    run
  end

  defp put_attempt!(run, boundary_session_id) do
    attempt =
      Attempt.new!(%{
        run_id: run.run_id,
        attempt: 1,
        runtime_class: :session,
        status: :completed,
        target_id: "target-1",
        runtime_ref_id: "runtime-ref-1",
        output: %{
          "metadata" => %{
            "boundary" => %{
              "descriptor" => %{
                "boundary_session_id" => boundary_session_id,
                "session_status" => "attached"
              },
              "route" => %{
                "route_id" => "route-1"
              },
              "attach_grant" => %{
                "attach_mode" => "read_write"
              }
            }
          }
        }
      })

    :ok = Stores.attempt_store().put_attempt(attempt)
    attempt
  end

  defp put_attempt_without_boundary!(run) do
    attempt =
      Attempt.new!(%{
        run_id: run.run_id,
        attempt: 1,
        runtime_class: :session,
        status: :completed,
        target_id: "target-1",
        runtime_ref_id: "runtime-ref-1",
        output: %{"metadata" => %{}}
      })

    :ok = Stores.attempt_store().put_attempt(attempt)
    attempt
  end
end
