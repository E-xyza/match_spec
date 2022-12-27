defmodule MatchSpecTest.Fun2msfunTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO
  import MatchSpec, only: [fun2msfun: 2]

  describe "for fun2msfun with a lambda" do
    test "you can bind a variable to the whole match" do
      assert [{{:foo}, [], [:"$_"]}] ==
               fun2msfun(fn result = ^tuple -> result end, [tuple]).({:foo})
    end

    test "you can bind a variable to a part of the match" do
      assert [{{:foo, :"$1"}, [], [:"$1"]}] ==
               fun2msfun(fn {^key, value} -> value end, [key]).(:foo)
    end
  end
end
