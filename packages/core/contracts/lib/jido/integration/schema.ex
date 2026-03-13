defmodule Jido.Integration.Schema do
  @moduledoc """
  JSON schema validation helpers for control-plane contracts.
  """

  alias ExJsonSchema.Validator
  alias Jido.Integration.Error

  @doc """
  Validate data against a JSON schema.

  Returns `:ok` when the payload matches the schema, otherwise returns a
  normalized `Jido.Integration.Error`.
  """
  @spec validate(map() | boolean() | nil, term(), keyword()) :: :ok | {:error, Error.t()}
  def validate(schema, data, opts \\ [])

  def validate(nil, _data, _opts), do: :ok

  def validate(schema, data, opts) when is_map(schema) or is_boolean(schema) do
    message = Keyword.get(opts, :message, "Schema validation failed")
    class = Keyword.get(opts, :class, :invalid_request)
    code = Keyword.get(opts, :code)

    case Validator.validate(schema, data) do
      :ok ->
        :ok

      {:error, errors} ->
        {:error,
         Error.new(class, message,
           code: code,
           upstream_context: %{"schema_errors" => List.wrap(errors)}
         )}
    end
  end
end
