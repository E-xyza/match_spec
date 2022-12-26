defmodule MatchSpecTest.NamedLambdaFun2msfun do
  require MatchSpec

  def failing_lambda do
    MatchSpec.fun2msfun(:lambda, :my_lambda, fn any -> any end, [])
  end
end
