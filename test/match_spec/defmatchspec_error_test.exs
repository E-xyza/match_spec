defmodule MatchSpecTest.DefmatchspecErrorTest do
  use ExUnit.Case, async: true

  defp assert_compile_error(filename, regex) do
    assert_raise CompileError, regex, fn ->
      "error_modules"
      |> Path.join(filename)
      |> Code.compile_file(__DIR__)
    end
  end

  describe "defmatchspec functions" do
    test "defmatchspec needs use MatchSpec" do
      assert_compile_error(
        "defmatchspec_without_use_match_spec.exs",
        ~r/defmatchspec may only be used if you have `use MatchSpec` in the module$/
      )
    end

    test "defmatchspecp needs use MatchSpec" do
      assert_compile_error(
        "defmatchspecp_without_use_match_spec.exs",
        ~r/defmatchspecp may only be used if you have `use MatchSpec` in the module$/
      )
    end

    test "if you try to redefine defmatchspec" do
      assert_compile_error(
        "defmatchspecp_after_defmatchspec.exs",
        ~r(defmatchspecp my_matchspec/1 was already defined as defmatchspec)
      )
    end

    test "if you try to redefine defmatchspecp" do
      assert_compile_error(
        "defmatchspec_after_defmatchspecp.exs",
        ~r(defmatchspec my_matchspec/1 was already defined as defmatchspecp)
      )
    end

    test "if you try to have a top level attrribute in defmatchspec" do
      assert_compile_error(
        "defmatchspec_top_level_attribute.exs",
        ~r(top match cannot be an attribute)
      )
    end
  end
end
