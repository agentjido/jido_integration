defmodule Jido.Integration.Env do
  @moduledoc false

  @app :jido_integration_workspace
  @key :env

  @spec all(map() | keyword()) :: %{optional(String.t()) => String.t()}
  def all(overrides \\ %{}) do
    configured()
    |> Map.merge(normalize(overrides))
  end

  @spec get(String.t(), map() | keyword() | nil) :: String.t() | nil
  def get(key, env \\ nil)
  def get(key, nil) when is_binary(key), do: Map.get(all(), key)
  def get(key, env) when is_binary(key), do: Map.get(all(env), key)

  @spec configured() :: %{optional(String.t()) => String.t()}
  def configured do
    @app
    |> Application.get_env(@key, %{})
    |> normalize()
  end

  @spec normalize(map() | keyword() | nil) :: %{optional(String.t()) => String.t()}
  def normalize(env) when is_map(env) do
    env
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new(fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  def normalize(env) when is_list(env) do
    env
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new(fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  def normalize(_env), do: %{}
end
