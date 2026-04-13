defmodule Jido.Integration.TestTmpDirTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.TestTmpDir

  test "creates unique temp directories under the system temp root" do
    first = TestTmpDir.create!("contracts_test")
    second = TestTmpDir.create!("contracts_test")

    on_exit(fn ->
      :ok = TestTmpDir.cleanup!(first)
      :ok = TestTmpDir.cleanup!(second)
    end)

    assert first != second
    assert File.dir?(first)
    assert File.dir?(second)
    assert Path.dirname(first) == Path.expand(System.tmp_dir!())
    assert Path.basename(first) =~ "contracts_test"
  end

  test "removes temp directories during cleanup" do
    path = TestTmpDir.create!("contracts_cleanup")

    assert File.dir?(path)
    assert :ok == TestTmpDir.cleanup!(path)
    refute File.exists?(path)
  end
end
