defmodule MatchSpec.Fun2ms do
  @moduledoc false
  defstruct [:match, :caller, bindings: %{}, filters: [], return: []]

  @type var_ast :: {atom, list, atom}
  @type t :: %__MODULE__{
          caller: Macro.Env.t(),
          bindings: %{optional(atom) => pos_integer | :_ | var_ast},
          match: atom | tuple,
          filters: list,
          return: list
        }

  def from_fun_ast({:fn, _, arrows}, opts) do
    match_from_arrows(arrows, opts)
  end

  defp match_from_arrows(arrows, opts) do
    Enum.map(arrows, &match_arrow(&1, opts))
  end

  defp match_arrow({:->, _, [predicate, consequence]}, opts) do
    arrow =
      %__MODULE__{caller: Keyword.fetch!(opts, :caller)}
      |> load_bindings(opts)
      |> set_predicate(predicate)
      |> set_consequence(consequence)

    quote do
      {unquote(arrow.match), unquote(arrow.filters), unquote(arrow.return)}
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

  # case where we have filters
  defp set_predicate(state, [{:when, _, [match, filter]}]) do
    {match_spec, state} = set_match(match, state)
    filter_spec = List.wrap(set_filter(filter, state))
    %{state | match: match_spec, filters: filter_spec}
  end

  # case where we have no filters
  defp set_predicate(state, [match]) do
    {match_spec, state} = set_match(match, state)
    %{state | match: match_spec}
  end

  # attempting to bind variables at the top, rhs
  defp set_match({:=, _, [{var, _, tag}, rhs]}, state) when is_atom(tag) do
    {match_spec, state} =
      set_match(rhs, %{state | bindings: Map.put_new(state.bindings, var, :_)})

    {match_spec, %{state | match: match_spec}}
  end

  # attempting to bind variables at the top, lhs
  defp set_match({:=, _, [lhs, {var, _, tag}]}, state) when is_atom(tag) do
    {match_spec, state} =
      set_match(lhs, %{state | bindings: Map.put_new(state.bindings, var, :_)})

    {match_spec, %{state | match: match_spec}}
  end

  # whole variable bound at the top
  defp set_match({var, _, tag}, state) when is_atom(tag) do
    if is_map_key(state.bindings, var) do
      IO.warn("unpinned variable `#{var}` in function match head has the same name as a binding")
    end

    case Atom.to_string(var) do
      "_" <> _ ->
        {:_, state}

      _ ->
        {:_, %{state | bindings: Map.put(state.bindings, var, :_)}}
    end
  end

  # generic matching, but not at the top.
  defp set_match(binding, state), do: set_binding(binding, state)

  defp set_binding({:^, _, [{var, _, tag}]}, state) when is_atom(tag) do
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

  defp set_binding({var, _, tag}, state) when is_atom(tag) do
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
  defp set_binding({a, b}, state) do
    {match_list, state} = set_binding([a, b], state)
    {List.to_tuple(match_list), state}
  end

  defp set_binding({:{}, _, tuple_list}, state) do
    {match_list, state} = set_binding(tuple_list, state)
    {to_tuple_ast(match_list), state}
  end

  defp set_binding(list, state) when is_list(list) do
    Enum.map_reduce(list, state, &set_binding/2)
  end

  defp set_binding({:%, _, [aliasing, map]}, state) do
    {map_part, new_state} = set_binding(map, state)
    {{:%, [], [aliasing, map_part]}, new_state}
  end

  defp set_binding({:%{}, _, map}, state) do
    {match_list, state} =
      Enum.map_reduce(map, state, fn
        {k, v}, state ->
          {v_encoded, new_state} = set_binding(v, state)
          {{k, v_encoded}, new_state}
      end)

    {{:%{}, [], match_list}, state}
  end

  defp set_binding(literal, state) when is_number(literal) or is_binary(literal) do
    {literal, state}
  end

  defp set_binding(atom, state) when is_atom(atom) do
    {atom, state}
  end

  defp lowest_index(bindings) do
    bindings
    |> Map.values()
    |> Enum.reject(&(match?({_, _, _}, &1) or &1 == :_))
    |> case do
      [] -> 1
      list -> Enum.max(list) + 1
    end
  end

  # when a filter has another filter
  defp set_filter({:when, _, filters}, state) do
    Enum.flat_map(filters, &List.wrap(set_filter(&1, state)))
  end

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
    defp set_filter({unquote(guard), _, args}, state) when length(args) == unquote(arity) do
      translated_args = Enum.map(args, &set_filter(&1, state))
      to_tuple_ast([unquote(guard) | translated_args])
    end
  end

  defp set_filter({:is_map_key, _, [map, key]}, state) do
    # note in erlang is_map_key takes params (key, map)
    to_tuple_ast({:is_map_key, set_filter(key, state), set_filter(map, state)})
  end

  defp set_filter({:elem, _, [tup, idx]}, state) do
    to_tuple_ast(
      case idx do
        int when is_integer(int) ->
          {:element, int + 1, set_filter(tup, state)}

        {_, _, _} ->
          {:element, to_tuple_ast({:+, set_filter(idx, state), 1}), set_filter(tup, state)}
      end
    )
  end

  # dot syntax for map dereferencing
  defp set_filter({{:., _, [var, deref]}, _, []}, state) when is_atom(deref) do
    to_tuple_ast({:map_get, deref, set_filter(var, state)})
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
    defp set_filter({unquote(exguard), _, args}, state) when length(args) == unquote(arity) do
      translated_args = Enum.map(args, &set_filter(&1, state))
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
    defp set_filter({{:., _, [:erlang, unquote(guard)]}, _, args}, state)
         when length(args) == unquote(arity) do
      translated_args = Enum.map(args, &set_filter(&1, state))

      to_tuple_ast([unquote(guard) | translated_args])
    end
  end

  defp set_filter({var, _, tag}, state) when is_atom(tag) do
    :"$#{Map.fetch!(state.bindings, var)}"
  end

  defp set_filter(atom, _state) when is_atom(atom), do: {:const, atom}

  defp set_filter(number, _state) when is_number(number), do: number

  defp set_consequence(state, consequence) do
    return = [make_term(consequence, state)]
    %{state | return: return}
  end

  defp make_term({var, _, tag}, state) when is_atom(tag) do
    index = Map.fetch!(state.bindings, var)
    :"$#{index}"
  end

  defp make_term({:{}, _, terms}, state) do
    # tuples must be wrapped inside of tuples so they aren't confused for
    # functions.
    inner_tuple =
      terms
      |> Enum.map(&make_term(&1, state))
      |> List.to_tuple()
      |> to_tuple_ast

    to_tuple_ast({inner_tuple})
  end

  defp make_term({:%{}, _, terms}, state) do
    rewritten_terms = Enum.map(terms, fn {k, v} -> {k, make_term(v, state)} end)
    {:%{}, [], rewritten_terms}
  end

  defp make_term({:%, _, [aliasing, map]}, state) do
    {:%, [], [aliasing, make_term(map, state)]}
  end

  defp make_term(atom, _state) when is_atom(atom) do
    case Atom.to_string(atom) do
      "$" <> _ -> {:literal, atom}
      _ -> atom
    end
  end

  defp to_tuple_ast(tuple) when is_tuple(tuple) do
    {:{}, [], Tuple.to_list(tuple)}
  end

  defp to_tuple_ast(list) when is_list(list) do
    {:{}, [], list}
  end
end
