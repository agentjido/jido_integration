defmodule Jido.Integration.Connectors.GitHub.DefaultClient do
  @moduledoc """
  Default HTTP client for the GitHub connector using `Req`.

  Falls back to a stub that returns `:unavailable` errors if Req
  is not available.
  """

  @doc "Perform a GET request."
  @spec get(String.t(), list()) :: {:ok, map()} | {:error, term()}
  def get(url, headers) do
    if Code.ensure_loaded?(Req) do
      case Req.get(url, headers: headers) do
        {:ok, %Req.Response{status: status, body: body}} ->
          {:ok, %{status: status, body: body}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :req_not_available}
    end
  end

  @doc "Perform a POST request."
  @spec post(String.t(), map(), list()) :: {:ok, map()} | {:error, term()}
  def post(url, body, headers) do
    if Code.ensure_loaded?(Req) do
      case Req.post(url, json: body, headers: headers) do
        {:ok, %Req.Response{status: status, body: resp_body}} ->
          {:ok, %{status: status, body: resp_body}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :req_not_available}
    end
  end

  @doc "Perform a PATCH request."
  @spec patch(String.t(), map(), list()) :: {:ok, map()} | {:error, term()}
  def patch(url, body, headers) do
    if Code.ensure_loaded?(Req) do
      case Req.patch(url, json: body, headers: headers) do
        {:ok, %Req.Response{status: status, body: resp_body}} ->
          {:ok, %{status: status, body: resp_body}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :req_not_available}
    end
  end
end
