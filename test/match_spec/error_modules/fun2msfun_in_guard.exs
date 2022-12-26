defmodule MatchSpecTest.LambdaFun2msfunInGuard do
  require MatchSpec

  case :foo do
    a when MatchSpec.fun2msfun(:defp, :mymatch, fn any -> any end, []) ->
      :ok
  end
end
