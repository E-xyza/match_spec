defmodule Foo do
  @on_load :init

  require MatchSpec

  def init do
    ms = :ets.match_spec_compile(MatchSpec.fun2ms(fn {a} -> a end))
    Application.put_env(:match_spec, Foo, ms)
  end
end
