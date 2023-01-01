defmodule MatchSpecTest.Fun2msWithListMatch do
  require MatchSpec

  def foo do
    MatchSpec.fun2ms(fn [a] -> a end)
  end
end
