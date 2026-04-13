# `Jido.Integration.V2.Auth`

Durable connection/install truth plus short-lived credential leases.

# `connection_binding`

```elixir
@type connection_binding() :: %{
  connection: Jido.Integration.V2.Auth.Connection.t(),
  credential_ref: Jido.Integration.V2.CredentialRef.t(),
  credential: Jido.Integration.V2.Credential.t()
}
```

# `external_secret_opts`

```elixir
@type external_secret_opts() :: %{
  stage: external_secret_stage(),
  requested_fields: [String.t()],
  missing_fields: [String.t()],
  now: DateTime.t()
}
```

# `external_secret_resolver`

```elixir
@type external_secret_resolver() :: (Jido.Integration.V2.Auth.Connection.t(),
                               Jido.Integration.V2.Credential.t(),
                               external_secret_opts() -&gt;
                                 {:ok, map()} | {:error, term()})
```

# `external_secret_stage`

```elixir
@type external_secret_stage() :: :lease | :fetch_lease | :refresh
```

# `refresh_handler`

```elixir
@type refresh_handler() :: (Jido.Integration.V2.Auth.Connection.t(),
                      Jido.Integration.V2.Credential.t() -&gt;
                        {:ok,
                         %{
                           optional(:secret) =&gt; map(),
                           optional(:expires_at) =&gt; DateTime.t() | nil,
                           optional(:refresh_token_expires_at) =&gt;
                             DateTime.t() | nil,
                           optional(:lease_fields) =&gt; [String.t()],
                           optional(:metadata) =&gt; map(),
                           optional(:source_ref) =&gt; map()
                         }}
                        | {:error, term()})
```

# `cancel_install`

```elixir
@spec cancel_install(String.t(), map()) ::
  {:ok,
   %{
     install: Jido.Integration.V2.Auth.Install.t(),
     connection: Jido.Integration.V2.Auth.Connection.t()
   }}
  | {:error, term()}
```

# `complete_install`

```elixir
@spec complete_install(String.t(), map()) ::
  {:ok,
   %{
     install: Jido.Integration.V2.Auth.Install.t(),
     connection: Jido.Integration.V2.Auth.Connection.t(),
     credential_ref: Jido.Integration.V2.CredentialRef.t()
   }}
  | {:error, term()}
```

# `connection_status`

```elixir
@spec connection_status(String.t()) ::
  {:ok, Jido.Integration.V2.Auth.Connection.t()} | {:error, :unknown_connection}
```

# `connections`

```elixir
@spec connections(map()) :: [Jido.Integration.V2.Auth.Connection.t()]
```

# `expire_install`

```elixir
@spec expire_install(String.t(), map()) ::
  {:ok,
   %{
     install: Jido.Integration.V2.Auth.Install.t(),
     connection: Jido.Integration.V2.Auth.Connection.t()
   }}
  | {:error, term()}
```

# `fail_install`

```elixir
@spec fail_install(String.t(), map()) ::
  {:ok,
   %{
     install: Jido.Integration.V2.Auth.Install.t(),
     connection: Jido.Integration.V2.Auth.Connection.t()
   }}
  | {:error, term()}
```

# `fetch_install`

```elixir
@spec fetch_install(String.t()) ::
  {:ok, Jido.Integration.V2.Auth.Install.t()} | {:error, :unknown_install}
```

# `fetch_lease`

```elixir
@spec fetch_lease(String.t(), map()) ::
  {:ok, Jido.Integration.V2.CredentialLease.t()}
  | {:error,
     :unknown_lease
     | :expired_lease
     | :unknown_credential
     | :connection_revoked
     | :reauth_required
     | :external_secret_unavailable
     | {:missing_lease_fields, [String.t()]}}
```

# `installs`

```elixir
@spec installs(map()) :: [Jido.Integration.V2.Auth.Install.t()]
```

# `issue_lease`

```elixir
@spec issue_lease(Jido.Integration.V2.CredentialRef.t(), map()) ::
  {:ok, Jido.Integration.V2.CredentialLease.t()}
  | {:error,
     :unknown_connection
     | :unknown_credential
     | :credential_subject_mismatch
     | :credential_expired
     | :connection_installing
     | :connection_disabled
     | :connection_revoked
     | :reauth_required
     | :external_secret_unavailable
     | {:missing_connection_scopes, [String.t()]}
     | {:missing_lease_fields, [String.t()]}}
```

# `reauthorize_connection`

```elixir
@spec reauthorize_connection(String.t(), map()) ::
  {:ok,
   %{
     install: Jido.Integration.V2.Auth.Install.t(),
     connection: Jido.Integration.V2.Auth.Connection.t(),
     session_state: map()
   }}
  | {:error, term()}
```

# `request_lease`

```elixir
@spec request_lease(String.t(), map()) ::
  {:ok, Jido.Integration.V2.CredentialLease.t()}
  | {:error,
     :unknown_connection
     | :unknown_credential
     | :credential_expired
     | :connection_installing
     | :connection_disabled
     | :connection_revoked
     | :reauth_required
     | :external_secret_unavailable
     | :expired_lease
     | {:missing_connection_scopes, [String.t()]}
     | {:missing_lease_fields, [String.t()]}}
```

# `reset!`

```elixir
@spec reset!() :: :ok
```

# `resolve`

```elixir
@spec resolve(Jido.Integration.V2.CredentialRef.t(), map()) ::
  {:ok, Jido.Integration.V2.Credential.t()}
  | {:error, :unknown_credential | :credential_subject_mismatch}
```

# `resolve_connection_binding`

```elixir
@spec resolve_connection_binding(String.t(), map()) ::
  {:ok, connection_binding()}
  | {:error,
     :unknown_connection
     | :unknown_credential
     | :credential_subject_mismatch
     | :credential_expired
     | :connection_installing
     | :connection_disabled
     | :connection_revoked
     | :reauth_required}
```

# `resolve_install_callback`

```elixir
@spec resolve_install_callback(map()) ::
  {:ok,
   %{
     install: Jido.Integration.V2.Auth.Install.t(),
     connection: Jido.Integration.V2.Auth.Connection.t()
   }}
  | {:error,
     :callback_locator_required
     | :unknown_install
     | :ambiguous_install
     | :install_expired
     | :callback_already_consumed
     | :invalid_callback_state
     | :invalid_callback_token
     | :pkce_verifier_required
     | :invalid_pkce_verifier
     | {:callback_error, term()}
     | term()}
```

# `resolve_secret`

```elixir
@spec resolve_secret(Jido.Integration.V2.CredentialRef.t(), String.t() | atom()) ::
  {:ok, term()}
  | {:error,
     :unknown_credential | :credential_subject_mismatch | :unknown_secret}
```

# `revoke_connection`

```elixir
@spec revoke_connection(String.t(), map()) ::
  {:ok, Jido.Integration.V2.Auth.Connection.t()} | {:error, term()}
```

# `rotate_connection`

```elixir
@spec rotate_connection(String.t(), map()) ::
  {:ok,
   %{
     connection: Jido.Integration.V2.Auth.Connection.t(),
     credential_ref: Jido.Integration.V2.CredentialRef.t()
   }}
  | {:error, term()}
```

# `set_external_secret_resolver`

```elixir
@spec set_external_secret_resolver(external_secret_resolver() | nil) :: :ok
```

# `set_refresh_handler`

```elixir
@spec set_refresh_handler(refresh_handler() | nil) :: :ok
```

# `start_install`

```elixir
@spec start_install(String.t(), String.t(), map()) ::
  {:ok,
   %{
     install: Jido.Integration.V2.Auth.Install.t(),
     connection: Jido.Integration.V2.Auth.Connection.t(),
     session_state: map()
   }}
  | {:error, term()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
