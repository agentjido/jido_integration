defmodule Jido.Integration.V2.Schema do
  @moduledoc false

  @spec new(module(), Zoi.schema(), map() | keyword() | struct()) ::
          {:ok, struct()} | {:error, Exception.t()}
  def new(module, schema, attrs) when is_map(attrs) do
    parse(module, schema, attrs)
  end

  def new(module, schema, attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs) do
      parse(module, schema, Map.new(attrs))
    else
      {:error,
       ArgumentError.exception(
         "#{inspect(module)} attrs must be a map, struct, or keyword list, got: #{inspect(attrs)}"
       )}
    end
  end

  def new(module, _schema, attrs) when is_atom(module) do
    {:error,
     ArgumentError.exception(
       "#{inspect(module)} attrs must be a map, struct, or keyword list, got: #{inspect(attrs)}"
     )}
  end

  @spec new!(module(), Zoi.schema(), map() | keyword() | struct()) :: struct()
  def new!(module, schema, attrs) when is_atom(module) do
    case new(module, schema, attrs) do
      {:ok, value} ->
        value

      {:error, %ArgumentError{} = error} ->
        raise error
    end
  end

  @spec refine_new(
          {:ok, struct()} | {:error, Exception.t()},
          (struct() -> :ok | {:ok, struct()} | {:error, Exception.t()})
        ) :: {:ok, struct()} | {:error, Exception.t()}
  def refine_new({:ok, value}, fun) when is_function(fun, 1) do
    case fun.(value) do
      :ok -> {:ok, value}
      {:ok, refined_value} -> {:ok, refined_value}
      {:error, %ArgumentError{} = error} -> {:error, error}
    end
  end

  def refine_new({:error, %ArgumentError{} = error}, _fun), do: {:error, error}

  @spec parse(module(), Zoi.schema(), map() | struct()) ::
          {:ok, struct()} | {:error, Exception.t()}
  def parse(module, schema, attrs) when is_atom(module) do
    case Zoi.parse(schema, attrs) do
      {:ok, value} ->
        {:ok, value}

      {:error, errors} ->
        {:error,
         ArgumentError.exception(
           "invalid #{inspect(module)}:\n\n#{String.trim(Zoi.prettify_errors(errors))}"
         )}
    end
  end
end
