defmodule Mix.Tasks.JidoIntegration.Release.Publish do
  use Mix.Task

  @moduledoc """
  Publish the prepared welded release bundle from `build_support/weld.exs`.

  This task intentionally publishes from the prepared bundle snapshot rather
  than from the source monorepo so the published Hex artifact matches the
  archived release bundle byte-for-byte.

  Run `mix release.prepare` first, then publish with this task, then finish
  with `mix release.archive`.
  """

  @shortdoc "Publish the prepared welded release bundle"

  @impl Mix.Task
  def run(args) do
    {opts, _positional, _invalid} =
      OptionParser.parse(args, strict: [artifact: :string, dry_run: :boolean, manifest: :string])

    artifact = opts[:artifact] || "jido_integration"
    manifest_path = opts[:manifest] || "build_support/weld.exs"
    bundle_path = Weld.release_bundle_path!(manifest_path, artifact: artifact)
    project_path = Path.join(bundle_path, "project")

    unless File.dir?(project_path) do
      Mix.raise("""
      prepared release bundle not found: #{project_path}

      Run `mix release.prepare` first.
      """)
    end

    publish_args =
      ["hex.publish", "--yes"] ++
        if(opts[:dry_run], do: ["--dry-run"], else: [])

    {output, status} =
      System.cmd("mix", publish_args, cd: project_path, stderr_to_stdout: true)

    Mix.shell().info(output)

    if status != 0 do
      Mix.raise("bundle publish failed from #{project_path}")
    end
  after
    Mix.Task.reenable("jido_integration.release.publish")
  end
end
