defmodule MatchSpec do
  @moduledoc """
  Elixir module to help you write matchspecs.

  contains functions which transform elixir-style functions into erlang matchspecs,
  and vice versa.

  ### Functions to matchspecs

  For transforming elixir-style functions into matchspecs, the following
  restrictions apply:

  - The function must use the `Kernel.fn/1` macro as its form, or use `defmatchspec/2`
    or `defmatchspec/3`, where the matchspecs form is similar to the `Kernel.fn/1` form.any()
  - The function must have arity 1.
  - The function may only use guards in its `when` section.
  - The function may only return a single expression that uses guard functions to
    transform matches.

  Furthermore, the following restrictions apply to binary pattern matching in the
  head of the function

  - the binary pattern may only consist of single bytes and strings
    - arbitrary bit-width bitstrings are not supported
    - conversions such as float are not supported.

  > #### Note {: .info}
  >
  > The restrictions on binary matching exist due to limitations on the BIFs
  > available to ets and may change in the future if OTP comes to support
  > these conversions in its kernel.
  """

  alias MatchSpec.Defmatchspec
  alias MatchSpec.Fun2ms
  alias MatchSpec.Ms2fun

  @doc """
  converts a function ast into an ets matchspec.

  The function must also be "`fn` ast"; you can't pass a shorthand lambda or
  a lambda to an existing lambda.

  The function lambda form is only used as a scaffolding to represent ets
  matching and filtering operations, by default it will not be instantiated
  into bytecode of the resulting module.

  ```elixir
  iex> require MatchSpec
  iex> MatchSpec.fun2ms(fn tuple = {k, v} when v > 1 and v < 10 -> tuple end)
  [{{:"$1", :"$2"}, [{:andalso, {:>, :"$2", 1}, {:<, :"$2", 10}}], [:"$_"]}]
  ```

  If you would also like the equivalent lambda, pass `with_fun: true` as an
  option and the `fun2ms/2` macro will emit a tuple of the matchspec and the
  lambda.

  ```elixir
  iex> {ms, fun} = MatchSpec.fun2ms(fn {:key, value} -> value end, with_fun: true)
  iex> :ets.test_ms({:key, "value"}, ms)
  {:ok, "value"}
  iex> fun.({:key, "value"})
  "value"
  ```

  This macro uses the same backend as `fun2msfun/4` and will emit the same
  matchspec as if you passed no parameters to `fun2msfun/4`
  """
  defmacro fun2ms(fun = {:fn, _, arrows}, opts \\ []) do
    matchspec = Fun2ms.from_arrows(arrows, caller: __CALLER__)

    if Keyword.get(opts, :with_fun) do
      {matchspec, fun}
    else
      matchspec
    end
  end

  @doc """
  converts a function into a function that generates a match spec based on
  bindings.  This can be used to either create an named function or an
  anonymous function.

  if you would like to use one of the free variables in your function as a part
  of the head of the match, you must pin it.

  if you omit the first parameter, it will create an anonymous function.

  Example with `:lambda` (default):

  ```elixir
  iex> require MatchSpec
  iex> lambda = MatchSpec.fun2msfun(:lambda, fn {key, value} when key === target -> value end, [target])
  iex> lambda.(:key)
  [{{:"$1", :"$2"}, [{:"=:=", :"$1", {:const, :key}}], [:"$2"]}]
  iex> lambda2 = MatchSpec.fun2msfun(fn {^key, value} -> value end, [key])
  iex> lambda2.(:key)
  [{{:"$1", :"$2"}, [{:"=:=", :"$1", {:const, :key}}], [:"$2"]}]
  ```

  Example with (`:def`/`:defp`):

  ```elixir
  require MatchSpec

  MatchSpec.fun2msfun(:def, :matchspec, fn {key, value} when key == target -> value end, [target])
  ```
  """
  defmacro fun2msfun(type \\ :lambda, name \\ nil, fun_ast, bindings) when is_atom(nil) do
    arrows =
      case fun_ast do
        {:fn, _, arrows} -> arrows
      end

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

        ms_ast = Fun2ms.from_arrows(arrows, bind: bindings, caller: __CALLER__)

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

        ms_ast = Fun2ms.from_arrows(arrows, bind: bindings, caller: __CALLER__)

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
  Writes a matchspec-generating function based on a body.

  You may provide multiple function bodies.

  This macro uses the same backend as `fun2msfun/4` and will generate
  identical code to that macro.

  Example:

  ```elixir
  use MatchSpec

  defmatchspec my_matchspec(value1, value2) do
    {key, ^value1, ^value} when key === :foo -> value == value2
  end
  ```

  This generates the equivalent to the following function:

  ```elixir
  def my_matchspec(value1, value2) do
    [{:"$1", :"$2", :"$3"}, [{:"=:=", :"$1", :foo}, {:"=:=", :"$2", value1}], [{:==, :"$3", {:const, value2}}]]
  end
  ```
  """
  defmacro defmatchspec(header, do: expr) do
    Defmatchspec.assert_used(__CALLER__, :defmatchspec)

    matchspec_body =
      :def
      |> Defmatchspec.struct_from(header, expr, __CALLER__)
      |> Macro.escape()

    quote bind_quoted: [matchspec_body: matchspec_body] do
      MatchSpec.Defmatchspec.assert_consistent(matchspec_body, @match_spec_bodies)
      @match_spec_bodies matchspec_body
    end
  end

  @doc """
  Writes a matchspec-generating function based on a body.

  You may provide multiple function bodies.

  This macro uses the same backend as `fun2msfun/4` and will generate
  identical code.

  see `defmatchspec/2` for details

  """
  defmacro defmatchspecp(header, do: expr) do
    Defmatchspec.assert_used(__CALLER__, :defmatchspecp)

    matchspec_body =
      :defp
      |> Defmatchspec.struct_from(header, expr, __CALLER__)
      |> Macro.escape()

    quote bind_quoted: [matchspec_body: matchspec_body] do
      MatchSpec.Defmatchspec.assert_consistent(matchspec_body, @match_spec_bodies)
      @match_spec_bodies matchspec_body
    end
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
      @before_compile Defmatchspec
      import MatchSpec, only: [defmatchspec: 2, defmatchspecp: 2]
    end
  end
end
