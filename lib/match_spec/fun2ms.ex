defmodule MatchSpec.Fun2ms do
  @moduledoc false
  alias MatchSpec.Fun2ms.ConditionExpression
  alias MatchSpec.Fun2ms.Head
  alias MatchSpec.Tools
  import Tools

  # to make debugging less insane
  @derive {Inspect, except: [:caller]}
  @enforce_keys [:caller]
  defstruct @enforce_keys ++
              [
                :head,
                bindings: %{},
                conditions: [],
                body: [],
                pins: %{},
                preflight_checks: [],
                in: :arg
              ]

  @type t :: %__MODULE__{
          caller: Macro.Env.t(),
          bindings: Tools.bindings(),
          pins: Tools.pins(),
          head: nil | head_ast,
          conditions: [condition_ast],
          body: [body_ast],
          # which phase of analysis we're in:
          in: :arg | :when | :expr,
          preflight_checks: [Macro.t()]
        }

  # these types represent ast types that correspond to the elixir ast of the function in
  # elixir fn-style lambda format.

  @typedoc "ast for a function argument match"
  @type arg_ast :: Macro.t()
  @typedoc "ast for a function when clause"
  @type when_ast :: Macro.t()
  @typedoc "ast for a function return expression"
  @type expr_ast :: Macro.t()

  # see https://www.erlang.org/doc/apps/erts/match_spec.html
  # names here align with the "informal grammar" section.any()

  @typedoc "ast for a matchspec match"
  @type head_ast :: Macro.t()
  @typedoc "ast for a matchspec condition"
  @type condition_ast :: [Macro.t()]
  @typedoc "ast for a matchspec body"
  @type body_ast :: [Macro.t()]

  @typedoc "ast for a bindable variable"
  @type var_ast :: {name :: atom, meta :: keyword, context :: atom}
  @typedoc "ast for a function part, which may have come from a lambda definition or a def/defp"
  @type part_ast :: {arg_ast, when_ast, expr_ast}

  @spec from_arrows(Macro.t(), keyword) :: Macro.t()
  def from_arrows(arrows, opts) do
    Enum.map(arrows, fn arrow ->
      arrow
      |> part_ast_from_arrow(opts)
      |> from_part(opts)
    end)
  end

  defp part_ast_from_arrow({:->, _, [argument, expr_ast]}, opts) do
    {arg_ast, when_ast} = arg_when_from_argument(argument, opts)
    {arg_ast, when_ast, expr_ast}
  end

  @spec arg_when_from_argument(Macro.t(), keyword) :: {arg_ast, when_ast}
  defp arg_when_from_argument([{:when, _, when_params}], opts) do
    case when_params do
      [arg_ast, when_ast] ->
        {arg_ast, [when_ast]}

      _ ->
        %{file: file, line: line} = Keyword.fetch!(opts, :caller)

        raise CompileError,
          description:
            "function branches for matchspecs must have arity 1 (got arity #{length(when_params) - 1})",
          file: file,
          line: line
    end
  end

  defp arg_when_from_argument([arg_ast], _), do: {arg_ast, []}

  defp arg_when_from_argument(list, opts) when is_list(list) do
    %{file: file, line: line} = Keyword.fetch!(opts, :caller)

    raise CompileError,
      description:
        "function branches for matchspecs must have arity 1 (got arity #{length(list)})",
      file: file,
      line: line
  end

  @spec from_parts([part_ast], keyword) :: Macro.t()
  def from_parts(parts, opts) do
    Enum.map(parts, &from_part(&1, opts))
  end

  @spec from_part(part_ast, keyword) :: Macro.t()
  defp from_part({arg_ast, when_ast, expr_ast}, opts) do
    %__MODULE__{caller: Keyword.fetch!(opts, :caller)}
    |> load_bindings(opts)
    |> set_head(arg_ast)
    |> set_condition(when_ast)
    |> set_body(expr_ast)
    |> to_quoted
  end

  @spec to_quoted(t) :: Macro.t()
  defp to_quoted(state) do
    quote do
      unquote(Enum.reverse(state.preflight_checks))
      {unquote(state.head), unquote(state.conditions), unquote(state.body)}
    end
  end

  defp load_bindings(state, opts) do
    external_bindings =
      state.caller
      |> Macro.Env.vars()
      |> Map.new(fn {var, context} -> {var, {:external, {var, context}}} end)

    opts
    |> Keyword.get(:bind, [])
    |> Enum.reduce(%{state | bindings: external_bindings}, fn
      {var, _, _atom} = to_bind, state_so_far ->
        new_bindings = Map.put(state_so_far.bindings, var, to_bind)
        %{state_so_far | bindings: new_bindings}

      # constant values don't trigger registering a binding
      constant, state when is_atom(constant) or is_binary(constant) or is_number(constant) ->
        state
    end)
  end

  # generic matching, special cased to handle variables at the top which
  # might get matched to :"$_"
  @spec set_head(t, arg_ast) :: t
  # attempting to bind variables at the top
  defp set_head(state, arg_ast) do
    head = Head.from_arg_ast(arg_ast, state.bindings, state.caller)

    %{
      state
      | head: head.head_ast,
        pins: head.pins,
        bindings: head.bindings,
        preflight_checks: head.preflight_checks
    }
  end

  @spec set_condition(t, when_ast) :: t
  defp set_condition(state, when_ast) do
    pin_conditions =
      Enum.map(state.pins, fn
        {match_var, ast} -> to_tuple_ast({:"=:=", match_var, {:const, ast}})
      end)

    when_conditions = Enum.map(when_ast, &ConditionExpression.from_ast(&1, %{state | in: :when}))

    %{state | conditions: pin_conditions ++ when_conditions}
  end

  @spec set_body(t, body_ast) :: t
  defp set_body(state, {:__block__, _, _} = block) do
    raise CompileError,
      description: """
      function bodies for matchspecs must be a single result expression, got:

      #{Macro.to_string(block)}
      """,
      file: state.caller.file,
      line: state.caller.line
  end

  defp set_body(state, body_ast) do
    %{state | body: [ConditionExpression.from_ast(body_ast, %{state | in: :expr})]}
  end
end
