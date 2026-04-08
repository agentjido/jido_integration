defmodule Jido.Integration.V2.StorePostgres.CredentialStore do
  @moduledoc false

  @behaviour Jido.Integration.V2.Auth.CredentialStore

  alias Jido.Integration.V2.Auth.SecretEnvelope
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Credential
  alias Jido.Integration.V2.StorePostgres
  alias Jido.Integration.V2.StorePostgres.Repo
  alias Jido.Integration.V2.StorePostgres.Schemas.CredentialRecord
  alias Jido.Integration.V2.StorePostgres.Serialization

  @impl true
  def store_credential(%Credential{} = credential) do
    credential
    |> to_record_attrs()
    |> then(&CredentialRecord.changeset(%CredentialRecord{}, &1))
    |> Repo.insert(
      on_conflict:
        {:replace,
         [
           :credential_ref_id,
           :connection_id,
           :profile_id,
           :subject,
           :auth_type,
           :version,
           :scopes,
           :lease_fields,
           :secret_envelope,
           :expires_at,
           :refresh_token_expires_at,
           :source,
           :source_ref,
           :supersedes_credential_id,
           :revoked_at,
           :metadata,
           :updated_at
         ]},
      conflict_target: [:id]
    )
    |> case do
      {:ok, _record} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl true
  def fetch_credential(id) do
    case Repo.get(CredentialRecord, id) do
      nil ->
        {:error, :unknown_credential}

      record ->
        {:ok,
         Credential.new!(%{
           id: record.id,
           credential_ref_id: record.credential_ref_id,
           connection_id: record.connection_id,
           profile_id: record.profile_id,
           subject: record.subject,
           auth_type: normalize_auth_type(record.auth_type),
           version: record.version || 1,
           scopes: record.scopes || [],
           lease_fields: record.lease_fields || [],
           secret: SecretEnvelope.decrypt(record.secret_envelope || %{}, record.id),
           expires_at: record.expires_at,
           refresh_token_expires_at: record.refresh_token_expires_at,
           source: normalize_optional_atom(record.source),
           source_ref: load_optional_map(record.source_ref),
           supersedes_credential_id: record.supersedes_credential_id,
           revoked_at: record.revoked_at,
           metadata: Serialization.load(record.metadata || %{})
         })}
    end
  end

  def reset! do
    StorePostgres.ensure_started!()
    Repo.delete_all(CredentialRecord)
    :ok
  end

  defp to_record_attrs(%Credential{} = credential) do
    timestamp = Contracts.now()

    %{
      id: credential.id,
      credential_ref_id: credential.credential_ref_id,
      connection_id: credential.connection_id,
      profile_id: credential.profile_id,
      subject: credential.subject,
      auth_type: Atom.to_string(credential.auth_type),
      version: credential.version,
      scopes: credential.scopes,
      lease_fields: credential.lease_fields,
      secret_envelope: SecretEnvelope.encrypt(credential.secret, credential.id),
      expires_at: credential.expires_at,
      refresh_token_expires_at: credential.refresh_token_expires_at,
      source: dump_optional_atom(credential.source),
      source_ref: dump_optional_map(credential.source_ref),
      supersedes_credential_id: credential.supersedes_credential_id,
      revoked_at: credential.revoked_at,
      metadata: Serialization.dump(credential.metadata),
      inserted_at: timestamp,
      updated_at: timestamp
    }
  end

  defp normalize_auth_type(nil), do: :oauth2

  defp normalize_auth_type(auth_type) when is_binary(auth_type),
    do: String.to_existing_atom(auth_type)

  defp normalize_auth_type(auth_type), do: auth_type

  defp normalize_optional_atom(nil), do: nil
  defp normalize_optional_atom(value) when is_binary(value), do: String.to_existing_atom(value)

  defp dump_optional_atom(nil), do: nil
  defp dump_optional_atom(value) when is_atom(value), do: Atom.to_string(value)

  defp dump_optional_map(nil), do: nil
  defp dump_optional_map(value), do: Serialization.dump(value)

  defp load_optional_map(nil), do: nil
  defp load_optional_map(value), do: Serialization.load(value)
end
