import Config

if config_env() == :test do
  config :jido_integration_v2_auth,
    credential_store: Jido.Integration.V2.StoreLocal.CredentialStore,
    lease_store: Jido.Integration.V2.StoreLocal.LeaseStore,
    connection_store: Jido.Integration.V2.StoreLocal.ConnectionStore,
    install_store: Jido.Integration.V2.StoreLocal.InstallStore

  config :jido_integration_v2_control_plane,
    run_store: Jido.Integration.V2.StoreLocal.RunStore,
    attempt_store: Jido.Integration.V2.StoreLocal.AttemptStore,
    event_store: Jido.Integration.V2.StoreLocal.EventStore,
    artifact_store: Jido.Integration.V2.StoreLocal.ArtifactStore,
    ingress_store: Jido.Integration.V2.StoreLocal.IngressStore,
    target_store: Jido.Integration.V2.StoreLocal.TargetStore
end
