defmodule MatchSpecTest.Fun2msfunTest do
  use ExUnit.Case, async: true

  import MatchSpec, only: [fun2msfun: 2, fun2msfun: 4]

  describe "for fun2msfun with a lambda," do
    test "you can bind a variable to the whole in the match" do
      assert [{{:foo}, [], [:"$_"]}] ==
               fun2msfun(fn result = ^tuple -> result end, [tuple]).({:foo})
    end

    test "you can bind a variable to a part of the match" do
      assert [{{:foo, :"$1"}, [], [:"$1"]}] ==
               fun2msfun(fn {^key, value} -> value end, [key]).(:foo)
    end

    test "you can bind a variable into the filter, and it's const" do
      assert [{:_, [{:"=:=", :"$_", {:const, :foo}}], [:"$_"]}] ==
               fun2msfun(fn result when result === tuple -> result end, [tuple]).(:foo)
    end

    test "you can bind a variable into the result, and it's const" do
      assert [{:_, [], [{:const, :foo}]}] ==
               fun2msfun(fn _ -> output end, [output]).(:foo)
    end
  end

  describe "for fun2ms" do
    fun2msfun(:def, :test_def, fn {^key, value} -> value end, [key])

    test "def-style works" do
      assert [{{:foo, :"$1"}, [], [:"$1"]}] == test_def(:foo)
      assert function_exported?(__MODULE__, :test_def, 1)
    end

    fun2msfun(:defp, :test_defp, fn {^key, value} -> value end, [key])

    test "defp-style works" do
      assert [{{:foo, :"$1"}, [], [:"$1"]}] == test_defp(:foo)
      refute function_exported?(__MODULE__, :test_defp, 1)
    end
  end
end
