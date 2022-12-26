defmodule MatchSpecTest.LambdaFun2msfunInGuard do
  require MatchSpec

  MatchSpec.fun2msfun(:defp, :mymatch, fn any -> any end, []) = :foo
end
