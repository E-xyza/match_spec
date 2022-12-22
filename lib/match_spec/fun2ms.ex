defmodule MatchSpec.Fun2ms do
  defstruct [:match, bindings: %{}, filters: [], return: []]

  @type t :: %__MODULE__{
          bindings: %{optional(atom) => pos_integer | :_},
          match: atom | tuple,
          filters: list,
          return: list
        }

  def from_fun_ast({:fn, _, arrows}) do
    match_from_arrows(arrows)
  end

  defp match_from_arrows(arrows) do
    Enum.map(arrows, &match_arrow/1)
  end

  defp match_arrow({:->, _, [predicate, consequence]}) do
    arrow =
      %__MODULE__{}
      |> analyze_predicate(predicate)
      |> analyze_consequence(consequence)

    quote do
      {unquote(arrow.match), unquote(arrow.filters), unquote(arrow.return)}
    end
  end

  # case where we have filters
  defp analyze_predicate(state, [{:when, _, [match, filter]}]) do
    {match_spec, state} = analyze_match(match, state)
    filter_spec = List.wrap(analyze_filter(filter, state))
    %{state | match: match_spec, filters: filter_spec}
  end

  # case where we have no filters
  defp analyze_predicate(state, [match]) do
    {match_spec, state} = analyze_match(match, state)
    %{state | match: match_spec}
  end

  # attempting to bind variables at the top
  defp analyze_match({:=, _, [{var, _, tag}, rhs]}, state) when is_atom(tag) do
    {match_spec, state} =
      analyze_match(rhs, %{state | bindings: Map.put(state.bindings, var, :_)})

    {match_spec, %{state | match: match_spec}}
  end

  defp analyze_match({:=, _, [lhs, {var, _, tag}]}, state) when is_atom(tag) do
    {match_spec, state} =
      analyze_match(lhs, %{state | bindings: Map.put(state.bindings, var, :_)})

    {match_spec, %{state | match: match_spec}}
  end

  # whole variable bound at the top
  defp analyze_match({var, _, tag}, state) when is_atom(tag) do
    case Atom.to_string(var) do
      "_" <> _ ->
        {:_, state}

      _ ->
        {:"$_", %{state | bindings: %{var => :_}}}
    end
  end

  defp analyze_match(binding, state), do: analyze_binding(binding, state)

  defp analyze_binding({var, _, tag}, state) when is_atom(tag) do
    if String.starts_with?(Atom.to_string(var), "_") do
      {:_, state}
    else
      # add the binding to the tag
      index =
        case state.bindings do
          %{^var => index} ->
            index

          _ ->
            lowest_index(state.bindings)
        end

      {:"$#{index}", %{state | bindings: Map.put(state.bindings, var, index)}}
    end
  end

  # a twople is a special case
  defp analyze_binding({a, b}, state) do
    {match_list, state} = analyze_binding([a, b], state)
    {List.to_tuple(match_list), state}
  end

  defp analyze_binding({:{}, _, tuple_list}, state) do
    {match_list, state} = analyze_binding(tuple_list, state)
    {to_tuple_ast(match_list), state}
  end

  defp analyze_binding(list, state) when is_list(list) do
    Enum.map_reduce(list, state, &analyze_binding/2)
  end

  defp analyze_binding({:%, _, [aliasing, map]}, state) do
    {map_part, new_state} = analyze_binding(map, state)
    {{:%, [], [aliasing, map_part]}, new_state}
  end

  defp analyze_binding({:%{}, _, map}, state) do
    {match_list, state} =
      Enum.map_reduce(map, state, fn
        {k, v}, state ->
          {v_encoded, new_state} = analyze_binding(v, state)
          {{k, v_encoded}, new_state}
      end)

    {{:%{}, [], match_list}, state}
  end

  defp analyze_binding(literal, state) when is_number(literal) or is_binary(literal) do
    {literal, state}
  end

  defp lowest_index(bindings) do
    case Map.values(bindings) -- [:_] do
      [] -> 1
      list -> Enum.max(list) + 1
    end
  end

  # when a filter has another filter
  defp analyze_filter({:when, _, filters}, state) do
    Enum.flat_map(filters, &List.wrap(analyze_filter(&1, state)))
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
    defp analyze_filter({unquote(guard), _, args}, state) when length(args) == unquote(arity) do
      translated_args = Enum.map(args, &analyze_filter(&1, state))
      to_tuple_ast([unquote(guard) | translated_args])
    end
  end

  defp analyze_filter({:is_map_key, _, [map, key]}, state) do
    # note in erlang is_map_key takes params (key, map)
    to_tuple_ast({:is_map_key, analyze_filter(key, state), analyze_filter(map, state)})
  end

  defp analyze_filter({:elem, _, [tup, idx]}, state) do
    to_tuple_ast(
      case idx do
        int when is_integer(int) ->
          {:element, analyze_filter(tup, state), int + 1}

        {_, _, _} ->
          {:element, analyze_filter(tup, state),
           to_tuple_ast({:+, analyze_filter(idx, state), 1})}
      end
    )
  end

  # dot syntax for map dereferencing
  defp analyze_filter({{:., _, [var, deref]}, _, []}, state) when is_atom(deref) do
    to_tuple_ast({:map_get, deref, analyze_filter(var, state)})
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
    defp analyze_filter({unquote(exguard), _, args}, state) when length(args) == unquote(arity) do
      translated_args = Enum.map(args, &analyze_filter(&1, state))
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
    defp analyze_filter({{:., _, [:erlang, unquote(guard)]}, _, args}, state)
         when length(args) == unquote(arity) do
      translated_args = Enum.map(args, &analyze_filter(&1, state))

      to_tuple_ast([unquote(guard) | translated_args])
    end
  end

  defp analyze_filter({var, _, tag}, state) when is_atom(tag) do
    :"$#{Map.fetch!(state.bindings, var)}"
  end

  defp analyze_filter(number, _state) when is_number(number), do: number

  defp analyze_consequence(state, consequence) do
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
