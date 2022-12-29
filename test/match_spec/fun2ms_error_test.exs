defmodule MatchSpecTest.Fun2msErrorTest do
  use ExUnit.Case, async: true

  defp assert_compile_error(filename, regex) do
    assert_raise CompileError, regex, fn ->
      "error_modules"
      |> Path.join(filename)
      |> Code.compile_file(__DIR__)
    end
  end

  test "fun2ms rejects having multiple matches that aren't whole variables" do
    assert_compile_error(
      "fun2ms_with_multiple_structural_matches.exs",
      ~r"only one structured pattern match allowed, multiple structured heads found: `{_, _}` and `{_}`"
    )
  end

  test "fun2ms rejects arity not 1" do
    assert_compile_error(
      "fun2ms_with_wrong_arity.exs",
      ~r"function branches for matchspecs must have arity 1 \(got arity 2\)"
    )
  end

  test "fun2ms rejects arity not 1 with a when statement" do
    assert_compile_error(
      "fun2ms_with_wrong_arity_and_when.exs",
      ~r"function branches for matchspecs must have arity 1 \(got arity 2\)"
    )
  end
end
