defmodule MatchSpecTest.Fun2msWithMapMatch do
  require MatchSpec

  def foo do
    MatchSpec.fun2ms(fn %{foo: a} -> a end)
  end
end
