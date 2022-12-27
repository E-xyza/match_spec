defmodule MatchSpecTest.Fun2msfunWarnTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  defp assert_compile_warn(filename, msg) do
    capture =
      capture_io(:stderr, fn ->
        "warn_modules"
        |> Path.join(filename)
        |> Code.compile_file(__DIR__)
      end)

    assert capture =~ msg
  end

  describe "fun2msfun warns if you don't pin a matched variable" do
    test "at the top level" do
      assert_compile_warn(
        "fun2msfun_binding_unpinned_top_level.exs",
        "unpinned variable `tuple` in function match head has the same name as a binding"
      )
    end

    test "in the match body" do
      assert_compile_warn(
        "fun2msfun_binding_unpinned.exs",
        "unpinned variable `value` in function match head has the same name as a binding"
      )
    end
  end
end
