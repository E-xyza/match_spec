defmodule MatchSpecTest.DefmatchspecTest do
  use ExUnit.Case, async: true
  use MatchSpec

  describe "defmatchspec" do
    defmatchspec test_def_one_body(key) do
      {^key, value} -> value
    end

    test "works with one body" do
      assert [{{:"$1", :"$2"}, [{:"=:=", :"$1", {:const, :foo}}], [:"$2"]}] ==
               test_def_one_body(:foo)

      assert function_exported?(__MODULE__, :test_def_one_body, 1)
    end

    defmatchspec test_def_with_when_in_match(key) do
      {^key, value} when is_integer(value) -> value
    end

    test "works with a when in the match" do
      assert [{{:"$1", :"$2"}, [{:"=:=", :"$1", {:const, :foo}}, {:is_integer, :"$2"}], [:"$2"]}] ==
               test_def_with_when_in_match(:foo)
    end

    defmatchspec test_def_with_when_in_fn(key) when is_integer(key) do
      {^key, value} -> value
    end

    test "works with a when in the main function" do
      assert [{{:"$1", :"$2"}, [{:"=:=", :"$1", {:const, 1}}], [:"$2"]}] ==
               test_def_with_when_in_fn(1)
    end

    defmatchspec test_def_with_multiple_bodies(key) when is_integer(key) do
      {^key, value} -> value
    end

    defmatchspec test_def_with_multiple_bodies(key) when is_atom(key) do
      {value, ^key} -> value
    end

    test "works with multiple bodies" do
      assert [{{:"$1", :"$2"}, [{:"=:=", :"$1", {:const, 1}}], [:"$2"]}] ==
               test_def_with_multiple_bodies(1)

      assert [{{:"$1", :"$2"}, [{:"=:=", :"$2", {:const, :foo}}], [:"$1"]}] ==
               test_def_with_multiple_bodies(:foo)
    end

    require Integer
    defguardp is_five(number) when number === 5

    defmatchspec test_builtin_custom_guard() do
      {number} when Integer.is_even(number) -> number
    end

    test "works with builtin custom guard" do
      assert [
               {{:"$1"}, [{:andalso, {:is_integer, :"$1"}, {:==, {:band, :"$1", 1}, 0}}], [:"$1"]}
             ] == test_builtin_custom_guard()
    end

    defmatchspec test_local_custom_guard() do
      {number} when is_five(number) -> number
    end

    test "works with local custom guard" do
      assert [{{:"$1"}, [{:"=:=", :"$1", 5}], [:"$1"]}] == test_local_custom_guard()
    end
  end

  describe "defmatchspecp" do
    defmatchspecp test_defp_matchspec(key) do
      {^key, value} -> value
    end

    test "works" do
      assert [{{:"$1", :"$2"}, [{:"=:=", :"$1", {:const, :foo}}], [:"$2"]}] ==
               test_defp_matchspec(:foo)

      refute function_exported?(__MODULE__, :test_defp_matchspec, 1)
    end
  end
end
