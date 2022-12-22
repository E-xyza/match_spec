defmodule MatchSpec do
  @moduledoc """
  Elixir module to help you write matchspecs.

  contains functions which transform elixir-style functions into erlang matchspecs, and vice versa.
  """

  alias MatchSpec.Fun2ms
  alias MatchSpec.Ms2fun

  @doc """
  converts a function ast into an ets matchspec.

  The function must have arity one, and may only have one clause which results in a
  return value.  Only builtin guard clauses are supported.

  The function must also be "`fn` ast"; you can't pass a shorthand lambda or
  a lambda to an existing lambda.

  The function lambda form is only used as a scaffolding to represent ets matching
  and filtering operations, it will not be instantiated into bytecode of the
  resulting module.

  ```elixir
  iex> require MatchSpec
  iex> MatchSpec.fun2ms(fn tuple = {k, v} when v > 1 and v < 10 -> tuple end)
  [{{:"$1", :"$2"}, [{:andalso, {:>, :"$2", 1}, {:<, :"$2", 10}}], [:"$_"]}]
  ```
  """
  defmacro fun2ms(fun_ast) do
    Fun2ms.from_fun_ast(fun_ast)
  end

  @doc """
  converts a matchspec into elixir AST for functions.  Unfortunately, the ast
  generator cannot guess names for variables, so variable names are set by
  the numerical value of the matchspec token

  The second parameter takes two modes:

  - `:ast` emits elixir ast to write a lambda.

  ```elixir
  iex> MatchSpec.ms2fun([{{:"$1", :"$2"}, [], [:"$2"]}], :ast)

  {:fn, [],
    [{:->, [], [[{:{}, [], [{:v1, [], nil}, {:v2, [], nil}]}], {:v2, [], nil}]}]}
  ```

  - `:code` outputs formatted elixir code.

  ```elixir
  iex> MatchSpec.ms2fun([{{:"$1", :"$2"}, [], [:"$2"]}, {{:"$1"}, [], [:"$_"]}], :code)

  \"""
  fn
    {v1, v2} -> v2
    tuple = {v1} -> tuple
  end
  \"""
  ```
  """
  defdelegate ms2fun(ms, mode), to: Ms2fun, as: :to_fun
end
