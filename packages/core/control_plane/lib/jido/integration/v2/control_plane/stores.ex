defmodule Jido.Integration.V2.ControlPlane.Stores do
  @moduledoc false

  @default_run_store Jido.Integration.V2.ControlPlane.RunLedger
  @default_attempt_store Jido.Integration.V2.ControlPlane.RunLedger
  @default_event_store Jido.Integration.V2.ControlPlane.RunLedger
  @default_artifact_store Jido.Integration.V2.ControlPlane.RunLedger
  @default_target_store Jido.Integration.V2.ControlPlane.RunLedger
  @default_ingress_store Jido.Integration.V2.ControlPlane.RunLedger

  @spec run_store() :: module()
  def run_store do
    Application.get_env(:jido_integration_v2_control_plane, :run_store, @default_run_store)
  end

  @spec attempt_store() :: module()
  def attempt_store do
    Application.get_env(
      :jido_integration_v2_control_plane,
      :attempt_store,
      @default_attempt_store
    )
  end

  @spec event_store() :: module()
  def event_store do
    Application.get_env(:jido_integration_v2_control_plane, :event_store, @default_event_store)
  end

  @spec artifact_store() :: module()
  def artifact_store do
    Application.get_env(
      :jido_integration_v2_control_plane,
      :artifact_store,
      @default_artifact_store
    )
  end

  @spec target_store() :: module()
  def target_store do
    Application.get_env(:jido_integration_v2_control_plane, :target_store, @default_target_store)
  end

  @spec ingress_store() :: module()
  def ingress_store do
    Application.get_env(
      :jido_integration_v2_control_plane,
      :ingress_store,
      @default_ingress_store
    )
  end
end
