defmodule MatchSpecTest.Fun2msfunWithLocalGuard do
  require MatchSpec

  defguardp is_foo(x) when x === :foo

  MatchSpec.fun2msfun(:def, :foo, fn foo when is_foo(foo) -> true end, [])
end
