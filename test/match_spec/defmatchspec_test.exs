defmodule MatchSpecTest.DefmatchspecTest do
  use ExUnit.Case, async: true
  use MatchSpec

  describe "defmatchspec" do
    defmatchspec(test_def_one_body(key)({^key, value}), do: value)

    test "works with one body" do
      assert [{{:foo, :"$1"}, [], [:"$1"]}] == test_def_one_body(:foo)
      assert function_exported?(__MODULE__, :test_def_one_body, 1)
    end

    test "works with a with"

    test "works with multiple bodies"
  end

  describe "defmatchspecp" do
    defmatchspec(test_defp_matchspec(key)({^key, value}), do: value)

    test "works" do
      assert [{{:foo, :"$1"}, [], [:"$1"]}] == test_defp_matchspec(:foo)
      refute function_exported?(__MODULE__, :test_defp_matchspec, 1)
    end
  end
end
