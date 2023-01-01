defmodule MatchSpec.Fun2ms do
  @moduledoc false
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
    opts
    |> Keyword.get(:bind, [])
    |> Enum.reduce(state, fn
      to_bind = {var, _, _atom}, state_so_far ->
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

    when_conditions = Enum.map(when_ast, &expression_from(&1, %{state | in: :when}))

    %{state | conditions: pin_conditions ++ when_conditions}
  end

  @spec set_body(t, body_ast) :: t
  defp set_body(state, block = {:__block__, _, _}) do
    raise CompileError,
      description: """
      function bodies for matchspecs must be a single result expression, got:

      #{Macro.to_string(block)}
      """,
      file: state.caller.file,
      line: state.caller.line
  end

  defp set_body(state, body_ast) do
    %{state | body: [expression_from(body_ast, %{state | in: :expr})]}
  end

  @spec expression_from(when_ast | expr_ast, t) :: condition_ast | body_ast

  guards = [
    is_atom: 1,
    is_float: 1,
    is_integer: 1,
    is_list: 1,
    is_number: 1,
    is_pid: 1,
    is_port: 1,
    is_reference: 1,
    is_tuple: 1,
    is_map: 1,
    is_binary: 1,
    is_function: 1,
    not: 1,
    abs: 1,
    hd: 1,
    length: 1,
    map_size: 1,
    node: 0,
    round: 1,
    size: 1,
    bit_size: 1,
    byte_size: 1,
    tl: 1,
    trunc: 1,
    binary_part: 3,
    +: 2,
    -: 2,
    *: 2,
    div: 2,
    rem: 2,
    self: 0,
    >: 2,
    >=: 2,
    <: 2,
    ==: 2
  ]

  for {guard, arity} <- guards do
    defp expression_from({unquote(guard), _, args}, state) when length(args) == unquote(arity) do
      translated_args = Enum.map(args, &expression_from(&1, state))
      to_tuple_ast([unquote(guard) | translated_args])
    end
  end

  defp expression_from({:is_map_key, _, [map, key]}, state) do
    # note in erlang is_map_key takes params (key, map)
    to_tuple_ast({:is_map_key, expression_from(key, state), expression_from(map, state)})
  end

  defp expression_from({:elem, _, [tup, idx]}, state) do
    to_tuple_ast(
      case idx do
        int when is_integer(int) ->
          {:element, int + 1, expression_from(tup, state)}

        {_, _, _} ->
          {:element, to_tuple_ast({:+, expression_from(idx, state), 1}),
           expression_from(tup, state)}
      end
    )
  end

  # dot syntax for map dereferencing
  defp expression_from({{:., _, [var, deref]}, _, []}, state) when is_atom(deref) do
    to_tuple_ast({:map_get, deref, expression_from(var, state)})
  end

  # guards with names that are different between matchspec and elixir
  for {exguard, {msguard, arity}} <- [
        and: {:andalso, 2},
        or: {:orelse, 2},
        <=: {:"=<", 2},
        ===: {:"=:=", 2},
        !=: {:"/=", 2},
        !==: {:"=/=", 2},
        # multiple when clauses in a match are equivalent to "or" 🤯
        when: {:orelse, 2}
      ] do
    defp expression_from({unquote(exguard), _, args}, state)
         when length(args) == unquote(arity) do
      translated_args = Enum.map(args, &expression_from(&1, state))
      to_tuple_ast([unquote(msguard) | translated_args])
    end
  end

  # direct usage of erlang guards
  erlangfunctions =
    guards ++
      [
        is_map_key: 2,
        is_record: 2,
        and: 2,
        or: 2,
        element: 1,
        map_get: 2,
        andalso: 2,
        orelse: 2,
        band: 2,
        bor: 2,
        bxor: 2,
        bnot: 2,
        bsl: 2,
        bsr: 2,
        "=<": 2,
        "=:=": 2,
        "/=": 2,
        "=/=": 2
      ]

  for {guard, arity} <- erlangfunctions do
    defp expression_from({{:., _, [:erlang, unquote(guard)]}, _, args}, state)
         when length(args) == unquote(arity) do
      translated_args = Enum.map(args, &expression_from(&1, state))

      to_tuple_ast([unquote(guard) | translated_args])
    end
  end

  defp expression_from({var, _, tag}, state) when is_atom(tag) do
    case Map.fetch!(state.bindings, var) do
      :"$_" ->
        :"$_"

      int when is_integer(int) ->
        :"$#{int}"

      var when is_var_ast(var) ->
        {:const, var}

      part = {:{}, _, [:binary_part | _]} ->
        part
    end
  end

  # tuples
  defp expression_from({a, b}, state) do
    [a, b]
    |> Enum.map(&expression_from(&1, state))
    |> tuple_wrap
  end

  defp expression_from({:{}, _, tuple_parts}, state) do
    tuple_parts
    |> Enum.map(&expression_from(&1, state))
    |> tuple_wrap
  end

  # maps
  defp expression_from({:%{}, _, map_parts}, state) do
    parts = Enum.map(map_parts, fn {k, v} -> {k, expression_from(v, state)} end)
    {:%{}, [], parts}
  end

  # structs
  defp expression_from({:%, _, [alias_part, map_part]}, state) do
    {:%, [], [alias_part, expression_from(map_part, state)]}
  end

  defp expression_from(atom, _state) when is_atom(atom) do
    case Atom.to_string(atom) do
      "$" <> _ -> {:const, atom}
      _ -> atom
    end
  end

  defp expression_from(number, _state) when is_number(number), do: number

  @part_name %{when: "when clause", expr: "result expression"}

  defp expression_from(call = {_, _, args}, state) when is_list(args) do
    case Macro.expand(call, %{state.caller | context: :guard}) do
      ^call ->
        part_name = Map.fetch!(@part_name, state.in)

        raise CompileError,
          description: "non-guard function found in #{part_name}: `#{Macro.to_string(call)}`",
          file: state.caller.file,
          line: state.caller.line

      guard ->
        expression_from(guard, state)
    end
  end
end
