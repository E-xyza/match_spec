defmodule MatchSpecTest.Fun2msWithNonguardInWhen do
  require MatchSpec

  def foo do
    MatchSpec.fun2ms(fn
      _ when Process.get(:bar) -> true
    end)
  end
end
