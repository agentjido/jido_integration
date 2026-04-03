defmodule Jido.Integration.V2.Connectors.LinearTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.Connectors.Linear
  alias Jido.Integration.V2.Connectors.Linear.Fixtures
  alias Jido.Integration.V2.Connectors.Linear.Operation
  alias Jido.Integration.V2.Connectors.Linear.OperationCatalog
  alias Jido.Integration.V2.ConsumerProjection
  alias Jido.Integration.V2.OperationSpec

  @published_capability_ids [
    "linear.comments.create",
    "linear.issues.list",
    "linear.issues.retrieve",
    "linear.issues.update",
    "linear.users.get_self"
  ]
  @normalized_surface_expectations %{
    "linear.comments.create" => {"comment.create", "comment_create"},
    "linear.issues.list" => {"work_item.list", "work_item_list"},
    "linear.issues.retrieve" => {"work_item.fetch", "work_item_fetch"},
    "linear.issues.update" => {"work_item.update", "work_item_update"},
    "linear.users.get_self" => {"users.get_self", "users_get_self"}
  }
  @permission_expectations %{
    "linear.comments.create" => ["write"],
    "linear.issues.list" => ["read"],
    "linear.issues.retrieve" => ["read"],
    "linear.issues.update" => ["write"],
    "linear.users.get_self" => ["read"]
  }

  test "publishes the A0 direct catalog slice as authored operation specs plus derived capabilities" do
    manifest = Linear.manifest()

    assert manifest.connector == "linear"
    assert manifest.auth.binding_kind == :connection_id
    assert manifest.auth.auth_type == :api_token
    assert manifest.auth.default_profile == "api_key_user"
    assert manifest.auth.management_modes == [:external_secret, :hosted, :manual]
    assert manifest.auth.requested_scopes == ["read", "write"]
    assert manifest.auth.durable_secret_fields == ["access_token", "api_key", "refresh_token"]
    assert manifest.auth.lease_fields == ["access_token", "api_key"]
    assert manifest.auth.secret_names == []
    assert manifest.catalog.display_name == "Linear"
    assert manifest.catalog.publication == :public
    assert manifest.runtime_families == [:direct]
    assert manifest.metadata.provider_sdk == :linear_sdk
    assert manifest.metadata.published_slice == :a0_issue_workflows

    assert manifest.auth.install == %{
             required: true,
             profiles: ["api_key_user", "oauth_user"],
             hosted_callback_supported: true,
             callback_route_kind: "oauth_callback",
             state_required: true,
             pkce_supported: true,
             expires_in_seconds: nil,
             metadata: %{
               completion_modes: [:hosted_callback, :manual_callback],
               approval_by_profile: %{
                 api_key_user: :manual_token_entry,
                 oauth_user: :browser_oauth
               }
             }
           }

    assert manifest.auth.reauth == %{
             supported: true,
             profiles: ["oauth_user"],
             hosted_callback_supported: true,
             state_required: true,
             pkce_supported: true,
             metadata: %{reuse_install_path: true}
           }

    assert Enum.map(manifest.auth.supported_profiles, & &1.id) == [
             "api_key_user",
             "oauth_user"
           ]

    api_key_profile = Enum.find(manifest.auth.supported_profiles, &(&1.id == "api_key_user"))

    assert api_key_profile.auth_type == :api_token
    assert api_key_profile.subject_kind == :user
    assert api_key_profile.install_required == true
    assert api_key_profile.grant_types == [:manual_token]
    assert api_key_profile.callback_required == false
    assert api_key_profile.refresh_supported == false
    assert api_key_profile.reauth_supported == false
    assert api_key_profile.external_secret_supported == true
    assert api_key_profile.durable_secret_fields == ["api_key"]
    assert api_key_profile.lease_fields == ["api_key"]
    assert api_key_profile.management_modes == [:external_secret, :manual]
    assert api_key_profile.required_scopes == ["read", "write"]

    oauth_profile = Enum.find(manifest.auth.supported_profiles, &(&1.id == "oauth_user"))

    assert oauth_profile.auth_type == :oauth2
    assert oauth_profile.subject_kind == :user
    assert oauth_profile.install_required == true
    assert oauth_profile.grant_types == [:authorization_code, :refresh_token]
    assert oauth_profile.callback_required == true
    assert oauth_profile.pkce_required == true
    assert oauth_profile.refresh_supported == true
    assert oauth_profile.reauth_supported == true
    assert oauth_profile.external_secret_supported == true
    assert oauth_profile.durable_secret_fields == ["access_token", "refresh_token"]
    assert oauth_profile.lease_fields == ["access_token"]
    assert oauth_profile.management_modes == [:external_secret, :hosted, :manual]
    assert oauth_profile.required_scopes == ["read", "write"]

    assert manifest.triggers == []

    assert Enum.map(manifest.operations, & &1.operation_id) ==
             @published_capability_ids

    assert Enum.map(manifest.capabilities, & &1.id) == Enum.sort(@published_capability_ids)

    Enum.each(manifest.capabilities, fn capability ->
      assert capability.runtime_class == :direct
      assert capability.kind == :operation
      assert capability.transport_profile == :sdk
      assert capability.handler == Operation
      assert capability.metadata.document |> is_binary()
      assert capability.metadata.operation_name |> is_binary()

      assert capability.metadata.required_scopes ==
               Map.fetch!(@permission_expectations, capability.id)

      assert capability.metadata.permission_bundle ==
               Map.fetch!(@permission_expectations, capability.id)

      assert capability.metadata.input_schema |> is_struct()
      assert capability.metadata.output_schema |> is_struct()
      assert capability.metadata.rollout_phase == :a0
      assert capability.metadata.event_type |> is_binary()
      assert capability.metadata.failure_event_type |> is_binary()
      assert capability.metadata.artifact_slug |> is_binary()
      assert capability.metadata.jido.action.name |> is_binary()
      assert capability.metadata.policy.environment.allowed == [:prod, :staging]
      assert capability.metadata.policy.sandbox.level == :standard
      assert capability.metadata.policy.sandbox.egress == :restricted
      assert capability.metadata.policy.sandbox.approvals == :auto

      assert capability.metadata.policy.sandbox.allowed_tools == [
               String.replace(capability.id, "linear.", "linear.api.")
             ]
    end)

    Enum.each(manifest.operations, fn operation ->
      {normalized_id, action_name} =
        Map.fetch!(@normalized_surface_expectations, operation.operation_id)

      assert operation.consumer_surface.mode == :common
      assert operation.consumer_surface.normalized_id == normalized_id
      assert operation.consumer_surface.action_name == action_name
      assert operation.schema_policy.input == :defined
      assert operation.schema_policy.output == :defined
    end)
  end

  test "authors the A0 slice as rich operation specs and derives the executable catalog from them" do
    operations = OperationCatalog.published_operations()
    entries = OperationCatalog.entries()

    assert Enum.all?(operations, &match?(%OperationSpec{}, &1))
    assert Enum.map(operations, & &1.operation_id) == @published_capability_ids

    assert Enum.map(OperationCatalog.published_entries(), & &1.operation_id) ==
             @published_capability_ids

    assert Enum.all?(entries, & &1.published?)

    Enum.each(Fixtures.specs(), fn spec ->
      operation = OperationCatalog.fetch_operation!(spec.capability_id)

      assert {:ok, _parsed_input} = Zoi.parse(operation.input_schema, spec.input)
      assert {:ok, _parsed_output} = Zoi.parse(operation.output_schema, spec.output)
      assert is_binary(operation.display_name)
      refute operation.description =~ "Scaffolded"
    end)

    assert {:error, _reason} =
             Zoi.parse(
               OperationCatalog.fetch_operation!("linear.issues.retrieve").input_schema,
               %{}
             )

    assert {:error, _reason} =
             Zoi.parse(
               OperationCatalog.fetch_operation!("linear.comments.create").input_schema,
               %{issue_id: "lin-issue-321"}
             )

    plugin_module = ConsumerProjection.plugin_module(Linear)
    assert Code.ensure_loaded?(plugin_module)
    assert plugin_module.subscriptions() == []

    refute Enum.any?(operations, &String.contains?(&1.operation_id, "install_binding"))
  end
end
