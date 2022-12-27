defmodule MatchSpecTest.Fun2msfunErrorTest do
  use ExUnit.Case, async: true

  defp assert_compile_error(filename, regex) do
    assert_raise CompileError, regex, fn ->
      "error_modules"
      |> Path.join(filename)
      |> Code.compile_file(__DIR__)
    end
  end

  test "fun2msfun errors if you have a bad type" do
    assert_compile_error(
      "fun2msfun_with_bad_type.exs",
      ~r/fun2msfun must be one of `:lambda`, `:def`, `:defp`$/
    )
  end

  describe "def/defp fun2msfun invocation" do
    test "errors if you try to make a def/defp without a name" do
      assert_compile_error(
        "fun2msfun_without_name.exs",
        ~r/def and defp fun2msfun invocations must have a name$/
      )
    end

    test "errors if you try to put it in a function body" do
      assert_compile_error(
        "fun2msfun_in_function_body.exs",
        ~r/def and defp fun2msfun invocations must be in the module body$/
      )
    end

    test "cant be in a guard" do
      assert_compile_error(
        "fun2msfun_in_guard.exs",
        ~r/def and defp fun2msfun invocations may not be in a guard$/
      )
    end

    test "cant be in a match" do
      assert_compile_error(
        "fun2msfun_in_match.exs",
        ~r/def and defp fun2msfun invocations may not be in a match$/
      )
    end
  end

  describe "lambda fun2msfun invocation" do
    test "errors if you try to make a lambda with a name" do
      assert_compile_error(
        "lambda_fun2msfun_with_name.exs",
        ~r/lambda fun2msfun invocations must not have a name$/
      )
    end

    test "errors if you try to put it into the module body" do
      assert_compile_error(
        "lambda_fun2msfun_in_module_body.exs",
        ~r/lambda fun2msfun invocations must be in a function body$/
      )
    end

    test "cant be in a guard" do
      assert_compile_error(
        "lambda_fun2msfun_in_guard.exs",
        ~r/lambda fun2msfun invocations may not be in a guard$/
      )
    end

    test "cant be in a match" do
      assert_compile_error(
        "lambda_fun2msfun_in_match.exs",
        ~r/lambda fun2msfun invocations may not be in a match$/
      )
    end
  end
end
