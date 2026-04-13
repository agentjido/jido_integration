defmodule Jido.Integration.V2.ExecutionGovernanceProjection.Verifier do
  @moduledoc """
  Verifies that supplied operational shadow sections still match the Spine compiler.
  """

  alias Jido.Integration.V2.CanonicalJson
  alias Jido.Integration.V2.ExecutionGovernanceProjection
  alias Jido.Integration.V2.ExecutionGovernanceProjection.Compiler

  @spec verify(
          ExecutionGovernanceProjection.t(),
          map(),
          map(),
          map()
        ) :: :ok | {:error, :projection_mismatch, map()}
  def verify(
        %ExecutionGovernanceProjection{} = projection,
        gateway_request,
        runtime_request,
        boundary_request
      ) do
    expected =
      projection
      |> Compiler.compile!()
      |> CanonicalJson.normalize!()

    supplied = %{
      gateway_request: CanonicalJson.normalize!(gateway_request),
      runtime_request: CanonicalJson.normalize!(runtime_request),
      boundary_request: CanonicalJson.normalize!(boundary_request)
    }

    supplied = CanonicalJson.normalize!(supplied)

    if CanonicalJson.encode!(supplied) == CanonicalJson.encode!(expected) do
      :ok
    else
      {:error, :projection_mismatch, %{expected: expected, supplied: supplied}}
    end
  end

  @spec verify!(
          ExecutionGovernanceProjection.t(),
          map(),
          map(),
          map()
        ) :: :ok
  def verify!(
        %ExecutionGovernanceProjection{} = projection,
        gateway_request,
        runtime_request,
        boundary_request
      ) do
    case verify(projection, gateway_request, runtime_request, boundary_request) do
      :ok ->
        :ok

      {:error, :projection_mismatch, details} ->
        raise ArgumentError,
              "execution governance projection mismatch: #{inspect(details, pretty: true)}"
    end
  end
end
