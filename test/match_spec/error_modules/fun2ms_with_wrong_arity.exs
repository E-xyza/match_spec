defmodule MatchSpecTest.Fun2msWithWrongArity do
  require MatchSpec

  def foo do
    MatchSpec.fun2ms(fn a, b -> true end)
  end
end
