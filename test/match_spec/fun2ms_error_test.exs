defmodule MatchSpecTest.Fun2msErrorTest do
  use ExUnit.Case, async: true

  defp assert_compile_error(filename, regex) do
    assert_raise CompileError, regex, fn ->
      "error_modules"
      |> Path.join(filename)
      |> Code.compile_file(__DIR__)
    end
  end

  describe "fun2ms rejects" do
    test "having multiple matches that aren't whole variables" do
      assert_compile_error(
        "fun2ms_with_multiple_structural_matches.exs",
        ~r"only one structured pattern match allowed in the head, multiple patterns found: `{_}` and `{_, _}`"
      )
    end

    test "arity not 1" do
      assert_compile_error(
        "fun2ms_with_wrong_arity.exs",
        ~r"function branches for matchspecs must have arity 1 \(got arity 2\)"
      )
    end

    test "arity not 1 with a when statement" do
      assert_compile_error(
        "fun2ms_with_wrong_arity_and_when.exs",
        ~r"function branches for matchspecs must have arity 1 \(got arity 2\)"
      )
    end

    test "not having a singular final expression" do
      assert_compile_error(
        "fun2ms_with_nonsingular_return.exs",
        ~r"function bodies for matchspecs must be a single result expression"
      )
    end

    test "a non-guard function in the when clause" do
      assert_compile_error(
        "fun2ms_with_nonguard_in_when.exs",
        ~r"non-guard function found in when clause: `Process.get\(:bar\)`"
      )
    end

    test "a non-guard function in the body clause" do
      assert_compile_error(
        "fun2ms_with_nonguard_in_body.exs",
        ~r"non-guard function found in result expression: `Process.get\(:bar\)`"
      )
    end

    test "top level matches on lists error" do
      assert_compile_error(
        "fun2ms_with_list_match.exs",
        ~r"top match cannot be a list \(got: \[a\]\)"
      )
    end

    test "top level matches on maps error" do
      assert_compile_error(
        "fun2ms_with_map_match.exs",
        ~r"top match cannot be a map \(got: %{foo: a}\)"
      )
    end

    test "top level matches on structs error" do
      assert_compile_error(
        "fun2ms_with_struct_match.exs",
        ~r"top match cannot be a struct \(got: %Range{start: a}\)"
      )
    end

    test "top level matches on binaries error" do
      assert_compile_error(
        "fun2ms_with_binary_match.exs",
        ~r"top match cannot be a binary \(got: <<_>>\)"
      )
    end
  end
end
