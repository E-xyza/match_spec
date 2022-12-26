defmodule MatchSpecTest.LambdaFun2msfunInModuleBody do
  require MatchSpec
  MatchSpec.fun2msfun(:lambda, fn any -> any end, [])
end
