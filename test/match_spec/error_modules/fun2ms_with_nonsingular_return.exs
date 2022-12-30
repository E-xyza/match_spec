defmodule MatchSpecTest.Fun2msWithNonsingularReturn do
  require MatchSpec

  def foo do
    MatchSpec.fun2ms(fn
      _ ->
        foo = Process.get(:bar)
        foo
    end)
  end
end
