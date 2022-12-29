defmodule MatchSpecTest.Fun2msfunWithUndefinedPin do
  require MatchSpec

  MatchSpec.fun2msfun(:def, :my_msfun, fn any = ^undefined -> any end, [])
end
