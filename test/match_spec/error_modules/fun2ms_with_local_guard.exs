defmodule MatchSpecTest.Fun2msWithLocalGuard do
  require MatchSpec

  defguardp is_foo(x) when x === :foo

  MatchSpec.fun2ms(fn foo when is_foo(foo) -> true end)
end
