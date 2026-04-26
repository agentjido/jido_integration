defmodule Jido.Integration.V2.Connectors.GitHub.LiveSpec do
  @moduledoc false

  @repo_regex ~r/\A[^\/\s]+\/[^\/\s]+\z/
  @modes [:auth, :read, :write, :all]

  @defaults %{
    subject: "github-live-proof",
    actor_id: "github-live-proof",
    tenant_id: "tenant-github-live",
    write_label: "jido-live-acceptance"
  }

  defstruct mode: nil,
            repo: nil,
            write_repo: nil,
            subject: @defaults.subject,
            actor_id: @defaults.actor_id,
            tenant_id: @defaults.tenant_id,
            write_label: @defaults.write_label,
            api_base_url: nil,
            timeout_ms: nil

  @type mode :: :auth | :read | :write | :all
  @type t :: %__MODULE__{
          mode: mode(),
          repo: String.t() | nil,
          write_repo: String.t() | nil,
          subject: String.t(),
          actor_id: String.t(),
          tenant_id: String.t(),
          write_label: String.t(),
          api_base_url: String.t() | nil,
          timeout_ms: pos_integer() | nil
        }

  @spec parse(mode(), [String.t()]) :: {:ok, t()} | {:error, term()}
  def parse(mode, argv) when mode in @modes and is_list(argv) do
    with {:ok, opts} <- parse_args(drop_arg_separator(argv), %{}),
         {:ok, opts} <- normalize_opts(opts),
         :ok <- validate_required(mode, opts),
         :ok <- validate_repos(opts) do
      {:ok, build(mode, opts)}
    end
  end

  def parse(mode, _argv), do: {:error, {:invalid_mode, mode}}

  defp drop_arg_separator(["--" | argv]), do: argv
  defp drop_arg_separator(argv), do: argv

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

    options:
      --repo owner/repo              readable repository for read/all modes
      --write-repo owner/repo        disposable writable repository for write/all modes
      --subject value                install subject label
      --actor-id value               operator actor id
      --tenant-id value              tenant id
      --write-label value            label applied during write proof
      --api-base-url url             optional GitHub Enterprise API base URL
      --timeout-ms positive_integer  optional HTTP timeout
    """
  end

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
      {:ok, key} ->
        case value_for(flag, inline_value, rest) do
          {:ok, value, remaining} -> parse_args(remaining, Map.put(acc, key, value))
          {:error, reason} -> {:error, reason}
        end

      :error ->
        {:error, {:unknown_flag, flag}}
    end
  end

  defp flag_key("--repo"), do: {:ok, :repo}
  defp flag_key("--write-repo"), do: {:ok, :write_repo}
  defp flag_key("--subject"), do: {:ok, :subject}
  defp flag_key("--actor-id"), do: {:ok, :actor_id}
  defp flag_key("--tenant-id"), do: {:ok, :tenant_id}
  defp flag_key("--write-label"), do: {:ok, :write_label}
  defp flag_key("--api-base-url"), do: {:ok, :api_base_url}
  defp flag_key("--timeout-ms"), do: {:ok, :timeout_ms}
  defp flag_key(_flag), do: :error

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
    with {:ok, timeout_ms} <- normalize_timeout(Map.get(opts, :timeout_ms)) do
      {:ok,
       opts
       |> normalize_string(:repo)
       |> normalize_string(:write_repo)
       |> normalize_string(:subject)
       |> normalize_string(:actor_id)
       |> normalize_string(:tenant_id)
       |> normalize_string(:write_label)
       |> normalize_string(:api_base_url)
       |> Map.put(:timeout_ms, timeout_ms)}
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

  defp normalize_timeout(nil), do: {:ok, nil}

  defp normalize_timeout(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _other -> {:error, {:invalid_integer, "--timeout-ms", value}}
    end
  end

  defp validate_required(:auth, _opts), do: :ok

  defp validate_required(:read, opts) do
    if Map.get(opts, :repo), do: :ok, else: {:error, {:missing, ["--repo"]}}
  end

  defp validate_required(mode, opts) when mode in [:write, :all] do
    if Map.get(opts, :repo) || Map.get(opts, :write_repo) do
      :ok
    else
      {:error, {:missing, ["--repo", "--write-repo"]}}
    end
  end

  defp validate_repos(opts) do
    case validate_repo("--repo", Map.get(opts, :repo)) do
      :ok -> validate_repo("--write-repo", Map.get(opts, :write_repo))
      {:error, _reason} = error -> error
    end
  end

  defp validate_repo(_flag, nil), do: :ok

  defp validate_repo(flag, repo) do
    if repo =~ @repo_regex, do: :ok, else: {:error, {:invalid_repo, flag, repo}}
  end

  defp build(mode, opts) do
    repo = Map.get(opts, :repo) || Map.get(opts, :write_repo)
    write_repo = Map.get(opts, :write_repo) || write_default(mode, repo)

    struct!(__MODULE__, %{
      mode: mode,
      repo: repo_for_mode(mode, repo),
      write_repo: write_repo,
      subject: Map.get(opts, :subject, @defaults.subject),
      actor_id: Map.get(opts, :actor_id, @defaults.actor_id),
      tenant_id: Map.get(opts, :tenant_id, @defaults.tenant_id),
      write_label: Map.get(opts, :write_label, @defaults.write_label),
      api_base_url: Map.get(opts, :api_base_url),
      timeout_ms: Map.get(opts, :timeout_ms)
    })
  end

  defp repo_for_mode(:auth, _repo), do: nil
  defp repo_for_mode(_mode, repo), do: repo

  defp write_default(mode, repo) when mode in [:write, :all], do: repo
  defp write_default(_mode, _repo), do: nil

  defp error_message({:missing, flags}) do
    "missing required live argument: #{Enum.join(flags, " or ")}\n\n#{usage()}"
  end

  defp error_message({:missing_value, flag}), do: "missing value for #{flag}\n\n#{usage()}"
  defp error_message({:unknown_flag, flag}), do: "unknown live argument #{flag}\n\n#{usage()}"
  defp error_message({:unexpected_arg, arg}), do: "unexpected live argument #{arg}\n\n#{usage()}"

  defp error_message({:invalid_repo, flag, repo}) do
    "invalid #{flag} value #{inspect(repo)}; expected owner/repo"
  end

  defp error_message({:invalid_integer, flag, value}) do
    "invalid #{flag} value #{inspect(value)}; expected a positive integer"
  end
end
