unless Code.ensure_loaded?(Jido.Integration.Build.WeldContract) do
  Code.require_file("weld_contract.exs", __DIR__)
end

Jido.Integration.Build.WeldContract.manifest()
