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
    Fun2ms.from_fun_ast(fun_ast, caller: __CALLER__)
  end

  @doc """
  converts a function into a function that generates a match spec based on bindings.  This can
  be used to either create an named function or an anonymous function.

  Example (lambda, default):

  ```elixir
  iex> require MatchSpec
  iex> lambda = MatchSpec.fun2msfun(:lambda, fn {key, value} when key === target -> value end, [target])
  iex> lambda.(:key)
  [[{{:"$1", :"$2"}, [{:"=:=", :"$1", :key}], [:"$2"]}]]

  Example (def/defp):

  ```elixir
  require MatchSpec

  MatchSpec.fun2msfun(:def, :matchspec, fn {key, value} when key == target -> value end, [target])
  ```
  ```
  """
  defmacro fun2msfun(type \\ :lambda, name \\ nil, fun_ast, bindings) when is_atom(nil) do
    case type do
      type when type in [:def, :defp] ->
        unless name do
          raise CompileError,
            description: "def and defp fun2msfun invocations must have a name",
            file: __CALLER__.file,
            line: __CALLER__.line
        end

        if __CALLER__.function do
          raise CompileError,
            description: "def and defp fun2msfun invocations must be in the module body",
            file: __CALLER__.file,
            line: __CALLER__.line
        end

        if context = __CALLER__.context do
          raise CompileError,
            description: "def and defp fun2msfun invocations may not be in a #{context}",
            file: __CALLER__.file,
            line: __CALLER__.line
        end

        ms_ast = Fun2ms.from_fun_ast(fun_ast, bind: bindings, caller: __CALLER__)

        quote do
          unquote(type)(unquote(name)(unquote_splicing(bindings))) do
            unquote(ms_ast)
          end
        end

      :lambda ->
        if name do
          raise CompileError,
            description: "lambda fun2msfun invocations must not have a name",
            file: __CALLER__.file,
            line: __CALLER__.line
        end

        # it should be ok to run it from IEx or outside of a module in general.
        unless !__CALLER__.module or __CALLER__.function do
          raise CompileError,
            description: "lambda fun2msfun invocations must be in a function body",
            file: __CALLER__.file,
            line: __CALLER__.line
        end

        if context = __CALLER__.context do
          raise CompileError,
            description: "lambda fun2msfun invocations may not be in a #{context}",
            file: __CALLER__.file,
            line: __CALLER__.line
        end

        ms_ast = Fun2ms.from_fun_ast(fun_ast, bind: bindings, caller: __CALLER__)

        quote do
          fn unquote_splicing(bindings) ->
            unquote(ms_ast)
          end
        end

      _ ->
        raise CompileError,
          description: "fun2msfun must be one of `:lambda`, `:def`, `:defp`",
          file: __CALLER__.file,
          line: __CALLER__.line
    end
  end

  @doc """
  Writes a matchspec-generating function based on a body.  You may provide multiple function bodies.
  This is syntactic sugar for using matchspec

  Example:

  ```elixir
  use MatchSpec

  defmatchspec my_matchspec(value1, value2)({key, value1, value}) when key === :foo do
    value == value2
  end
  ```

  This generates the equivalent to the following function:

  ```elixir
  def my_matchspec(value1, value2) do
    [{:"$1", value1, :"$2"}, [{:"=:=", :"$1", :foo}], [{:==, :"$2", {:const, value2}}]]
  end
  """
  defmacro defmatchspec({{name, _, bindings}, _, [match]}, do: expr) do
    assert_used(__CALLER__, :defmatchspec)

    [bindings, match, expr, caller] =
      Enum.map([bindings, match, expr, __CALLER__], &Macro.escape/1)

    quote bind_quoted: [name: name, bindings: bindings, match: match, expr: expr, caller: caller] do
      @match_spec_bodies {name, :def, bindings, match, expr, caller}
    end
  end

  defmacro defmatchspec({:when, _, [{{_matchspec_name, _, _vars}, _, [_match]}, _when_clause]},
             do: _do_expr
           ) do
    assert_used(__CALLER__, :defmatchspec)
  end

  @doc """
  Writes a matchspec-generating function based on a body.  You may provide multiple function bodies.
  This is syntactic sugar for using matchspec

  Example:

  ```elixir
  use MatchSpec

  defmatchspec my_matchspec(value1, value2)({key, value1, value}) when key === :foo do
    value == value2
  end
  ```

  This generates the equivalent to the following function:

  ```elixir
  def my_matchspec(value1, value2) do
    [{:"$1", value1, :"$2"}, [{:"=:=", :"$1", :foo}], [{:==, :"$2", {:const, value2}}]]
  end
  """
  defmacro defmatchspecp({{_matchspec_name, _, _vars}, _, [_match]}, do: _do_expr) do
    assert_used(__CALLER__, :defmatchspecp)
  end

  defmacro defmatchspecp({:when, _, [{{_matchspec_name, _, _vars}, _, [_match]}, _when_clause]},
             do: _do_expr
           ) do
    assert_used(__CALLER__, :defmatchspecp)
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

  defmacro __using__(_opts) do
    module = __CALLER__.module
    Module.register_attribute(module, :match_spec_bodies, accumulate: true)

    quote do
      @before_compile MatchSpec
      import MatchSpec, only: [defmatchspec: 2, defmatchspecp: 2]
    end
  end

  defmacro __before_compile__(env) do
    env.module
    |> Module.get_attribute(:match_spec_bodies)
    |> Enum.group_by(&elem(&1, 0))
    |> dbg

    quote do
      :ok
    end
  end

  defp assert_used(env, type) do
    unless Module.get_attribute(env.module, :match_spec_bodies) do
      raise CompileError,
        description: "#{type} may only be used if you have `use MatchSpec` in the module",
        file: env.file,
        line: env.line
    end
  end

  def _macro_inspect(macro) do
    macro
    |> Macro.to_string()
    |> IO.puts()

    macro
  end
end
