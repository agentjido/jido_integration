defmodule Jido.Integration.V2.StorePostgres.TargetStore do
  @moduledoc false

  @behaviour Jido.Integration.V2.ControlPlane.TargetStore

  import Ecto.Query

  alias Jido.Integration.V2.StorePostgres.Repo
  alias Jido.Integration.V2.StorePostgres.Schemas.TargetRecord
  alias Jido.Integration.V2.StorePostgres.Serialization
  alias Jido.Integration.V2.TargetDescriptor

  @impl true
  def put_target_descriptor(%TargetDescriptor{} = descriptor) do
    descriptor
    |> to_record_attrs()
    |> then(&TargetRecord.changeset(%TargetRecord{}, &1))
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:target_id, :inserted_at]},
      conflict_target: [:target_id]
    )
    |> case do
      {:ok, _record} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl true
  def fetch_target_descriptor(target_id) do
    case Repo.get(TargetRecord, target_id) do
      nil -> :error
      record -> {:ok, to_contract(record)}
    end
  end

  @impl true
  def list_target_descriptors do
    from(target in TargetRecord, order_by: [asc: target.target_id])
    |> Repo.all()
    |> Enum.map(&to_contract/1)
  end

  def reset! do
    Jido.Integration.V2.StorePostgres.ensure_started!()
    Repo.delete_all(TargetRecord)
    :ok
  end

  defp to_record_attrs(%TargetDescriptor{} = descriptor) do
    %{
      target_id: descriptor.target_id,
      capability_id: descriptor.capability_id,
      runtime_class: descriptor.runtime_class,
      version: descriptor.version,
      features: Serialization.dump(descriptor.features),
      constraints: Serialization.dump(descriptor.constraints),
      health: descriptor.health,
      location: Serialization.dump(descriptor.location),
      extensions: Serialization.dump(descriptor.extensions)
    }
  end

  defp to_contract(record) do
    TargetDescriptor.new!(%{
      target_id: record.target_id,
      capability_id: record.capability_id,
      runtime_class: record.runtime_class,
      version: record.version,
      features: Serialization.load(record.features || %{}),
      constraints: Serialization.load(record.constraints || %{}),
      health: record.health,
      location: Serialization.load(record.location || %{}),
      extensions: Serialization.load(record.extensions || %{})
    })
  end
end
