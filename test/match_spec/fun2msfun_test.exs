defmodule MatchSpecTest.Fun2msfunTest do
  use ExUnit.Case, async: true

  import MatchSpec

  describe "for fun2msfun with a lambda," do
    test "you can bind a variable to the whole in the match" do
      assert [{:_, [{:"=:=", :"$_", {:const, {:foo}}}], [:"$_"]}] ==
               fun2msfun(fn result = ^tuple -> result end, [tuple]).({:foo})
    end

    test "you can bind a variable to a part of the match" do
      assert [{{:"$1", :"$2"}, [{:"=:=", :"$1", {:const, :foo}}], [:"$2"]}] ==
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

    test "you can match a string with a fixed size" do
      assert [
               {{:"$1"}, [{:"=:=", {:binary_part, :"$1", 0, 3}, {:const, "foo"}}],
                [{:binary_part, :"$1", 3, {:-, {:byte_size, :"$1"}, 3}}]}
             ] ==
               fun2msfun(fn {<<^v::binary-size(3), rest::binary>>} -> rest end, [v]).("foo")
    end

    test "you can match a string with a variable size" do
      assert [
               {{:"$1"}, [{:"=:=", {:binary_part, :"$1", 0, 3}, {:const, "foo"}}],
                [{:binary_part, :"$1", 3, {:-, {:byte_size, :"$1"}, 3}}]}
             ] ==
               fun2msfun(fn {<<^v::binary-size(byte_size(v)), rest::binary>>} -> rest end, [v]).(
                 "foo"
               )
    end

    test "you can match a string with a prefix and a variable size" do
      assert [
               {{:"$1"},
                [
                  {:"=:=", {:binary_part, :"$1", 0, 3}, {:const, "foo"}},
                  {:"=:=", {:binary_part, :"$1", 3, 3}, {:const, "bar"}}
                ], [{:binary_part, :"$1", 6, {:-, {:byte_size, :"$1"}, 6}}]}
             ] ==
               fun2msfun(
                 fn {<<"foo", ^v::binary-size(byte_size(v)), rest::binary>>} -> rest end,
                 [v]
               ).("bar")
    end

    test "fails preflight check if you pass a non-string into binary-pinned content" do
      assert_raise ArgumentError, "the variable `a` is required to be a binary, got :foo", fn ->
        fun2msfun(fn {<<^a::binary-size(3)>>} -> true end, [a]).(:foo)
      end
    end

    test "fails preflight check if you pass a too-short string into binary-pinned content" do
      assert_raise ArgumentError,
                   "the variable `a` is expected to have length at least 4, got 3",
                   fn ->
                     fun2msfun(fn {<<^a::binary-size(4)>>} -> true end, [a]).("foo")
                   end
    end
  end

  describe "for fun2msfun function builder" do
    fun2msfun(:def, :test_def, fn {^key, value} -> value end, [key])

    test "def-style works" do
      assert [{{:"$1", :"$2"}, [{:"=:=", :"$1", {:const, :foo}}], [:"$2"]}] == test_def(:foo)
      assert function_exported?(__MODULE__, :test_def, 1)
    end

    fun2msfun(:defp, :test_defp, fn {^key, value} -> value end, [key])

    test "defp-style works" do
      assert [{{:"$1", :"$2"}, [{:"=:=", :"$1", {:const, :foo}}], [:"$2"]}] == test_defp(:foo)
      refute function_exported?(__MODULE__, :test_defp, 1)
    end

    fun2msfun(:def, :test_top_pin, fn ^pin -> true end, [pin])

    test "injects an runtime error if a pinned, top-level match isn't a tuple" do
      assert_raise ArgumentError,
                   "matching against the whole match must be a tuple, got pinned value `:foo`",
                   fn ->
                     test_top_pin(:foo)
                   end

      assert_raise ArgumentError,
                   "matching against the whole match must be a tuple, got pinned value `%{some: \"map\"}`",
                   fn ->
                     test_top_pin(%{some: "map"})
                   end
    end
  end
end
