defmodule Jido.Integration.V2.Connectors.Linear.Build.DependencyResolver do
  @moduledoc false

  def linear_sdk(opts \\ []) do
    {:linear_sdk, "~> 0.2.0", opts}
  end

  def prismatic(opts \\ []) do
    {:prismatic, "~> 0.2.0", opts}
  end
end
