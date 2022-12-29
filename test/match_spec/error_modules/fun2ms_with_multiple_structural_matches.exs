defmodule MatchSpecTest.Fun2msWithMultipleStructuralMatches do
  require MatchSpec

  def foo do
    MatchSpec.fun2ms(fn {_} = {_, _} -> true end)
  end
end
