defmodule MatchSpec.Fun2ms do
  @moduledoc false
  # to make debugging less insane
  @derive {Inspect, except: [:caller]}
  defstruct [:head, :caller, bindings: %{}, conditions: [], body: []]

  @type t :: %__MODULE__{
          caller: Macro.Env.t(),
          bindings: %{optional(atom) => pos_integer | :"$_" | var_ast},
          head: nil | head_ast,
          conditions: nil | condition_ast,
          body: nil | body_ast
        }

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

  @spec from_fun_ast(Macro.t(), keyword) :: Macro.t()
  def from_fun_ast({:fn, _, arrows}, opts) do
    Enum.map(arrows, fn arrow ->
      arrow
      |> part_ast_from_arrow
      |> from_part(opts)
    end)
  end

  defp part_ast_from_arrow({:->, _, [argument, expr_ast]}) do
    {arg_ast, when_ast} = arg_when_from_argument(argument)
    {arg_ast, when_ast, expr_ast}
  end

  @spec arg_when_from_argument(Macro.t()) :: {arg_ast, when_ast}
  defp arg_when_from_argument([{:when, _, [arg_ast, when_ast]}]), do: {arg_ast, [when_ast]}

  defp arg_when_from_argument([arg_ast]), do: {arg_ast, []}

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
      {unquote(state.head), unquote(state.conditions), unquote(state.body)}
    end
  end

  defp load_bindings(state, opts) do
    opts
    |> Keyword.get(:bind, [])
    |> Enum.reduce(state, fn binding = {var, _, _atom}, state_so_far ->
      new_bindings = Map.put(state_so_far.bindings, var, binding)
      %{state_so_far | bindings: new_bindings}
    end)
  end

  # generic matching, but not at the top.
  @spec set_head(t, arg_ast) :: t
  # attempting to bind variables at the top
  defp set_head(state, {:=, _, [lhs, rhs]}) do
    case {lhs, rhs} do
      # for both of these cases, bind_top_var must take precedence because
      # the non var-assignment must shadow top_var which is always available
      # as :"$_"
      {{var, _, tag}, _} when is_atom(tag) ->
        state
        |> bind_top_var(var)
        |> set_head(rhs)

      {_, {var, _, tag}} when is_atom(tag) ->
        state
        |> bind_top_var(var)
        |> set_head(lhs)

      _ ->
        # TODO: should we do a resolution on this?
        raise "unsupported head argument matching"
    end
  end

  ## whole variable bound at the top, not a structured datatype.
  defp set_head(state, {var, _, tag}) when is_atom(tag) do
    bind_top_var(state, var)
  end

  defp set_head(state, binding) do
    {head_ast, new_state} = bind_to(binding, state)
    %{new_state | head: head_ast}
  end

  @spec bind_top_var(t, atom) :: t
  defp bind_top_var(state, var) do
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

  @spec bind_to(arg_ast, t) :: {head_ast, t}
  defp bind_to({:^, _, [{var, _, tag}]}, state) when is_atom(tag) do
    vars =
      state.bindings
      |> Map.values()
      |> Enum.flat_map(&List.wrap(if match?({_, _, _}, &1), do: elem(&1, 0)))

    case Map.fetch(state.bindings, var) do
      {:ok, var_ast} ->
        {var_ast, state}

      _ ->
        raise CompileError,
          description: "pin requires a bound variable (got #{var}, found: #{inspect(vars)}",
          file: state.caller.file,
          line: state.caller.line
    end
  end

  defp bind_to({var, _, tag}, state) when is_atom(tag) do
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
  defp bind_to({a, b}, state) do
    {match_list, state} = bind_to([a, b], state)
    {List.to_tuple(match_list), state}
  end

  defp bind_to({:{}, _, tuple_list}, state) do
    {match_list, state} = bind_to(tuple_list, state)
    {to_tuple_ast(match_list), state}
  end

  defp bind_to(list, state) when is_list(list) do
    Enum.map_reduce(list, state, &bind_to/2)
  end

  defp bind_to({:%, _, [aliasing, map]}, state) do
    {map_part, new_state} = bind_to(map, state)
    {{:%, [], [aliasing, map_part]}, new_state}
  end

  defp bind_to({:%{}, _, map}, state) do
    {match_list, state} =
      Enum.map_reduce(map, state, fn
        {k, v}, state ->
          {v_encoded, new_state} = bind_to(v, state)
          {{k, v_encoded}, new_state}
      end)

    {{:%{}, [], match_list}, state}
  end

  defp bind_to(literal, state) when is_number(literal) or is_binary(literal) do
    {literal, state}
  end

  defp bind_to(atom, state) when is_atom(atom) do
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
    %{state | conditions: Enum.map(when_ast, &expression_from(&1, state))}
  end

  @spec set_body(t, body_ast) :: t
  defp set_body(state, body_ast) do
    %{state | body: [expression_from(body_ast, state)]}
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
        !==: {:"=/=", 2}
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
