defmodule MatchSpec.Fun2ms do
  @moduledoc false
  # to make debugging less insane
  @derive {Inspect, except: [:caller]}
  @enforce_keys [:caller]
  defstruct @enforce_keys ++ [:head, bindings: %{}, conditions: [], body: [], top_pins: [], in: :arg]

  @type t :: %__MODULE__{
          caller: Macro.Env.t(),
          bindings: %{optional(atom) => pos_integer | :"$_" | var_ast},
          head: nil | head_ast,
          conditions: nil | condition_ast,
          body: nil | body_ast,
          top_pins: [Macro.t()],
          # which phase of analysis we're in:
          in: :arg | :when | :expr
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
      unquote(argument_error_warning(state))
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
    head_matches = find_head_matches(arg_ast, %{top: [], pattern: :_}, state)

    head_matches.top
    |> Enum.reduce(state, &bind_top_var/2)
    |> bind_head_match(head_matches.pattern)
  end

  defp find_head_matches({:=, _, [lhs, rhs]}, matches, state) do
    Enum.reduce([lhs, rhs], matches, &find_head_matches(&1, &2, state))
  end

  defp find_head_matches(pinned_var = {:^, _, _}, matches, _state) do
    %{matches | top: [pinned_var | matches.top], pattern: pinned_var}
  end

  defp find_head_matches({name, _, tag}, matches, _state) when is_atom(tag) do
    %{matches | top: [name | matches.top]}
  end

  defp find_head_matches(other, matches = %{pattern: :_}, _state) do
    %{matches | pattern: other}
  end

  defp find_head_matches(other, matches, state) do
    raise CompileError,
      description:
        "only one structured pattern match allowed, multiple structured heads found: `#{Macro.to_string(other)}` and `#{Macro.to_string(matches.pattern)}`",
      file: state.caller.file,
      line: state.caller.line
  end

  @spec bind_top_var(atom, t) :: t
  # don't bind top vars that are pins of a function variable, but register them as a top pin.
  defp bind_top_var({:^, _, [pin = {_name, _, tag}]}, state) when is_atom(tag),
    do: %{state | top_pins: [pin | state.top_pins]}

  # for other top vars:
  defp bind_top_var(var, state) do
    if is_map_key(state.bindings, var) do
      IO.warn("unpinned variable `#{var}` in function match head has the same name as a binding")
    end

    case Atom.to_string(var) do
      "_" <> _ ->
        # don't bother binding since this is an ignored parameter.
        %{state | head: :_}

      _ ->
        # still safe to ignore matching on the head because subsequent uses of the variable
        # will use "whole match" idiom.
        %{state | head: :_, bindings: Map.put(state.bindings, var, :"$_")}
    end
  end

  @spec bind_head_match(t, arg_ast) :: t
  defp bind_head_match(state, arg_ast) do
    {head_ast, new_state} = translate_arg(arg_ast, state)
    %{new_state | head: head_ast}
  end

  @spec translate_arg(arg_ast, t) :: {head_ast, t}
  defp translate_arg({:^, _, [{var, _, tag}]}, state) when is_atom(tag) do
    vars =
      state.bindings
      |> Map.values()
      |> Enum.flat_map(&List.wrap(if match?({_, _, _}, &1), do: elem(&1, 0)))

    case Map.fetch(state.bindings, var) do
      {:ok, var_ast} ->
        {var_ast, state}

      _ ->
        raise CompileError,
          description: "pin requires a bound variable (got #{var}, found: #{inspect(vars)})",
          file: state.caller.file,
          line: state.caller.line
    end
  end

  defp translate_arg({var, _, tag}, state) when is_atom(tag) do
    if String.starts_with?(Atom.to_string(var), "_") do
      {:_, state}
    else
      # add the variable to the collection of known bindings
      index =
        case state.bindings do
          %{^var => index} when is_integer(index) ->
            index

          %{^var => {_, _, _}} ->
            IO.warn(
              "unpinned variable `#{var}` in function match head has the same name as a binding"
            )

            lowest_index(state.bindings)

          _ ->
            lowest_index(state.bindings)
        end

      {:"$#{index}", %{state | bindings: Map.put(state.bindings, var, index)}}
    end
  end

  # a twople is a special case
  defp translate_arg({a, b}, state) do
    {match_list, state} = translate_arg([a, b], state)
    {List.to_tuple(match_list), state}
  end

  defp translate_arg({:{}, _, tuple_list}, state) do
    {match_list, state} = translate_arg(tuple_list, state)
    {to_tuple_ast(match_list), state}
  end

  defp translate_arg(list, state) when is_list(list) do
    Enum.map_reduce(list, state, &translate_arg/2)
  end

  defp translate_arg({:%, _, [aliasing, map]}, state) do
    {map_part, new_state} = translate_arg(map, state)
    {{:%, [], [aliasing, map_part]}, new_state}
  end

  defp translate_arg({:%{}, _, map}, state) do
    {match_list, state} =
      Enum.map_reduce(map, state, fn
        {k, v}, state ->
          {v_encoded, new_state} = translate_arg(v, state)
          {{k, v_encoded}, new_state}
      end)

    {{:%{}, [], match_list}, state}
  end

  defp translate_arg(literal, state) when is_number(literal) or is_binary(literal) do
    {literal, state}
  end

  defp translate_arg(atom, state) when is_atom(atom) do
    {atom, state}
  end

  defp lowest_index(bindings) do
    bindings
    |> Map.values()
    |> Enum.reject(&(match?({_, _, _}, &1) or &1 == :"$_"))
    |> case do
      [] -> 1
      list -> Enum.max(list) + 1
    end
  end

  @spec set_condition(t, when_ast) :: t
  defp set_condition(state, when_ast) do
    %{state | conditions: Enum.map(when_ast, &expression_from(&1, %{state | in: :when}))}
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
        when: {:orelse, 2} # multiple when clauses in a match are equivalent to "or" 🤯
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

      variable = {_, _, _} ->
        {:const, variable}
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

  # creates argument error if a top-pin variable is not a tuple.
  @spec argument_error_warning(t) :: Macro.t()
  defp argument_error_warning(state) do
    Enum.map(
      state.top_pins,
      &quote bind_quoted: [match: &1] do
        unless is_tuple(match) do
          raise ArgumentError,
                "matching against the whole match must be a tuple, got pinned value `#{inspect(match)}`"
        end
      end
    )
  end

  # UTILITY functions

  # two-tuples are special cases.
  defp to_tuple_ast(tuple = {_, _}), do: tuple

  defp to_tuple_ast(tuple) when is_tuple(tuple) do
    {:{}, [], Tuple.to_list(tuple)}
  end

  defp to_tuple_ast(list) when is_list(list) do
    {:{}, [], list}
  end

  defp tuple_wrap(tuple_parts) do
    tuple_parts
    |> List.to_tuple()
    |> to_tuple_ast
    |> List.wrap()
    |> List.to_tuple()
    |> to_tuple_ast
  end
end
