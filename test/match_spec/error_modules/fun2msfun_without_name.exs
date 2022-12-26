defmodule MatchSpecTest.NoNameFun2msfun do
  require MatchSpec
  MatchSpec.fun2msfun(:def, fn any -> any end, [])
end
