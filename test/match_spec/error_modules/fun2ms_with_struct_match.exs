defmodule MatchSpecTest.Fun2msWithStructMatch do
  require MatchSpec

  def foo do
    MatchSpec.fun2ms(fn %Range{start: a} -> a end)
  end
end
