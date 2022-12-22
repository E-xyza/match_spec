defmodule MatchSpec do
  alias MatchSpec.Fun2ms
  alias MatchSpec.Ms2fun

  defmacro fun2ms(fun_ast) do
    Fun2ms.from_fun_ast(fun_ast)
  end

  defdelegate ms2fun(ms, opt), to: Ms2fun, as: :to_fun
end
