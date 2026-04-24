defmodule Jido.Integration.V2.AccessGraph do
  @moduledoc """
  Pure access graph helpers for `Platform.AccessGraph.v1`.
  """

  alias Jido.Integration.V2.AccessGraph.Edge
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.TenantScope

  @type effective_access_tuple :: %{
          optional(:access_agents) => [String.t()],
          optional(:access_resources) => [String.t()],
          optional(:access_scopes) => [String.t()],
          optional(:policy_refs) => [String.t()],
          optional(String.t()) => [String.t()]
        }

  @type authority_compile_view :: %{
          snapshot_epoch: pos_integer(),
          access_agents: MapSet.t(String.t()),
          access_resources: MapSet.t(String.t()),
          access_scopes: MapSet.t(String.t()),
          scope_resources: MapSet.t(String.t()),
          policy_refs: MapSet.t(String.t()),
          graph_admissible?: boolean()
        }

  @spec a_of([Edge.t()], String.t(), pos_integer()) :: MapSet.t(String.t())
  def a_of(edges, user_ref, epoch), do: tails_for(edges, :ua, user_ref, epoch)

  @spec r_of([Edge.t()], String.t(), pos_integer()) :: MapSet.t(String.t())
  def r_of(edges, agent_ref, epoch), do: tails_for(edges, :ar, agent_ref, epoch)

  @spec s_of([Edge.t()], String.t(), pos_integer()) :: MapSet.t(String.t())
  def s_of(edges, user_ref, epoch), do: tails_for(edges, :us, user_ref, epoch)

  @spec sr_of([Edge.t()], String.t(), pos_integer()) :: MapSet.t(String.t())
  def sr_of(edges, scope_ref, epoch), do: tails_for(edges, :sr, scope_ref, epoch)

  @spec up_of([Edge.t()], String.t(), pos_integer()) :: MapSet.t(String.t())
  def up_of(edges, user_ref, epoch), do: tails_for(edges, :up, user_ref, epoch)

  @spec authority_compile_view(
          [Edge.t()],
          String.t(),
          String.t(),
          pos_integer(),
          effective_access_tuple()
        ) :: authority_compile_view()
  def authority_compile_view(edges, user_ref, agent_ref, epoch, effective_access_tuple \\ %{}) do
    user_scopes = s_of(edges, user_ref, epoch)

    scope_resources =
      user_scopes
      |> Enum.flat_map(fn scope_ref -> sr_of(edges, scope_ref, epoch) end)
      |> MapSet.new()

    %{
      snapshot_epoch: epoch,
      access_agents: a_of(edges, user_ref, epoch),
      access_resources: r_of(edges, agent_ref, epoch),
      access_scopes: user_scopes,
      scope_resources: scope_resources,
      policy_refs: up_of(edges, user_ref, epoch),
      graph_admissible?:
        graph_admissible?(edges, effective_access_tuple, user_ref, agent_ref, epoch)
    }
  end

  @spec graph_admissible?(
          [Edge.t()],
          effective_access_tuple(),
          String.t(),
          String.t(),
          pos_integer()
        ) ::
          boolean()
  def graph_admissible?(edges, effective_access_tuple, user_ref, agent_ref, epoch) do
    agents = access_set(effective_access_tuple, :access_agents)
    resources = access_set(effective_access_tuple, :access_resources)
    scopes = access_set(effective_access_tuple, :access_scopes)
    policies = access_set(effective_access_tuple, :policy_refs)

    user_agents = a_of(edges, user_ref, epoch)
    agent_resources = r_of(edges, agent_ref, epoch)
    user_scopes = s_of(edges, user_ref, epoch)
    user_policies = up_of(edges, user_ref, epoch)

    MapSet.member?(user_agents, agent_ref) and
      MapSet.subset?(agents, user_agents) and
      MapSet.member?(agents, agent_ref) and
      MapSet.subset?(resources, agent_resources) and
      MapSet.size(MapSet.intersection(scopes, user_scopes)) > 0 and
      policy_refs_admissible?(effective_access_tuple, policies, user_policies)
  end

  @spec current_epoch(module(), String.t()) :: non_neg_integer()
  def current_epoch(store, tenant_ref) when is_atom(store) and is_binary(tenant_ref) do
    store.current_epoch(tenant_ref)
  end

  @spec epoch_at(module(), String.t(), DateTime.t()) :: non_neg_integer()
  def epoch_at(store, tenant_ref, %DateTime{} = committed_at)
      when is_atom(store) and is_binary(tenant_ref) do
    store.epoch_at(tenant_ref, committed_at)
  end

  @spec validate_scope_hierarchy!([{String.t(), String.t()}]) :: :ok
  def validate_scope_hierarchy!(edges) when is_list(edges) do
    adjacency =
      Enum.reduce(edges, %{}, fn {parent, child}, acc ->
        parent = Contracts.validate_non_empty_string!(parent, "scope_hierarchy.parent")
        child = Contracts.validate_non_empty_string!(child, "scope_hierarchy.child")
        Map.update(acc, parent, MapSet.new([child]), &MapSet.put(&1, child))
      end)

    case Enum.find(Map.keys(adjacency), &cycle_from?(&1, &1, adjacency, %{})) do
      nil -> :ok
      scope -> raise ArgumentError, "scope hierarchy cycle detected at #{scope}"
    end
  end

  def validate_scope_hierarchy!(edges) do
    raise ArgumentError, "scope_hierarchy_edges must be a list, got: #{inspect(edges)}"
  end

  @spec backfill_from_tenant_scope!(TenantScope.t() | map() | keyword(), keyword()) :: [Edge.t()]
  def backfill_from_tenant_scope!(tenant_scope, opts) when is_list(opts) do
    scope = TenantScope.new!(tenant_scope)
    tenant_ref = scope.tenant_id
    user_ref = user_ref!(scope, opts)
    agent_refs = required_string_list!(opts, :agent_refs)
    resource_refs = required_string_list!(opts, :resource_refs)
    scope_refs = required_string_list!(opts, :scope_refs)
    policy_refs = required_string_list!(opts, :policy_refs)
    authority_ref = Keyword.fetch!(opts, :granting_authority_ref)
    source_node_ref = Keyword.fetch!(opts, :source_node_ref)
    evidence_refs = Keyword.get(opts, :evidence_refs, [])
    epoch_start = Keyword.get(opts, :epoch_start, 1)

    build_backfill_edges(%{
      tenant_ref: tenant_ref,
      user_ref: user_ref,
      agent_refs: agent_refs,
      resource_refs: resource_refs,
      scope_refs: scope_refs,
      policy_refs: policy_refs,
      authority_ref: authority_ref,
      source_node_ref: source_node_ref,
      evidence_refs: evidence_refs,
      epoch_start: epoch_start
    })
  end

  defp build_backfill_edges(%{
         tenant_ref: tenant_ref,
         user_ref: user_ref,
         agent_refs: agent_refs,
         resource_refs: resource_refs,
         scope_refs: scope_refs,
         policy_refs: policy_refs,
         authority_ref: authority_ref,
         source_node_ref: source_node_ref,
         evidence_refs: evidence_refs,
         epoch_start: epoch_start
       }) do
    ua_edges = for agent_ref <- agent_refs, do: {:ua, user_ref, agent_ref}

    ar_edges =
      for agent_ref <- agent_refs,
          resource_ref <- resource_refs,
          do: {:ar, agent_ref, resource_ref}

    us_edges = for scope_ref <- scope_refs, do: {:us, user_ref, scope_ref}

    sr_edges =
      for scope_ref <- scope_refs,
          resource_ref <- resource_refs,
          do: {:sr, scope_ref, resource_ref}

    up_edges = for policy_ref <- policy_refs, do: {:up, user_ref, policy_ref}

    (ua_edges ++ ar_edges ++ us_edges ++ sr_edges ++ up_edges)
    |> Enum.map(fn {edge_type, head_ref, tail_ref} ->
      Edge.new!(%{
        edge_type: edge_type,
        head_ref: head_ref,
        tail_ref: tail_ref,
        tenant_ref: tenant_ref,
        source_node_ref: source_node_ref,
        epoch_start: epoch_start,
        granting_authority_ref: authority_ref,
        evidence_refs: evidence_refs,
        policy_refs: policy_refs,
        metadata: %{source: "tenant_scope_backfill"}
      })
    end)
  end

  defp tails_for(edges, edge_type, head_ref, epoch) do
    edges
    |> Enum.filter(&active_edge?(&1, edge_type, head_ref, epoch))
    |> Enum.map(& &1.tail_ref)
    |> MapSet.new()
  end

  defp active_edge?(%Edge{} = edge, edge_type, head_ref, epoch) do
    edge.edge_type == edge_type and edge.head_ref == head_ref and
      Edge.active_at_epoch?(edge, epoch)
  end

  defp active_edge?(_edge, _edge_type, _head_ref, _epoch), do: false

  defp access_set(tuple, key) when is_map(tuple) do
    tuple
    |> Contracts.get(key, [])
    |> Contracts.normalize_string_list!("effective_access_tuple.#{key}")
    |> MapSet.new()
  end

  defp policy_refs_admissible?(tuple, policies, user_policies) do
    if Map.has_key?(tuple, :policy_refs) or Map.has_key?(tuple, "policy_refs") do
      MapSet.size(policies) > 0 and MapSet.subset?(policies, user_policies)
    else
      true
    end
  end

  defp user_ref!(%TenantScope{actor_ref: actor_ref}, opts) do
    [Keyword.get(opts, :user_ref) | actor_ref_user_candidates(actor_ref)]
    |> Enum.find(&(is_binary(&1) and &1 != ""))
    |> case do
      nil -> raise ArgumentError, "tenant_scope backfill requires user_ref or actor_ref.user_ref"
      user_ref -> user_ref
    end
  end

  defp actor_ref_user_candidates(nil), do: []

  defp actor_ref_user_candidates(actor_ref) when is_map(actor_ref) do
    [
      Map.get(actor_ref, "user_ref"),
      Map.get(actor_ref, :user_ref),
      Map.get(actor_ref, "actor_id"),
      Map.get(actor_ref, :actor_id)
    ]
  end

  defp required_string_list!(opts, key) do
    opts
    |> Keyword.fetch!(key)
    |> Contracts.normalize_string_list!("tenant_scope_backfill.#{key}")
  end

  defp cycle_from?(node, current, adjacency, visited) do
    adjacency
    |> Map.get(current, MapSet.new())
    |> Enum.any?(fn child ->
      child == node or
        (not Map.has_key?(visited, child) and
           cycle_from?(node, child, adjacency, Map.put(visited, child, true)))
    end)
  end
end
