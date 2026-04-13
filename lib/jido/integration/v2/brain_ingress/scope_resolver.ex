defmodule Jido.Integration.V2.BrainIngress.ScopeResolver do
  @moduledoc """
  Resolves logical workspace references into concrete runtime paths.
  """

  @callback resolve(String.t() | nil, String.t() | nil, keyword()) ::
              {:ok, %{workspace_root: String.t() | nil, file_scope: String.t() | nil}}
              | {:error, {:scope_unresolvable, String.t() | nil}}
end
