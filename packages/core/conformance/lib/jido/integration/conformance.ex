defmodule Jido.Integration.Conformance do
  @moduledoc """
  Conformance runner for connector adapters.

  The report shape follows the Build-Now charter output contract:
  all doc 045 suite groups are represented, with profile- and role-gated
  suites emitted as `:skipped` when they do not apply.
  """

  alias Jido.Integration.Auth.Descriptor, as: AuthDescriptor
  alias Jido.Integration.{Capability, Error, Manifest, Telemetry}
  alias Jido.Integration.Operation.Envelope
  alias Jido.Integration.Trigger.Descriptor, as: TriggerDescriptor

  @type result :: %{
          suite: String.t(),
          status: :passed | :failed | :skipped,
          checks: [check_result()],
          duration_ms: non_neg_integer(),
          reason: String.t() | nil
        }

  @type check_result :: %{
          name: String.t(),
          status: :passed | :failed,
          message: String.t() | nil
        }

  @type profile :: :mvp_foundation | :bronze | :silver | :gold

  @type report :: %{
          connector_id: String.t(),
          connector_version: String.t(),
          profile: profile(),
          runner_version: String.t(),
          suite_results: [result()],
          pass_fail: :pass | :fail,
          quality_tier_eligible: String.t() | nil,
          evidence_refs: [String.t()],
          exceptions_applied: [map()],
          timestamp: String.t(),
          duration_ms: non_neg_integer()
        }

  @profiles [:mvp_foundation, :bronze, :silver, :gold]
  @distributed_roles [:dispatch_consumer, :run_aggregator, :control_plane]
  @suite_defs [
    %{suite: "manifest", min_profile: :mvp_foundation, fun: :check_manifest_suite},
    %{suite: "operations", min_profile: :bronze, fun: :check_operations_suite},
    %{suite: "triggers", min_profile: :silver, fun: :check_triggers_suite},
    %{suite: "auth", min_profile: :bronze, fun: :check_auth_suite},
    %{suite: "security", min_profile: :mvp_foundation, fun: :check_security_suite},
    %{suite: "gateway", min_profile: :bronze, fun: :check_gateway_suite},
    %{suite: "determinism", min_profile: :silver, fun: :check_determinism_suite},
    %{suite: "telemetry", min_profile: :mvp_foundation, fun: :check_telemetry_suite},
    %{suite: "compliance_minimum", min_profile: :mvp_foundation, fun: :check_compliance_suite},
    %{
      suite: "distributed_correctness",
      min_profile: :mvp_foundation,
      roles: @distributed_roles,
      fun: :check_distributed_correctness_suite
    },
    %{
      suite: "artifact_transport",
      min_profile: :mvp_foundation,
      roles: @distributed_roles,
      fun: :check_artifact_transport_suite
    },
    %{
      suite: "policy_enforcement",
      min_profile: :mvp_foundation,
      roles: @distributed_roles,
      fun: :check_policy_enforcement_suite
    }
  ]

  @doc "Returns valid conformance profiles."
  @spec profiles() :: [profile()]
  def profiles, do: @profiles

  @doc """
  Run conformance checks against an adapter module.

  ## Options

  - `:profile` — conformance profile (default: `:mvp_foundation`)
  - `:fixture_dir` — optional fixture directory for determinism checks
  - `:roles` — repo roles; defaults to `[:connector]`
  """
  @spec run(module(), keyword()) :: report()
  def run(adapter_module, opts \\ []) when is_atom(adapter_module) do
    profile = Keyword.get(opts, :profile, :mvp_foundation)
    start_time = System.monotonic_time(:millisecond)

    manifest = adapter_module.manifest()

    context = %{
      adapter: adapter_module,
      manifest: manifest,
      profile: profile,
      roles: normalize_roles(Keyword.get(opts, :roles, [:connector])),
      fixture_dir: Keyword.get(opts, :fixture_dir),
      source_path: module_source_path(adapter_module)
    }

    suite_results =
      Enum.map(@suite_defs, fn suite_def ->
        run_suite(suite_def, context)
      end)

    pass_fail =
      if Enum.any?(suite_results, &(&1.status == :failed)), do: :fail, else: :pass

    eligible_tier =
      case pass_fail do
        :pass -> profile_to_tier(profile)
        :fail -> nil
      end

    duration = System.monotonic_time(:millisecond) - start_time

    report = %{
      connector_id: manifest.id,
      connector_version: manifest.version,
      profile: profile,
      runner_version: runner_version(),
      suite_results: suite_results,
      pass_fail: pass_fail,
      quality_tier_eligible: eligible_tier,
      evidence_refs: evidence_refs(context),
      exceptions_applied: [],
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      duration_ms: duration
    }

    _ =
      Telemetry.emit("jido.integration.conformance.suite_completed", %{duration_ms: duration}, %{
        connector_id: manifest.id,
        profile: profile,
        pass_fail: pass_fail
      })

    report
  end

  @doc "Check if a conformance report passed."
  @spec passed?(report()) :: boolean()
  def passed?(%{pass_fail: :pass}), do: true
  def passed?(_), do: false

  @doc "Get failed checks from a report."
  @spec failures(report()) :: [check_result()]
  def failures(%{suite_results: results}) do
    results
    |> Enum.flat_map(& &1.checks)
    |> Enum.filter(&(&1.status == :failed))
  end

  defp run_suite(%{suite: suite, roles: roles} = suite_def, %{roles: repo_roles} = context) do
    if Enum.any?(repo_roles, &(&1 in roles)) do
      run_suite_without_role_gate(suite_def, context)
    else
      skipped_suite(suite, "not_applicable: role_mismatch")
    end
  end

  defp run_suite(suite_def, context), do: run_suite_without_role_gate(suite_def, context)

  defp run_suite_without_role_gate(
         %{suite: suite, min_profile: min_profile, fun: fun},
         %{profile: profile} = context
       ) do
    if profile_includes?(profile, min_profile) do
      call_suite(fun, context)
    else
      skipped_suite(suite, "not_in_profile: #{profile}")
    end
  end

  defp check_manifest_suite(%{manifest: manifest}) do
    start = System.monotonic_time(:millisecond)

    capability_checks =
      if map_size(manifest.capabilities) == 0 do
        [
          check(
            "manifest.capabilities_optional",
            true,
            "No capabilities declared (OK for Build-Now)"
          )
        ]
      else
        Enum.map(manifest.capabilities, fn {key, status} ->
          check(
            "manifest.capabilities.#{key}.valid",
            Capability.valid_key?(key) && Capability.valid_status?(status),
            "Invalid capability: #{key} = #{status}"
          )
        end)
      end

    checks =
      [
        check("manifest.id_present", manifest.id != nil && manifest.id != ""),
        check("manifest.id_is_string", is_binary(manifest.id)),
        check("manifest.display_name_present", manifest.display_name != nil),
        check("manifest.vendor_present", manifest.vendor != nil),
        check("manifest.domain_valid", manifest.domain in Manifest.valid_domains()),
        check("manifest.version_valid", Version.parse(manifest.version) != :error),
        check(
          "manifest.quality_tier_valid",
          manifest.quality_tier in Manifest.valid_quality_tiers()
        ),
        check("manifest.auth_present", is_list(manifest.auth) && manifest.auth != []),
        check("manifest.operations_is_list", is_list(manifest.operations))
      ] ++ capability_checks

    suite_result("manifest", checks, start)
  end

  defp check_operations_suite(%{manifest: manifest}) do
    start = System.monotonic_time(:millisecond)

    checks =
      if manifest.operations == [] do
        [check("operations.present", true, "No operations declared")]
      else
        Enum.flat_map(manifest.operations, fn op ->
          [
            check("operations.#{op.id}.id_present", op.id != nil),
            check("operations.#{op.id}.summary_present", op.summary != nil),
            check("operations.#{op.id}.input_schema_present", is_map(op.input_schema)),
            check("operations.#{op.id}.output_schema_present", is_map(op.output_schema)),
            check("operations.#{op.id}.timeout_positive", op.timeout_ms > 0),
            check("operations.#{op.id}.errors_is_list", is_list(op.errors))
          ]
        end)
      end

    suite_result("operations", checks, start)
  end

  defp check_triggers_suite(%{manifest: manifest}) do
    start = System.monotonic_time(:millisecond)

    checks =
      if manifest.triggers == [] do
        [check("triggers.none_declared", true)]
      else
        Enum.flat_map(manifest.triggers, fn trigger ->
          [
            check("triggers.#{trigger.id}.id_present", trigger.id != nil),
            check(
              "triggers.#{trigger.id}.class_valid",
              trigger.class in TriggerDescriptor.valid_classes()
            ),
            check("triggers.#{trigger.id}.summary_present", trigger.summary != nil),
            check(
              "triggers.#{trigger.id}.delivery_valid",
              trigger.delivery_semantics in TriggerDescriptor.valid_delivery_semantics()
            ),
            check(
              "triggers.#{trigger.id}.topology_valid",
              trigger.callback_topology in TriggerDescriptor.valid_topologies()
            )
          ]
        end)
      end

    suite_result("triggers", checks, start)
  end

  defp check_auth_suite(%{manifest: manifest}) do
    start = System.monotonic_time(:millisecond)

    checks =
      Enum.flat_map(manifest.auth, fn auth ->
        [
          check("auth.#{auth.id}.id_present", auth.id != nil),
          check("auth.#{auth.id}.type_valid", auth.type in AuthDescriptor.valid_types()),
          check("auth.#{auth.id}.display_name_present", auth.display_name != nil),
          check("auth.#{auth.id}.secret_refs_is_list", is_list(auth.secret_refs)),
          check("auth.#{auth.id}.scopes_is_list", is_list(auth.scopes)),
          check(
            "auth.#{auth.id}.tenant_binding_valid",
            auth.tenant_binding in AuthDescriptor.valid_tenant_bindings()
          )
        ]
      end)

    suite_result("auth", checks, start)
  end

  defp check_security_suite(%{adapter: adapter, source_path: source_path}) do
    start = System.monotonic_time(:millisecond)
    source = read_source(source_path)

    checks = [
      security_id_check(adapter),
      check(
        "security.no_string_to_atom",
        not Regex.match?(~r/\bString\.to_atom\s*\(/, source),
        "Adapter source must not call String.to_atom/1 in integration boundary code"
      ),
      check(
        "security.webhook_verification_control_plane_only",
        not function_exported?(adapter, :verify_webhook, 2) and
          not function_exported?(adapter, :verify_webhook, 3),
        "Webhook signature verification must live in the control plane, not the connector package"
      ),
      check(
        "security.secrets_via_token_refs",
        not Regex.match?(
          ~r/(System|Application)\.get_env\([^\\n]*(token|secret|api[_-]?key|password|credential)/i,
          source
        ),
        "Runtime code must not read raw secrets from env/app config outside test fixtures"
      )
    ]

    suite_result("security", checks, start)
  end

  defp check_gateway_suite(%{manifest: manifest}) do
    start = System.monotonic_time(:millisecond)

    checks =
      [
        check(
          "gateway.default_policy_available",
          Code.ensure_loaded?(Jido.Integration.Gateway.Policy.Default),
          "Default gateway policy is not available"
        )
      ] ++
        Enum.map(manifest.operations, fn op ->
          check(
            "gateway.#{op.id}.rate_limit_declared",
            not is_nil(Map.get(op, :rate_limit)),
            "Operation #{op.id} must declare a rate limit policy"
          )
        end)

    suite_result("gateway", checks, start)
  end

  defp check_determinism_suite(%{adapter: adapter, fixture_dir: fixture_dir}) do
    case fixture_files(fixture_dir) do
      [] ->
        skipped_suite("determinism", "not_applicable: no_fixtures")

      files ->
        start = System.monotonic_time(:millisecond)
        checks = Enum.map(files, &fixture_check(adapter, &1))
        suite_result("determinism", checks, start)
    end
  end

  defp check_telemetry_suite(%{manifest: manifest}) do
    start = System.monotonic_time(:millisecond)

    telemetry_events = get_in(manifest.extensions, ["telemetry_events"]) || []

    event_checks =
      Enum.map(telemetry_events, fn event ->
        check(
          "telemetry.event_valid.#{event}",
          Telemetry.standard_event?(event),
          "Event #{event} is not part of the telemetry contract"
        )
      end)

    checks =
      [
        check(
          "telemetry.namespace_present",
          is_binary(manifest.telemetry_namespace) and
            String.starts_with?(manifest.telemetry_namespace, "jido.integration."),
          "Telemetry namespace must begin with jido.integration."
        )
      ] ++ event_checks

    suite_result("telemetry", checks, start)
  end

  defp check_compliance_suite(%{manifest: manifest}) do
    start = System.monotonic_time(:millisecond)

    error_checks =
      manifest.operations
      |> Enum.flat_map(fn op ->
        Enum.map(op.errors, fn error ->
          class = Map.get(error, "class", error[:class])
          retryability = Map.get(error, "retryability", error[:retryability])

          check(
            "compliance.#{op.id}.#{class}_retryability_matches_taxonomy",
            Error.valid_retryability?(to_string(class), to_string(retryability)),
            error_taxonomy_message(class, retryability)
          )
        end)
      end)

    checks =
      if error_checks == [] do
        [check("compliance.error_declarations_optional", true)]
      else
        error_checks
      end

    suite_result("compliance_minimum", checks, start)
  end

  defp check_distributed_correctness_suite(_context) do
    start = System.monotonic_time(:millisecond)

    checks = [
      check(
        "distributed_correctness.build_now_deferred",
        true,
        "Distributed correctness is deferred until a repo opts into distributed roles"
      )
    ]

    suite_result("distributed_correctness", checks, start)
  end

  defp check_artifact_transport_suite(_context) do
    start = System.monotonic_time(:millisecond)

    checks = [
      check(
        "artifact_transport.build_now_deferred",
        true,
        "Artifact transport checks are deferred until a repo opts into distributed roles"
      )
    ]

    suite_result("artifact_transport", checks, start)
  end

  defp check_policy_enforcement_suite(_context) do
    start = System.monotonic_time(:millisecond)

    checks = [
      check(
        "policy_enforcement.build_now_deferred",
        true,
        "Policy-enforcement conformance is deferred until a repo opts into distributed roles"
      )
    ]

    suite_result("policy_enforcement", checks, start)
  end

  defp fixture_check(adapter, fixture_file) do
    with {:ok, fixture} <- read_fixture(fixture_file),
         {:ok, result} <- execute_fixture(adapter, fixture),
         :ok <- compare_fixture_expectation(result, fixture) do
      check("determinism.#{Path.basename(fixture_file)}", true)
    else
      {:error, message} ->
        check("determinism.#{Path.basename(fixture_file)}", false, message)
    end
  end

  defp read_fixture(path) do
    case File.read(path) do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, fixture} when is_map(fixture) ->
            {:ok, fixture}

          {:ok, other} ->
            {:error, "Fixture #{Path.basename(path)} must decode to a map: #{inspect(other)}"}

          {:error, reason} ->
            {:error, "Fixture #{Path.basename(path)} is invalid JSON: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Fixture #{Path.basename(path)} could not be read: #{inspect(reason)}"}
    end
  end

  defp execute_fixture(adapter, fixture) do
    operation_id = fixture["operation_id"]
    args = Map.get(fixture, "input", %{})

    envelope = Envelope.new(operation_id, args)

    case Jido.Integration.Execution.execute(adapter, envelope) do
      {:ok, result} -> {:ok, result.result}
      {:error, error} -> {:error, Error.message(error)}
    end
  end

  defp compare_fixture_expectation(result, fixture) do
    cond do
      is_map(fixture["expected_output"]) ->
        compare_expected_map(result, fixture["expected_output"])

      is_map(fixture["expected"]) ->
        compare_expected_paths(result, fixture["expected"])

      true ->
        {:error, "Fixture must declare expected_output or expected"}
    end
  end

  defp compare_expected_map(result, expected) do
    if result == expected do
      :ok
    else
      {:error, "Expected #{inspect(expected)}, got #{inspect(result)}"}
    end
  end

  defp compare_expected_paths(result, expected) do
    case Enum.find(expected, fn {path, value} -> path_lookup(result, path) != value end) do
      nil ->
        :ok

      {path, value} ->
        {:error,
         "Expected #{path} == #{inspect(value)}, got #{inspect(path_lookup(result, path))}"}
    end
  end

  defp path_lookup(data, path) when is_binary(path) do
    path
    |> String.split(".")
    |> Enum.reduce_while(data, fn segment, acc ->
      value =
        cond do
          is_map(acc) and Map.has_key?(acc, segment) ->
            Map.get(acc, segment)

          (is_map(acc) and existing_atom_key(segment)) &&
              Map.has_key?(acc, existing_atom_key(segment)) ->
            Map.get(acc, existing_atom_key(segment))

          true ->
            :missing
        end

      if value == :missing, do: {:halt, nil}, else: {:cont, value}
    end)
  rescue
    ArgumentError -> nil
  end

  defp check(name, result, message \\ nil)

  defp check(name, true, _message) do
    %{name: name, status: :passed, message: nil}
  end

  defp check(name, false, message) do
    %{name: name, status: :failed, message: message || "Check failed"}
  end

  defp suite_result(suite_name, checks, start_time, reason \\ nil) do
    status =
      if Enum.all?(checks, &(&1.status == :passed)), do: :passed, else: :failed

    %{
      suite: suite_name,
      status: status,
      checks: checks,
      duration_ms: System.monotonic_time(:millisecond) - start_time,
      reason: reason
    }
  end

  defp skipped_suite(suite_name, reason) do
    %{suite: suite_name, status: :skipped, checks: [], duration_ms: 0, reason: reason}
  end

  defp error_taxonomy_message(class, retryability) do
    case safe_existing_atom(class) do
      nil ->
        "Unknown error class #{inspect(class)} with retryability #{inspect(retryability)}"

      class_atom ->
        "#{class} should have retryability #{Error.default_retryability(class_atom)} but got #{retryability}"
    end
  end

  defp security_id_check(adapter) do
    if function_exported?(adapter, :id, 0) do
      check("security.id_is_string", is_binary(adapter.id()))
    else
      check("security.id_is_string", true)
    end
  end

  defp fixture_files(nil), do: []

  defp fixture_files(path) do
    if File.dir?(path) do
      path
      |> Path.join("*.json")
      |> Path.wildcard()
      |> Enum.sort()
    else
      []
    end
  end

  defp evidence_refs(%{source_path: source_path, fixture_dir: fixture_dir}) do
    [source_path | fixture_files(fixture_dir)]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp module_source_path(module) do
    module.module_info(:compile)
    |> Keyword.get(:source)
    |> case do
      nil -> nil
      source when is_list(source) -> List.to_string(source)
      source -> source
    end
  end

  defp read_source(nil), do: ""

  defp read_source(source_path) do
    case File.read(source_path) do
      {:ok, source} -> source
      {:error, _} -> ""
    end
  end

  defp normalize_roles(roles) when is_list(roles), do: Enum.map(roles, &normalize_role/1)
  defp normalize_roles(_roles), do: [:connector]

  defp normalize_role(role) when is_atom(role), do: role

  defp normalize_role(role) when is_binary(role) do
    case role do
      "connector" -> :connector
      "dispatch_consumer" -> :dispatch_consumer
      "run_aggregator" -> :run_aggregator
      "control_plane" -> :control_plane
      _ -> :connector
    end
  end

  defp profile_includes?(profile, required_profile) do
    profile_rank(profile) >= profile_rank(required_profile)
  end

  defp profile_rank(:mvp_foundation), do: 0
  defp profile_rank(:bronze), do: 1
  defp profile_rank(:silver), do: 2
  defp profile_rank(:gold), do: 3

  defp profile_to_tier(:mvp_foundation), do: "bronze"
  defp profile_to_tier(:bronze), do: "bronze"
  defp profile_to_tier(:silver), do: "silver"
  defp profile_to_tier(:gold), do: "gold"

  defp runner_version do
    case Application.spec(:jido_integration, :vsn) do
      nil -> "0.1.0"
      version when is_list(version) -> List.to_string(version)
      version -> to_string(version)
    end
  end

  defp safe_existing_atom(value) when is_atom(value), do: value

  defp safe_existing_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end

  defp safe_existing_atom(_value), do: nil

  defp existing_atom_key(segment) do
    safe_existing_atom(segment)
  end

  defp call_suite(:check_manifest_suite, context), do: check_manifest_suite(context)
  defp call_suite(:check_operations_suite, context), do: check_operations_suite(context)
  defp call_suite(:check_triggers_suite, context), do: check_triggers_suite(context)
  defp call_suite(:check_auth_suite, context), do: check_auth_suite(context)
  defp call_suite(:check_security_suite, context), do: check_security_suite(context)
  defp call_suite(:check_gateway_suite, context), do: check_gateway_suite(context)
  defp call_suite(:check_determinism_suite, context), do: check_determinism_suite(context)
  defp call_suite(:check_telemetry_suite, context), do: check_telemetry_suite(context)
  defp call_suite(:check_compliance_suite, context), do: check_compliance_suite(context)

  defp call_suite(:check_distributed_correctness_suite, context),
    do: check_distributed_correctness_suite(context)

  defp call_suite(:check_artifact_transport_suite, context),
    do: check_artifact_transport_suite(context)

  defp call_suite(:check_policy_enforcement_suite, context),
    do: check_policy_enforcement_suite(context)
end
