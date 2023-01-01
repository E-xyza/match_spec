defmodule MatchSpecTest.Fun2msWithBinaryMatch do
  require MatchSpec

  def foo do
    MatchSpec.fun2ms(fn a = <<_>> -> a end)
  end
end
