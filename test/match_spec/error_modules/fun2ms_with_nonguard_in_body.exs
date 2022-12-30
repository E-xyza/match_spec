defmodule MatchSpecTest.Fun2msWithNonguardInBody do
  require MatchSpec

  def foo do
    MatchSpec.fun2ms(fn
      _ -> Process.get(:bar)
    end)
  end
end
