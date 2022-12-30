defmodule MatchSpecTest.Fun2msfunTest do
  use ExUnit.Case, async: true

  import MatchSpec

  describe "for fun2msfun with a lambda," do
    test "you can bind a variable to the whole in the match" do
      assert [{{:foo}, [], [:"$_"]}] ==
               fun2msfun(fn result = ^tuple -> result end, [tuple]).({:foo})
    end

    # test "you can bind a variable to a part of the match" do
    # assert [{{:foo, :"$1"}, [], [:"$1"]}] ==
    #  fun2msfun(fn {^key, value} -> value end, [key]).(:foo)
    # end
    #
    # test "you can bind a variable into the filter, and it's const" do
    # assert [{:_, [{:"=:=", :"$_", {:const, :foo}}], [:"$_"]}] ==
    #  fun2msfun(fn result when result === tuple -> result end, [tuple]).(:foo)
    # end
    #
    # test "you can bind a variable into the result, and it's const" do
    # assert [{:_, [], [{:const, :foo}]}] ==
    #  fun2msfun(fn _ -> output end, [output]).(:foo)
    # end
    # end
    #
    # describe "for fun2msfun function builder" do
    # fun2msfun(:def, :test_def, fn {^key, value} -> value end, [key])
    #
    # test "def-style works" do
    # assert [{{:foo, :"$1"}, [], [:"$1"]}] == test_def(:foo)
    # assert function_exported?(__MODULE__, :test_def, 1)
    # end
    #
    # fun2msfun(:defp, :test_defp, fn {^key, value} -> value end, [key])
    #
    # test "defp-style works" do
    # assert [{{:foo, :"$1"}, [], [:"$1"]}] == test_defp(:foo)
    # refute function_exported?(__MODULE__, :test_defp, 1)
    # end
    #
    # fun2msfun(:def, :test_top_pin, fn ^pin -> true end, [pin])
    #
    # test "injects an runtime error if a pinned, top-level match isn't a tuple" do
    # assert_raise ArgumentError, "matching against the whole match must be a tuple, got pinned value `:foo`", fn ->
    # test_top_pin(:foo)
    # end
    #
    # assert_raise ArgumentError, "matching against the whole match must be a tuple, got pinned value `%{some: \"map\"}`", fn ->
    # test_top_pin(%{some: "map"})
    # end

    # end
  end
end
