defmodule Jido.Integration.V2.Connectors.Linear.LiveSpec do
  @moduledoc false

  @modes [:auth, :read, :write, :all]

  @defaults %{
    subject: "linear-live-proof",
    actor_id: "linear-live-proof",
    tenant_id: "tenant-linear-live",
    read_limit: 10
  }

  defstruct mode: nil,
            api_key_source: nil,
            subject: @defaults.subject,
            actor_id: @defaults.actor_id,
            tenant_id: @defaults.tenant_id,
            api_base_url: nil,
            timeout_ms: nil,
            read_limit: @defaults.read_limit,
            keep_terminal_comment?: false

  @type api_key_source :: :stdin | {:file, String.t()}
  @type mode :: :auth | :read | :write | :all
  @type t :: %__MODULE__{
          mode: mode(),
          api_key_source: api_key_source() | nil,
          subject: String.t(),
          actor_id: String.t(),
          tenant_id: String.t(),
          api_base_url: String.t() | nil,
          timeout_ms: pos_integer() | nil,
          read_limit: pos_integer(),
          keep_terminal_comment?: boolean()
        }

  @spec parse(mode(), [String.t()]) :: {:ok, t()} | {:error, term()}
  def parse(mode, argv) when mode in @modes and is_list(argv) do
    with {:ok, opts} <- parse_args(drop_arg_separator(argv), %{}),
         {:ok, opts} <- normalize_opts(opts),
         :ok <- validate_required(opts),
         :ok <- validate_credential_source(opts) do
      {:ok, build(mode, opts)}
    end
  end

  def parse(mode, _argv), do: {:error, {:invalid_mode, mode}}

  @spec parse!(mode(), [String.t()]) :: t()
  def parse!(mode, argv) do
    case parse(mode, argv) do
      {:ok, spec} -> spec
      {:error, reason} -> raise ArgumentError, error_message(reason)
    end
  end

  @spec usage() :: String.t()
  def usage do
    """
    usage: scripts/live_acceptance.sh [auth|read|write|all] [options]

    credential source, exactly one required:
      --api-key-stdin               read a Linear API key from standard input
      --api-key-file path           read a Linear API key from an operator-owned file

    options:
      --subject value               install subject label
      --actor-id value              operator actor id
      --tenant-id value             tenant id
      --read-limit positive_integer live list page size for dynamic discovery
      --keep-terminal-comment       preserve the updated write-proof comment as terminal evidence
      --api-base-url url            optional Linear GraphQL API base URL
      --timeout-ms positive_integer optional HTTP receive timeout
    """
  end

  defp drop_arg_separator(["--" | argv]), do: argv
  defp drop_arg_separator(argv), do: argv

  defp parse_args([], acc), do: {:ok, acc}

  defp parse_args([arg | rest], acc) when is_binary(arg) do
    case split_flag(arg) do
      {:ok, flag, value} ->
        put_flag(flag, value, rest, acc)

      :not_flag ->
        {:error, {:unexpected_arg, arg}}
    end
  end

  defp split_flag("--" <> _rest = arg) do
    case String.split(arg, "=", parts: 2) do
      [flag, value] when value != "" -> {:ok, flag, value}
      [flag] -> {:ok, flag, nil}
      [flag, ""] -> {:ok, flag, ""}
    end
  end

  defp split_flag(_arg), do: :not_flag

  defp put_flag(flag, inline_value, rest, acc) do
    case flag_key(flag) do
      {:ok, :api_key_stdin} ->
        put_boolean_flag(flag, inline_value, rest, acc, :api_key_stdin)

      {:ok, :keep_terminal_comment} ->
        put_boolean_flag(flag, inline_value, rest, acc, :keep_terminal_comment)

      {:ok, key} ->
        case value_for(flag, inline_value, rest) do
          {:ok, value, remaining} -> parse_args(remaining, Map.put(acc, key, value))
          {:error, reason} -> {:error, reason}
        end

      :error ->
        {:error, {:unknown_flag, flag}}
    end
  end

  defp flag_key("--api-key-stdin"), do: {:ok, :api_key_stdin}
  defp flag_key("--api-key-file"), do: {:ok, :api_key_file}
  defp flag_key("--subject"), do: {:ok, :subject}
  defp flag_key("--actor-id"), do: {:ok, :actor_id}
  defp flag_key("--tenant-id"), do: {:ok, :tenant_id}
  defp flag_key("--api-base-url"), do: {:ok, :api_base_url}
  defp flag_key("--timeout-ms"), do: {:ok, :timeout_ms}
  defp flag_key("--read-limit"), do: {:ok, :read_limit}
  defp flag_key("--keep-terminal-comment"), do: {:ok, :keep_terminal_comment}
  defp flag_key(_flag), do: :error

  defp put_boolean_flag(_flag, nil, rest, acc, key), do: parse_args(rest, Map.put(acc, key, true))

  defp put_boolean_flag(flag, _inline_value, _rest, _acc, _key) do
    {:error, {:unexpected_value, flag}}
  end

  defp value_for(flag, nil, [next | rest]) when is_binary(next) do
    if String.starts_with?(next, "--") do
      {:error, {:missing_value, flag}}
    else
      {:ok, next, rest}
    end
  end

  defp value_for(flag, nil, []), do: {:error, {:missing_value, flag}}
  defp value_for(_flag, inline_value, rest), do: {:ok, inline_value, rest}

  defp normalize_opts(opts) do
    with {:ok, timeout_ms} <-
           normalize_positive_integer("--timeout-ms", Map.get(opts, :timeout_ms)),
         {:ok, read_limit} <-
           normalize_positive_integer("--read-limit", Map.get(opts, :read_limit)) do
      {:ok,
       opts
       |> normalize_string(:api_key_file)
       |> normalize_string(:subject)
       |> normalize_string(:actor_id)
       |> normalize_string(:tenant_id)
       |> normalize_string(:api_base_url)
       |> Map.put(:timeout_ms, timeout_ms)
       |> Map.put(:read_limit, read_limit || @defaults.read_limit)}
    end
  end

  defp normalize_string(opts, key) do
    case Map.get(opts, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> Map.delete(opts, key)
          present -> Map.put(opts, key, present)
        end

      _other ->
        opts
    end
  end

  defp normalize_positive_integer(_flag, nil), do: {:ok, nil}

  defp normalize_positive_integer(flag, value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _other -> {:error, {:invalid_integer, flag, value}}
    end
  end

  defp validate_required(opts) do
    if Map.get(opts, :api_key_stdin) || Map.get(opts, :api_key_file) do
      :ok
    else
      {:error, {:missing, ["--api-key-stdin", "--api-key-file"]}}
    end
  end

  defp validate_credential_source(%{api_key_stdin: true, api_key_file: _path}) do
    {:error, {:duplicate_credential_source, ["--api-key-stdin", "--api-key-file"]}}
  end

  defp validate_credential_source(_opts), do: :ok

  defp build(mode, opts) do
    struct!(__MODULE__, %{
      mode: mode,
      api_key_source: api_key_source(opts),
      subject: Map.get(opts, :subject, @defaults.subject),
      actor_id: Map.get(opts, :actor_id, @defaults.actor_id),
      tenant_id: Map.get(opts, :tenant_id, @defaults.tenant_id),
      api_base_url: Map.get(opts, :api_base_url),
      timeout_ms: Map.get(opts, :timeout_ms),
      read_limit: Map.fetch!(opts, :read_limit),
      keep_terminal_comment?: Map.get(opts, :keep_terminal_comment, false)
    })
  end

  defp api_key_source(%{api_key_stdin: true}), do: :stdin
  defp api_key_source(%{api_key_file: path}), do: {:file, path}

  defp error_message({:missing, flags}) do
    "missing required live argument: #{Enum.join(flags, " or ")}\n\n#{usage()}"
  end

  defp error_message({:missing_value, flag}), do: "missing value for #{flag}\n\n#{usage()}"
  defp error_message({:unexpected_value, flag}), do: "unexpected value for #{flag}\n\n#{usage()}"
  defp error_message({:unknown_flag, flag}), do: "unknown live argument #{flag}\n\n#{usage()}"
  defp error_message({:unexpected_arg, arg}), do: "unexpected live argument #{arg}\n\n#{usage()}"

  defp error_message({:duplicate_credential_source, flags}) do
    "choose exactly one credential source: #{Enum.join(flags, " or ")}"
  end

  defp error_message({:invalid_integer, flag, value}) do
    "invalid #{flag} value #{inspect(value)}; expected a positive integer"
  end
end
