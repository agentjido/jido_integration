defmodule Mix.Tasks.Jido.Integration.NewTest do
  use ExUnit.Case

  @moduletag :tmp_dir

  alias Jido.Integration.Conformance
  alias Mix.Tasks.Jido.Integration.New, as: NewTask

  describe "scaffold generation" do
    test "generates a standalone package layout by default", %{tmp_dir: tmp_dir} do
      in_tmp_project(tmp_dir, fn ->
        run_task(["acme_crm"])

        package_root = Path.join(tmp_dir, "packages/connectors/acme_crm")
        mix_path = Path.join(package_root, "mix.exs")
        readme_path = Path.join(package_root, "README.md")
        test_helper_path = Path.join(package_root, "test/test_helper.exs")
        adapter_path = Path.join(package_root, "lib/jido/integration/connectors/acme_crm.ex")

        manifest_path =
          Path.join(package_root, "priv/jido/integration/connectors/acme_crm/manifest.json")

        test_path = Path.join(package_root, "test/jido/integration/connectors/acme_crm_test.exs")

        conformance_path =
          Path.join(
            package_root,
            "test/jido/integration/connectors/acme_crm_conformance_test.exs"
          )

        fixture_path = Path.join(package_root, "test/fixtures/acme_crm/success.json")

        assert File.exists?(mix_path)
        assert File.exists?(readme_path)
        assert File.exists?(test_helper_path)
        assert File.exists?(adapter_path)
        assert File.exists?(manifest_path)
        assert File.exists?(test_path)
        assert File.exists?(conformance_path)
        assert File.exists?(fixture_path)

        mix_content = File.read!(mix_path)
        assert mix_content =~ "app: :jido_integration_acme_crm"
        assert mix_content =~ "{:jido_integration, path: \"../../..\"}"

        adapter_content = File.read!(adapter_path)
        assert adapter_content =~ "defmodule Jido.Integration.Connectors.AcmeCrm"
        assert adapter_content =~ "@manifest_path"
        assert adapter_content =~ "File.read!()"

        manifest = manifest_path |> File.read!() |> Jason.decode!()
        assert manifest["id"] == "acme_crm"
        assert manifest["domain"] == "saas"

        fixture = fixture_path |> File.read!() |> Jason.decode!()
        assert fixture["operation_id"] == "acme_crm.hello"
        assert fixture["expected"]["reply"] == "fixture_test"
      end)
    end

    test "generated package adapter compiles and passes conformance with fixtures", %{
      tmp_dir: tmp_dir
    } do
      in_tmp_project(tmp_dir, fn ->
        run_task(["acme_ops", "--module", "Generated.AcmeOps"])

        adapter_path =
          Path.join(
            tmp_dir,
            "packages/connectors/acme_ops/lib/jido/integration/connectors/acme_ops.ex"
          )

        fixture_dir =
          Path.join(tmp_dir, "packages/connectors/acme_ops/test/fixtures/acme_ops")

        [{module, _}] = Code.compile_file(adapter_path)

        assert module.id() == "acme_ops"
        assert module.manifest().id == "acme_ops"

        report = Conformance.run(module, profile: :silver, fixture_dir: fixture_dir)
        assert report.pass_fail == :pass, inspect(Conformance.failures(report))

        assert Enum.any?(
                 report.suite_results,
                 &(&1.suite == "determinism" and &1.status == :passed)
               )
      end)
    end

    test "supports explicit core layout with a custom adapter path", %{tmp_dir: tmp_dir} do
      in_tmp_project(tmp_dir, fn ->
        run_task([
          "my_ai",
          "--module",
          "Generated.MyAi",
          "--domain",
          "ai",
          "--layout",
          "core",
          "--path",
          "lib/custom/adapter.ex"
        ])

        adapter_path = Path.join(tmp_dir, "lib/custom/adapter.ex")
        manifest_path = Path.join(tmp_dir, "priv/jido/integration/connectors/my_ai/manifest.json")

        assert File.exists?(adapter_path)
        assert File.exists?(manifest_path)

        [{module, _}] = Code.compile_file(adapter_path)

        assert module.id() == "my_ai"
        assert module.manifest().domain == "ai"
      end)
    end
  end

  defp run_task(args) do
    Mix.Task.reenable("jido.integration.new")
    NewTask.run(args)
  end

  defp in_tmp_project(tmp_dir, fun) do
    File.cd!(tmp_dir, fn ->
      fun.()
    end)
  end
end
