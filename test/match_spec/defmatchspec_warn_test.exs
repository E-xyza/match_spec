defmodule MatchSpecTest.DefmatchspecWarnTest do
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

  describe "when the definitions are interrupted it warns for" do
    test "defmatchspec" do
      assert_compile_warn(
        "defmatchspec_interrupted.exs",
        "clauses with the same name and arity (number of arguments) should be grouped together, \"defmatchspec my_matchspec/1\" was previously defined"
      )
    end

    test "defmatchspecp" do
      assert_compile_warn(
        "defmatchspecp_interrupted.exs",
        "clauses with the same name and arity (number of arguments) should be grouped together, \"defmatchspecp my_matchspec/1\" was previously defined"
      )
    end
  end
end
