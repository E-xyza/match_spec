defmodule MatchSpecTest.NoNameFun2msfun do
  require MatchSpec
  MatchSpec.fun2msfun(:bad_descriptor, fn any -> any end, [])
end
