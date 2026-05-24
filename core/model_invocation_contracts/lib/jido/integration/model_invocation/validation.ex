defmodule Jido.Integration.ModelInvocation.Validation do
  @moduledoc false

  alias Jido.Integration.V2.Contracts

  @blocked_keys ~w(
    api_key authorization body content credential credentials messages prompt
    provider_payload raw raw_messages raw_prompt raw_provider_payload secret
    secrets token
  )

  @spec attrs_map(map() | keyword() | struct()) :: map()
  def attrs_map(%_{} = value), do: Map.from_struct(value)
  def attrs_map(attrs) when is_map(attrs), do: attrs

  def attrs_map(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs) do
      Map.new(attrs)
    else
      raise ArgumentError, "attrs must be a keyword list, got: #{inspect(attrs)}"
    end
  end

  def attrs_map(attrs) do
    raise ArgumentError, "attrs must be a map, struct, or keyword list, got: #{inspect(attrs)}"
  end

  @spec required_string!(map(), atom(), String.t()) :: String.t()
  def required_string!(attrs, key, field_name) do
    attrs
    |> Contracts.fetch_required!(key, field_name)
    |> Contracts.validate_non_empty_string!(field_name)
  end

  @spec optional_string!(map(), atom(), String.t()) :: String.t() | nil
  def optional_string!(attrs, key, field_name) do
    case Contracts.get(attrs, key) do
      nil -> nil
      value -> Contracts.validate_non_empty_string!(value, field_name)
    end
  end

  @spec required_map!(map(), atom(), String.t()) :: map()
  def required_map!(attrs, key, field_name) do
    attrs
    |> Contracts.fetch_required!(key, field_name)
    |> map!(field_name)
  end

  @spec optional_map!(map(), atom(), String.t(), map() | nil) :: map() | nil
  def optional_map!(attrs, key, field_name, default \\ %{}) do
    case Contracts.get(attrs, key, default) do
      nil -> default
      value -> map!(value, field_name)
    end
  end

  @spec optional_list!(map(), atom(), String.t(), list()) :: list()
  def optional_list!(attrs, key, field_name, default \\ []) do
    case Contracts.get(attrs, key, default) do
      value when is_list(value) -> value
      value -> raise ArgumentError, "#{field_name} must be a list, got: #{inspect(value)}"
    end
  end

  @spec operation!(term()) :: :generate_text | :stream_text
  def operation!(nil), do: :generate_text
  def operation!(:generate_text), do: :generate_text
  def operation!(:stream_text), do: :stream_text
  def operation!("generate_text"), do: :generate_text
  def operation!("stream_text"), do: :stream_text

  def operation!(value) do
    raise ArgumentError, "operation must be generate_text or stream_text, got: #{inspect(value)}"
  end

  @spec status!(term()) :: :accepted | :ok | :error | :cancelled
  def status!(status) when status in [:accepted, :ok, :error, :cancelled], do: status
  def status!("accepted"), do: :accepted
  def status!("ok"), do: :ok
  def status!("error"), do: :error
  def status!("cancelled"), do: :cancelled

  def status!(value) do
    raise ArgumentError,
          "status must be accepted, ok, error, or cancelled, got: #{inspect(value)}"
  end

  @spec runtime_kind!(term()) :: String.t()
  def runtime_kind!(value) when value in [:client, :task, :service, :fixture],
    do: Atom.to_string(value)

  def runtime_kind!(value) when value in ["client", "task", "service", "fixture"], do: value

  def runtime_kind!(value) do
    raise ArgumentError,
          "runtime_kind must be client, task, service, or fixture, got: #{inspect(value)}"
  end

  @spec checksum!(String.t(), String.t()) :: String.t()
  def checksum!(value, field_name) do
    Contracts.validate_checksum!(value)
  rescue
    error in ArgumentError ->
      reraise ArgumentError,
              [message: "#{field_name} #{Exception.message(error)}"],
              __STACKTRACE__
  end

  @spec ensure_no_raw_payloads!(term(), String.t()) :: :ok
  def ensure_no_raw_payloads!(value, field_name) do
    walk_raw_payloads!(value, [field_name])
    :ok
  end

  defp map!(value, _field_name) when is_map(value), do: Map.new(value)

  defp map!(value, field_name) do
    raise ArgumentError, "#{field_name} must be a map, got: #{inspect(value)}"
  end

  defp walk_raw_payloads!(%_{} = value, path),
    do: walk_raw_payloads!(Map.from_struct(value), path)

  defp walk_raw_payloads!(value, path) when is_map(value) do
    Enum.each(value, fn {key, nested} ->
      key_string = key |> to_string() |> String.downcase()

      if key_string in @blocked_keys do
        raise ArgumentError,
              "#{format_path([key_string | path])} is not allowed in model invocation DTOs"
      end

      walk_raw_payloads!(nested, [key_string | path])
    end)
  end

  defp walk_raw_payloads!(value, path) when is_list(value) do
    Enum.with_index(value, fn nested, index -> walk_raw_payloads!(nested, [index | path]) end)
  end

  defp walk_raw_payloads!(_value, _path), do: :ok

  defp format_path(path) do
    path
    |> Enum.reverse()
    |> Enum.reduce("", fn
      segment, "" when is_integer(segment) -> "[#{segment}]"
      segment, acc when is_integer(segment) -> "#{acc}[#{segment}]"
      segment, "" -> segment
      segment, acc -> "#{acc}.#{segment}"
    end)
  end
end
