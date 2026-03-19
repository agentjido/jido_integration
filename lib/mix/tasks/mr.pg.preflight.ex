defmodule Mix.Tasks.Mr.Pg.Preflight do
  use Mix.Task

  alias Jido.Integration.Workspace.PostgresPreflight

  @moduledoc """
  Check whether the root Postgres-backed test tier is reachable before running
  `mix mr.test` or `mix ci`.

  This task exists to separate an environment reachability problem from a repo
  regression. It probes the same `store_postgres` target that the root test and
  CI surface use in `:test`.

  ## Usage

      mix mr.pg.preflight
  """

  @shortdoc "Check the root Postgres-backed test tier before monorepo test/CI runs"

  @impl Mix.Task
  def run(args) do
    case args do
      [] -> :ok
      _ -> Mix.raise("mix mr.pg.preflight does not accept arguments")
    end

    config = PostgresPreflight.from_env()
    executable = System.find_executable("pg_isready")

    if is_nil(executable) do
      Mix.raise("""
      Could not find `pg_isready` on PATH.

      Install the PostgreSQL client tools or expose `pg_isready`, then rerun:

          mix mr.pg.preflight
      """)
    end

    args = PostgresPreflight.pg_isready_args(config)

    case System.cmd(executable, args, stderr_to_stdout: true) do
      {output, 0} ->
        Mix.shell().info("Postgres preflight: ready")
        Mix.shell().info("target: #{PostgresPreflight.target_label(config)}")
        Mix.shell().info("database: #{config.database}")
        Mix.shell().info("user: #{config.user}")
        Mix.shell().info("check: #{Enum.join([executable | args], " ")}")
        Mix.shell().info("note: this validates the canonical `core/store_postgres` test tier")

        trimmed_output(output)
        |> maybe_print_info()

      {output, exit_code} ->
        Mix.shell().error("Postgres preflight: failed")
        Mix.shell().error("target: #{PostgresPreflight.target_label(config)}")
        Mix.shell().error("database: #{config.database}")
        Mix.shell().error("user: #{config.user}")
        Mix.shell().error("check: #{Enum.join([executable | args], " ")}")
        Mix.shell().error("pg_isready exit code: #{exit_code}")

        Mix.shell().error(
          "note: `mix mr.test` and `mix ci` exercise the `core/store_postgres` tier in :test"
        )

        trimmed_output(output)
        |> maybe_print_error()

        Mix.raise("Postgres preflight failed")
    end
  end

  defp trimmed_output(output) do
    output
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp maybe_print_info(nil), do: :ok
  defp maybe_print_info(output), do: Mix.shell().info(output)

  defp maybe_print_error(nil), do: :ok
  defp maybe_print_error(output), do: Mix.shell().error(output)
end
