defmodule MatchSpecTest.LambdaFun2msfunInGuard do
  require MatchSpec

  def lambda_in_guard do
    case :foo do
      a when MatchSpec.fun2msfun(:lambda, fn any -> any end, []) ->
        :ok
    end
  end
end
