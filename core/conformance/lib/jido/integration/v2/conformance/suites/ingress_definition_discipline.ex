defmodule Jido.Integration.V2.Conformance.Suites.IngressDefinitionDiscipline do
  @moduledoc false

  alias Jido.Integration.V2.Conformance.CheckResult
  alias Jido.Integration.V2.Conformance.SuiteResult
  alias Jido.Integration.V2.Conformance.SuiteSupport
  alias Jido.Integration.V2.Ingress.Definition

  @spec run(map()) :: SuiteResult.t()
  def run(%{manifest: manifest, ingress_definitions: raw_definitions}) do
    trigger_capabilities = Enum.filter(manifest.capabilities, &trigger_capability?/1)

    case trigger_capabilities do
      [] ->
        SuiteResult.skip(
          :ingress_definition_discipline,
          "connector publishes no ingress-trigger capabilities"
        )

      _ ->
        checks = ingress_checks(trigger_capabilities, manifest.connector, raw_definitions)

        SuiteResult.from_checks(
          :ingress_definition_discipline,
          checks,
          "Trigger capabilities declare explicit ingress definitions"
        )
    end
  end

  defp ingress_checks(trigger_capabilities, connector_id, raw_definitions) do
    case normalize_definitions(raw_definitions) do
      {:ok, []} ->
        [
          CheckResult.fail(
            "ingress.definitions.present",
            "trigger capabilities require ingress_definitions/0 evidence"
          )
        ]

      {:ok, definitions} ->
        capability_ids = Enum.map(trigger_capabilities, & &1.id)

        unknown_definition_checks =
          definitions
          |> Enum.reject(&(&1.capability_id in capability_ids))
          |> Enum.map(fn definition ->
            CheckResult.fail(
              "ingress.#{definition.capability_id}.known_capability",
              "ingress definition references an unknown trigger capability"
            )
          end)

        per_capability_checks =
          Enum.flat_map(trigger_capabilities, fn capability ->
            matching = Enum.filter(definitions, &(&1.capability_id == capability.id))

            [
              SuiteSupport.check(
                "ingress.#{capability.id}.definition_present",
                length(matching) == 1,
                "trigger capabilities must have exactly one matching ingress definition"
              )
            ] ++
              matching_definition_checks(matching, capability, connector_id)
          end)

        unknown_definition_checks ++ per_capability_checks

      {:error, message} ->
        [
          CheckResult.fail("ingress.definitions.shape", message)
        ]
    end
  end

  defp matching_definition_checks([], _capability, _connector_id), do: []

  defp matching_definition_checks([definition | _rest], capability, connector_id) do
    [
      SuiteSupport.check(
        "ingress.#{capability.id}.connector_id",
        definition.connector_id == connector_id,
        "ingress definition connector_id must match manifest.connector"
      )
    ] ++ transport_checks(definition, capability.transport_profile, capability.id)
  end

  defp transport_checks(definition, :webhook, capability_id) do
    [
      SuiteSupport.check(
        "ingress.#{capability_id}.source",
        definition.source == :webhook,
        "webhook trigger capabilities must use Definition.source == :webhook"
      ),
      SuiteSupport.check(
        "ingress.#{capability_id}.verification",
        not is_nil(definition.verification),
        "webhook trigger capabilities must declare signature verification"
      )
    ]
  end

  defp transport_checks(definition, :poll, capability_id) do
    [
      SuiteSupport.check(
        "ingress.#{capability_id}.source",
        definition.source == :poll,
        "poll trigger capabilities must use Definition.source == :poll"
      )
    ]
  end

  defp transport_checks(_definition, _transport_profile, _capability_id), do: []

  defp normalize_definitions(definitions) when is_list(definitions) do
    {:ok, Enum.map(definitions, &normalize_definition!/1)}
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp normalize_definitions(_definitions), do: {:error, "ingress_definitions must be a list"}

  defp normalize_definition!(definition) when is_map(definition) do
    if Map.get(definition, :__struct__) == Definition do
      definition
    else
      Definition.new!(definition)
    end
  end

  defp trigger_capability?(capability) do
    capability.kind == :trigger or capability.transport_profile in [:webhook, :poll]
  end
end
