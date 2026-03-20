defmodule Jido.Integration.V2.Conformance.Suites.DeterministicFixtures do
  @moduledoc false

  alias Jido.Integration.V2.Conformance.CheckResult
  alias Jido.Integration.V2.Conformance.SuiteResult
  alias Jido.Integration.V2.Conformance.SuiteSupport
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.CredentialLease
  alias Jido.Integration.V2.CredentialRef
  alias Jido.Integration.V2.DirectRuntime
  alias Jido.Integration.V2.Gateway.Policy
  alias Jido.Integration.V2.HarnessRuntime

  @spec run(map()) :: SuiteResult.t()
  def run(%{fixtures: raw_fixtures, manifest: manifest}) when is_list(raw_fixtures) do
    checks =
      case raw_fixtures do
        [] ->
          [
            CheckResult.fail(
              "fixtures.present",
              "connectors must publish deterministic conformance fixtures"
            )
          ]

        fixtures ->
          Enum.flat_map(fixtures, &run_fixture(&1, manifest))
      end

    SuiteResult.from_checks(
      :deterministic_fixtures,
      checks,
      "Fixtures prove lease-bound deterministic runtime results"
    )
  end

  def run(%{fixtures: _invalid}) do
    SuiteResult.from_checks(
      :deterministic_fixtures,
      [
        CheckResult.fail("fixtures.shape", "fixtures must be returned as a list")
      ],
      "Fixtures prove lease-bound deterministic runtime results"
    )
  end

  defp run_fixture(raw_fixture, manifest) do
    case normalize_fixture(raw_fixture, manifest) do
      {:ok, fixture, capability} ->
        case execute_fixture(capability, fixture) do
          {:ok, first_result} ->
            second_result = rerun_fixture(capability, fixture)
            fixture_checks(capability, fixture, first_result, second_result)

          {:error, reason} ->
            [
              CheckResult.fail(
                "#{fixture.capability_id}.executed_with_lease",
                "fixture failed with a lease-only context: #{reason}"
              )
            ]
        end

      {:error, capability_id, reason} ->
        [
          CheckResult.fail("#{capability_id}.fixture.valid", reason)
        ]
    end
  end

  defp fixture_checks(capability, fixture, first_result, {:ok, second_result}) do
    first_summary = result_summary(first_result)
    second_summary = result_summary(second_result)

    [
      CheckResult.pass("#{capability.id}.executed_with_lease", "fixture ran successfully"),
      CheckResult.pass("#{capability.id}.runtime_result", "runtime returned RuntimeResult"),
      SuiteSupport.check(
        "#{capability.id}.connector_events",
        Enum.any?(first_result.events, &String.starts_with?(&1.type, "connector.")),
        "fixtures must emit at least one connector.* event"
      ),
      SuiteSupport.check(
        "#{capability.id}.artifacts_present",
        first_result.artifacts != [],
        "fixtures must emit at least one durable artifact ref"
      ),
      SuiteSupport.check(
        "#{capability.id}.deterministic",
        first_summary == second_summary,
        "fixture output changed between identical runs"
      )
    ] ++ expectation_checks(capability.id, fixture.expect, first_result)
  end

  defp fixture_checks(capability, _fixture, _first_result, {:error, reason}) do
    [
      CheckResult.fail(
        "#{capability.id}.deterministic",
        "fixture could not be re-run deterministically: #{reason}"
      )
    ]
  end

  defp expectation_checks(capability_id, expect, result) do
    normalized_output = normalize_output(result.output)

    output_checks =
      case Map.fetch(expect, :output) do
        {:ok, expected_output} ->
          [
            SuiteSupport.check(
              "#{capability_id}.output",
              normalized_output == expected_output,
              "fixture output did not match expectation"
            )
          ]

        :error ->
          []
      end

    event_type_checks =
      case Map.fetch(expect, :event_types) do
        {:ok, event_types} ->
          [
            SuiteSupport.check(
              "#{capability_id}.event_types",
              Enum.map(result.events, & &1.type) == event_types,
              "fixture event types did not match expectation"
            )
          ]

        :error ->
          []
      end

    artifact_type_checks =
      case Map.fetch(expect, :artifact_types) do
        {:ok, artifact_types} ->
          [
            SuiteSupport.check(
              "#{capability_id}.artifact_types",
              Enum.map(result.artifacts, & &1.artifact_type) == artifact_types,
              "fixture artifact types did not match expectation"
            )
          ]

        :error ->
          []
      end

    artifact_key_checks =
      case Map.fetch(expect, :artifact_keys) do
        {:ok, artifact_keys} ->
          [
            SuiteSupport.check(
              "#{capability_id}.artifact_keys",
              Enum.map(result.artifacts, & &1.payload_ref.key) == artifact_keys,
              "fixture artifact payload keys did not match expectation"
            )
          ]

        :error ->
          []
      end

    output_checks ++ event_type_checks ++ artifact_type_checks ++ artifact_key_checks
  end

  defp normalize_fixture(raw_fixture, manifest) when is_map(raw_fixture) do
    capability_id =
      raw_fixture
      |> SuiteSupport.fetch(:capability_id)
      |> to_string()

    case SuiteSupport.fetch_capability(manifest, capability_id) do
      nil ->
        {:error, capability_id, "fixture capability_id does not match a manifest capability"}

      capability ->
        with {:ok, credential_ref} <- normalize_credential_ref(raw_fixture),
             {:ok, credential_lease} <- normalize_credential_lease(raw_fixture),
             {:ok, input} <- normalize_map(raw_fixture, :input),
             {:ok, context} <- normalize_optional_map(raw_fixture, :context),
             {:ok, expect} <- normalize_optional_map(raw_fixture, :expect) do
          {:ok,
           %{
             capability_id: capability_id,
             input: input,
             credential_ref: credential_ref,
             credential_lease: credential_lease,
             context: context,
             expect: expect
           }, capability}
        end
    end
  rescue
    error ->
      {:error, "unknown", Exception.message(error)}
  end

  defp normalize_fixture(_raw_fixture, _manifest) do
    {:error, "unknown", "fixtures must be maps"}
  end

  defp normalize_credential_ref(raw_fixture) do
    case SuiteSupport.fetch(raw_fixture, :credential_ref) do
      %CredentialRef{} = credential_ref ->
        {:ok, credential_ref}

      credential_ref when is_map(credential_ref) ->
        {:ok, CredentialRef.new!(credential_ref)}

      nil ->
        {:error, "fixtures must declare credential_ref"}

      other ->
        {:error, "credential_ref must be a map or CredentialRef, got: #{inspect(other)}"}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp normalize_credential_lease(raw_fixture) do
    case SuiteSupport.fetch(raw_fixture, :credential_lease) do
      %CredentialLease{} = credential_lease ->
        {:ok, credential_lease}

      credential_lease when is_map(credential_lease) ->
        {:ok, CredentialLease.new!(credential_lease)}

      nil ->
        {:error, "fixtures must declare credential_lease"}

      other ->
        {:error, "credential_lease must be a map or CredentialLease, got: #{inspect(other)}"}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp normalize_map(raw_fixture, key) do
    case SuiteSupport.fetch(raw_fixture, key) do
      map when is_map(map) -> {:ok, map}
      other -> {:error, "#{key} must be a map, got: #{inspect(other)}"}
    end
  end

  defp normalize_optional_map(raw_fixture, key) do
    case SuiteSupport.fetch(raw_fixture, key, %{}) do
      map when is_map(map) -> {:ok, map}
      other -> {:error, "#{key} must be a map, got: #{inspect(other)}"}
    end
  end

  defp execute_fixture(capability, fixture) do
    reset_runtime!(capability.runtime_class)

    case dispatch(capability, fixture.input, build_context(capability, fixture)) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason, _result} ->
        {:error, inspect(reason)}
    end
  end

  defp rerun_fixture(capability, fixture), do: execute_fixture(capability, fixture)

  defp build_context(capability, fixture) do
    run_id =
      SuiteSupport.fetch(
        fixture.context,
        :run_id,
        "run-conformance-" <> String.replace(capability.id, ~r/[^a-zA-Z0-9]+/, "-")
      )

    default_context = %{
      run_id: run_id,
      attempt_id: Contracts.attempt_id(run_id, 1),
      credential_ref: fixture.credential_ref,
      credential_lease: fixture.credential_lease,
      policy_inputs: %{
        execution: execution_policy(capability)
      }
    }

    deep_merge(default_context, fixture.context)
  end

  defp execution_policy(capability) do
    contract = Policy.from_capability(capability)

    %{
      runtime_class: capability.runtime_class,
      sandbox: %{
        level: contract.sandbox.level,
        egress: contract.sandbox.egress,
        approvals: contract.sandbox.approvals,
        file_scope: contract.sandbox.file_scope,
        allowed_tools: contract.sandbox.allowed_tools
      }
    }
  end

  defp dispatch(%{runtime_class: :direct} = capability, input, context),
    do: DirectRuntime.execute(capability, input, context)

  defp dispatch(%{runtime_class: runtime_class} = capability, input, context)
       when runtime_class in [:session, :stream],
       do: HarnessRuntime.execute(capability, input, context)

  defp reset_runtime!(:direct), do: :ok

  defp reset_runtime!(runtime_class) when runtime_class in [:session, :stream] do
    {:ok, _apps} = Application.ensure_all_started(:jido_integration_v2_control_plane)
    HarnessRuntime.reset!()
  end

  defp result_summary(result) do
    %{
      output: normalize_output(result.output),
      event_types: Enum.map(result.events, & &1.type),
      artifacts:
        Enum.map(result.artifacts, fn artifact ->
          %{
            artifact_type: artifact.artifact_type,
            key: artifact.payload_ref.key,
            checksum: artifact.checksum,
            size_bytes: artifact.size_bytes,
            metadata: normalize_output(artifact.metadata)
          }
        end)
    }
  end

  defp normalize_output(output) when is_map(output) do
    output
    |> Map.new(fn {key, value} -> {key, normalize_output(value)} end)
    |> Map.drop([
      :stream_id,
      :session_id,
      :runtime_ref_id,
      "stream_id",
      "session_id",
      "runtime_ref_id"
    ])
  end

  defp normalize_output(output) when is_list(output), do: Enum.map(output, &normalize_output/1)
  defp normalize_output(output), do: output

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      deep_merge(left_value, right_value)
    end)
  end

  defp deep_merge(_left, right), do: right
end
