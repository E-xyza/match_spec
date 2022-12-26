defmodule MatchSpecTest.LambdaFun2msfunInGuard do
  require MatchSpec

  def lambda_in_match do
    MatchSpec.fun2msfun(:lambda, fn any -> any end, []) = :foo
  end
end
